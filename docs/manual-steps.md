# 手作業の手順

autoinstall とスクリプトで自動化できない作業と、自動化が効かなかったときの手順。SPEC.md §5.3 に対応する。

## 0. インストール用 USB を作る(作業用の PC で)

Linux か WSL で行う。xorriso と python3-yaml が要る。

1. `autoinstall/env.example.yaml` を `autoinstall/env.yaml` にコピーし、実値を入れる
   - `keyboard_layout` は RDP で使う人のキーボードに合わせる(101/104 の英字配列なら `us`、106/109 なら `jp`)
   - `network` は固定 IP なら `mode: static` とアドレス・ゲートウェイ・DNS を書く。有線 LAN が 2 つ以上ある機種では `interface` に名前(`enp3s0` など)を書く
   - `ntp_servers` は、社内から ntp.ubuntu.com に届かないときだけ書く
   - `proxy` と `ca_certs` は、社内にプロキシや独自の CA 証明書があるときだけ書く
   - `editors` は入れたいエディター(vscode / neovim / zed)。`agent_ssh_authorized_keys` は SFTP で agent に入る人の公開鍵。`dev_ports` は手元の PC から開発サーバーを見るときのポート
   - `sysadmin.password_hash` は `mkpasswd -m sha-512` で作る
2. Ubuntu Desktop 26.04 LTS の ISO を用意し、次を実行する
   ```
   scripts/build-usb.sh ubuntu-26.04-desktop-amd64.iso agent-host.iso
   ```
3. できた `agent-host.iso` を USB メモリに書き込む(Rufus なら「DD イメージ」モード)

できた ISO と USB メモリには、パスワードハッシュと RDP のパスワードが入る。使い終わったら消す。

**注意:** この USB から起動すると、確認なしでディスク全体を消してインストールが始まる。対象以外の PC に挿したまま起動しない。インストールが終わって再起動したら、すぐに USB を抜く。

## 1. BIOS

- Restore on AC Power Loss(名称は機種による)を **Power On** にする
- HDMI ダミープラグを挿す。デスクトップ共有は実際の画面をそのまま映すので、RDP の解像度はプラグの解像度になる(手元からは変えられない)。1920×1080 のプラグを選ぶ(4K だと文字がとても小さい)

## 2. インストール

1. USB から起動する。確認画面は出ずにインストールが進む
2. 再起動後、初回起動時の構成(agent-host-provision.service)がネットワークから Node.js・Orca・Claude Code などを取得する。終わるまで GDM は起動しない
3. 構成が終わると agent で自動ログインし、first-login がデスクトップ共有を有効にする

構成の結果は SSH で確かめる。

```
journalctl -u agent-host-provision.service      # 構成の記録
sudo cat /home/agent/.local/state/agent-host/first-login.log   # first-login の記録
```

構成が失敗したときは、原因を直してから `sudo /opt/agent-host/provision.sh` で再実行する。

## 3. agent のログインキーリング(自動で効かなかったときだけ)

80-agent-session.sh は空パスワードのキーリングを最初から置く。first-login.log に `set-credentials` の失敗が出ていたら、これが効いていない。そのときは手でパスワードを空にする。

1. 物理画面(または一時的に別の手段)で agent のデスクトップを開く
2. 「パスワードと鍵」(seahorse。無ければ `sudo apt install seahorse`)を起動する
3. 「ログイン」キーリングを右クリック → パスワードの変更 → 新しいパスワードを空にする(平文で保存する警告には「続ける」)
4. ターミナルで `/opt/agent-host/first-login/first-login.sh` を実行する

## 4. デスクトップ共有(first-login が失敗したときだけ)

first-login が成功していれば不要。失敗していたら、agent のデスクトップで次を行う。

- 設定 → システム → リモートデスクトップ → 「デスクトップ共有」をオン、「リモート操作」をオン
- 認証情報(ユーザー名・パスワード)を env.yaml の `rdp` の値にする
- 「リモートログイン」は**オンにしない**(デスクトップ共有が 3390 番に移る)

## 5. Claude Code のログイン

RDP で agent のデスクトップに入り、ターミナルで `claude` を起動してログインする。

## 6. Codex のログイン

1. 事前に ChatGPT の設定 → セキュリティで「Codex、Excel、PowerPoint、Word のデバイスコードによるサインイン」を有効にする(Workspace なら管理者の権限設定)。有効でないと、`codex login --device-auth` は「ChatGPT のセキュリティ設定で…デバイスコードによるサインインを有効にしてから…もう一度実行してください」と出して止まる
2. ターミナルで `codex login --device-auth` を実行し、表示された URL とコードを手元の PC のブラウザで入力する(VirtualBox + RDP で確認済み)

## 7. Orca の初回起動

1. Orca は自動起動している。初回の案内に従う
2. `~/.claude` / `~/.codex` の設定を取り込む
3. Settings → Privacy の「Share anonymous usage data」をオフにする(環境変数 ORCA_TELEMETRY_DISABLED=1 でも止めているが、設定にも残す)
4. Settings → Notifications の「Update available」をオフにする。.deb 版は自分では更新しない。更新の確認の通信そのものは止められない(HANDOVER.md)

## 8. GitHub の認証(push する場合)

どのアカウントで認証するかを先に決める(エージェント専用のアカウントか、権限を絞ったトークンが無難)。RDP で agent の端末から:

```
gh auth login        # GitHub.com → HTTPS → ブラウザ(デバイスコード)で認証
gh auth setup-git    # git の push に gh の認証を使う
gh auth status
```

## 9. Docker Hub へのログイン

社内から 1 つの IP でまとめて外に出ると、ログインなしの Docker Hub からの取得は 6 時間に 100 回までで、エージェントが使うとすぐ当たる。RDP で agent の端末から `docker login` する(アクセストークンを使う)。

## 10. ファイルのやり取り(SFTP)

env.yaml の `agent_ssh_authorized_keys` に公開鍵を書いた人は、WinSCP などで agent に SFTP で入れる(シェルには入れない)。

- ホスト: `<ホスト>`、ポート 22、ユーザー `agent`、認証は秘密鍵
- 作業の置き場所は `/home/agent/work`

小さなファイルは、RDP のクリップボードでのコピー&貼り付けでも渡せる(VirtualBox では未確認)。

## 11. 追加のエージェントのログイン(env.yaml の agents で選んだものだけ)

RDP で agent の端末から行う。

- OpenCode: `opencode auth login` で、使うモデルのプロバイダーの API キーや OAuth を設定する
- GitHub Copilot CLI: `copilot` を起動し `/login` → デバイスコード(github.com/login/device)。Copilot の契約が要る
- Antigravity CLI: `agy` を起動し、表示された URL を手元のブラウザで開き、得たコードを端末に貼り付ける。テレメトリはアカウント側の `/config` で切り替える

## 12. 通知の確認(env.yaml の notify を書いた場合)

```
agent-notify approval テスト "通知のテストです"
```

Slack と IP Messenger の両方に届くことを確かめる(done は Slack だけ)。IP Messenger の受け取り側の PC は、UDP 2425 番の受信を許可しておく。

## 13. スマホからの操作(Claude Code の Remote Control)

Claude Code に Pro / Max / Team / Enterprise のアカウントでログインしているときだけ使える。通信は Anthropic のサービスを通る。

1. RDP で agent の端末から、作業するディレクトリで `claude remote-control`(または動いているセッションで `/remote-control`)。初回は確認に `y` で答える
2. 表示された URL か QR コードを、スマホの Claude アプリか claude.ai/code で開く
3. スマホへのプッシュ通知: Claude アプリに同じアカウントでログインし、端末で `/config` から「Push when actions required」などをオンにする

## 14. RDP の接続の設定

`docs/agent-host.rdp.example` をコピーして `full address` をホスト名に直し、ダブルクリックで接続する。

- Windows キーを常にホストへ送る(`keyboardhook:i:1`)。Super+Space などが使える
- クリップボードを共有する。手元とホストの間でコピーと貼り付けができる
- 初回の証明書の警告で「このコンピューターへの接続について今後確認しない」を選ぶと、次から出ない
- **デスクトップ共有は 1 つの画面を全員で共有する。2 人が同時に入ると操作がぶつかるので、入る前に一声かける**

使い勝手:

- 日本語入力は Ctrl+Space、スクリーンショットは Ctrl+Shift+Alt+S(PrintScreen は手元の Windows に取られることがある)。撮った画像はクリップボードに入るので、Claude Code に Ctrl+V で貼れる
- 上部のバーの Clipboard Indicator から、コピーの履歴を選んで貼れる
- 端末(Ctrl+Alt+T)は Xfce Terminal。右クリックで貼り付け、選択でコピー
- Caps Lock はホストでは何もしない(RDP で手元と状態がずれるため)。大文字は Shift で打つ
- 接続の設定の色は 24 ビット(同じ 26.04 で、mstsc の 32 ビットは遅いという報告がある)

## 15. 環境を入れ替える(OS の入れなおし、機種の交換)

ホストの身元(SSH のホスト鍵、RDP の証明書)、ログインと設定、`~/work` と Orca の worktree を移す。ツールの本体、mise の言語、Docker のイメージ、Chrome のプロファイルは移さない(作りなおせる)。

1. Orca とエージェントの作業を止める(書き出しの途中で書き換わらないように)
2. 手元の PC(Linux、WSL、Git Bash)で書き出す。ホストには保存されない。sudo のパスワードは標準入力の先頭の 1 行で渡す(標準入力は書き出しの受け渡しにも使うので、端末で入力できない)
   ```
   read -rsp "sysadmin のパスワード: " PW; echo
   printf '%s\n' "$PW" | ssh sysadmin@<ホスト> 'sudo -S -p "" agent-host-backup' > agent-host-<ホスト名>-<日付>.tar.zst
   ```
3. Docker のボリュームに残したいデータがあれば、手で書き出す(例: `docker run --rm -v <ボリューム>:/v -v $PWD:/b alpine tar czf /b/<ボリューム>.tgz -C /v .`)
4. 同じ env.yaml で作った ISO で、新しいホストを入れる(env.yaml は安全な場所に保管しておく)
5. 構成が終わったら取り込み、再起動する
   ```
   { printf '%s\n' "$PW"; cat agent-host-<ホスト名>-<日付>.tar.zst; } | ssh sysadmin@<ホスト> 'sudo -S -p "" agent-host-restore'
   ssh -t sysadmin@<ホスト> 'sudo systemctl reboot'
   unset PW
   ```
6. 受け入れテストの 4・5 を行う

**書き出したファイルにはログインの情報が入る。暗号化された場所に置き、取り込んだら消す。**

## 16. 定期的な再起動(運用)

unattended-upgrades はセキュリティ更新を自動で入れるが、自動では再起動しない(作業中のエージェントを止めないため)。カーネルなどの更新は再起動するまで反映されないので、月 1 回、エージェントが作業していない時間に sysadmin で再起動する。

```
ssh sysadmin@<ホスト>
[ -f /var/run/reboot-required ] && cat /var/run/reboot-required.pkgs   # 再起動待ちの更新
sudo systemctl reboot
```

再起動後は何もしなくても RDP で接続できる状態に戻る(受け入れテスト 4)。
