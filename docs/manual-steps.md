# 手作業の手順

autoinstall とスクリプトで自動化できない作業と、自動化が効かなかったときの手順。SPEC.md §5.3 に対応する。
使う前に、README の「利用上の注意」と、無保証・自己責任であること(「ライセンス / 位置づけ」)を読む。
手元の PC での作業は just を前提に書く。just を使わないときのコマンドは付録 A にある。

## 準備(手元の PC)

- [just](https://just.systems/)
- Windows なら Git Bash(`C:/Program Files/Git/bin/bash.exe`)と Docker Desktop。Linux なら xorriso・python3-yaml・shellcheck があれば Docker は要らない
- 手順書の PDF を作るなら Docker(`just guide` が TeX Live のイメージを作って使う)
- このリポジトリの直下で `just` を実行すると、レシピの一覧が出る

試験用の VM などで SSH のポートや鍵を変えるときは、環境変数で渡す。

```
export AGENT_HOST_SSH_OPTS="-p 2222 -i build/test/id_ed25519"
```

## 0. インストール用 USB を作る

1. `autoinstall/env.example.yaml` を `autoinstall/env.yaml` にコピーし、実値を入れる
   - `keyboard_layout` は RDP で使う人のキーボードに合わせる(101/104 の英字配列なら `us`、106/109 なら `jp`)
   - `network` は固定 IP なら `mode: static` とアドレス・ゲートウェイ・DNS を書く。有線 LAN が 2 つ以上ある機種では `interface` に名前(`enp3s0` など)を書く
   - `ntp_servers` は、その LAN から ntp.ubuntu.com に届かないときだけ書く
   - `proxy` と `ca_certs` は、HTTP プロキシや独自の CA 証明書がある環境だけ書く
   - `editors` は入れたいエディター(vscode / neovim / zed)。VS Code は拡張機能も入り(足すなら `vscode_extensions`)、表示が日本語になる。Zed の拡張機能(足すなら `zed_extensions`)は Zed を初めて起動したときに入る
   - `agents` は追加のエージェント(opencode / copilot / antigravity)、`clouds` はクラウドの CLI(aws / gcp / azure。合わせて約 1.8GB)
   - `gitea_url` はGitea の URL(任意)、`notify` は通知の送り先(Slack の Webhook と IP Messenger)、`desktop_color` は壁紙の色(台ごとに変えると見分けやすい)
   - `users` は利用者(1 人以上)。1 人ごとに Linux のユーザー、ヘッドレスの GNOME のセッション、RDP のポートを持つ。`port` は人に固定し(例 3389、3390)、`rdp.initial_password` は初回だけの仮のパスワード(本人が最初の RDP で変える。下の 4)。`ssh_authorized_keys` は SFTP でその人のホームに入る公開鍵
   - `dev_ports` は手元の PC から開発サーバーを見るときのポート(利用者全員で共有する。`users` の `port` と重ねない)
   - `ups` は UPS を使うときだけ(下の「UPS」)
   - `sysadmin.password_hash` は `mkpasswd -m sha-512`(または `openssl passwd -6`)で作る
2. 検査して ISO を作る
   ```
   just check-env      # env.yaml を検査する
   just fetch-iso      # Ubuntu の ISO を build/ に取得して照合する
   just iso            # build/agent-host.iso を作る
   ```
3. `build/agent-host.iso` を USB メモリに書き込む(Rufus なら「DD イメージ」モード)

できた ISO と USB メモリには、パスワードハッシュ、RDP の仮のパスワード、Slack の Webhook の URL、UPS のパスワード(netclient のとき)が入る。使い終わったら消す。env.yaml は安全な場所に保管しておく(入れなおしや移行で使う)。

env.yaml は複数のファイルに分けて重ねられる(`just check-env common.yaml host.yaml`、`just iso build/x.iso common.yaml host.yaml`。後のファイルの値が勝つ)。ホストが 2 台以上になったら、env.yaml を別の非公開リポジトリで管理する([fleet.md](fleet.md))。

**注意:** この USB から起動すると、確認なしでディスク全体を消してインストールが始まる。対象以外の PC に挿したまま起動しない。インストールが終わって再起動したら、すぐに USB を抜く。

## 1. BIOS

- Restore on AC Power Loss(名称は機種による)を **Power On** にする
- UEFI で起動する。USB から起動できるようにする
- NVIDIA の GPU で Secure Boot が有効なら、そのままにしておく(インストールの中で入る NVIDIA のドライバーが、署名済みのモジュールで動くかは未確認。動かなければ just verify の「GPU」が ✗ になる)
- UPS を使うとき(env.yaml の `ups`)は、下の「UPS」も行う
- モニターと HDMI ダミープラグは要らない。利用者ごとのセッションはヘッドレス(物理の画面を使わない)で、RDP の解像度はつなぐ側の画面に合わせる(未確認。VirtualBox ではつなぐ側の大きさになった)

### UPS(env.yaml の ups を書いた場合)

85-ups.sh が NUT(Network UPS Tools)で UPS を見る。バッテリーが少なくなるか、NUT サーバーが終了を指示したら、正しく終了する。

| ups.mode | つなぎ方 | 電源が戻ったあと |
|---|---|---|
| `usb` | UPS をこの PC に USB(機種によりシリアル)でつなぐ。`driver` と `port` は NUT の対応表(networkupstools.org)で確かめる。多くは `usbhid-ups` と `auto` | 終了の最後に UPS の出力を止める。電源が戻ると UPS が出力を戻し、BIOS の「Restore on AC Power Loss: Power On」で PC が起動する |
| `netclient` | NAS など、UPS をつないだ別の機器の NUT サーバーを見る。`server`・`name`・`username`・`password` は、その NUT サーバーの監視用のユーザー(secondary) | 出力を止めるのは NUT サーバーの側。そちらの設定で、電源が戻ったときに出力が戻るようにする |

- UPS の側で「電源が戻ったら出力を戻す」(自動再起動)を有効にしておく(多くの機種で既定)
- 通知: バッテリー運転になった、バッテリーが少ない、まもなく終了する、状態を読めない、バッテリーの交換時期、は Slack と IP Messenger に、電源が戻った、状態をまた読めるようになった、は Slack に届く
- 確かめる: `just verify <ホスト>` の「UPS」に、UPS の状態(`OL` は電源から給電)が出る。ホストで `upsc <name>@localhost` でも見られる
- 停電を試すときは、UPS の電源プラグを抜いて、バッテリー運転の通知が届くことを確かめ、すぐ挿しなおす(バッテリーが少なくなるまで待つと終了する)

## 2. インストール

1. USB から起動する。確認画面は出ずにインストールが進む
2. 再起動後、初回起動時の構成(agent-host-provision.service)がネットワークから Node.js・Orca・Claude Code などを取得する。終わるまで GDM は起動しない
3. 構成が終わると GDM が起動し、利用者ごとのヘッドレスのセッション(`gnome-headless-session@<名前>`)が立つ。RDP は起動から 1 分ほどで、それぞれの `port` で待ち受ける

結果を確かめる。

```
just status <ホスト>   # 構成・待ち受けているポート・利用者ごとのセッション・ディスク・メモリ・失敗した unit
just logs <ホスト>     # 構成・最後の just update・利用者ごとの first-login とセッションの記録
just verify <ホスト>   # 仕様どおりかを確かめる(全体と利用者ごと。✗ の行を直す。何も変えない)
just verify-rdp <ホスト>   # 利用者ごとに、仮のパスワードで RDP の認証が通るか(画面は開かない)
```

構成が失敗したときは、原因を直してから `just update <ホスト>`(構成を再実行する)。

## 3. 利用者を足す・外す

env.yaml の `users` を直して `just update <ホスト>`。

- 足す: ユーザーを作り、構成をその人の分も行い、セッションを立てる。`port` はほかの人と重ねない
- 外す: ユーザーとホーム(ログインと作業)は残したまま、ログインを止める。期限切れにし(鍵の SSH も拒まれる)、SSH の `AllowUsers` から外し、セッション・linger・rootless Docker・ufw のその人のポートを止める。`users` に戻せば、同じホームで使える
- 並べ替えても、残った人の `port`(と接続ファイル)は変わらない

## 4. RDP のパスワードを変える(本人が最初の RDP で)

env.yaml の `rdp.initial_password` は初回だけの仮の値で、ISO と構成リポジトリの管理者にも見える。最初に RDP で入ったら、本人が自分の端末で変える。

```
grdctl --headless rdp set-credentials <rdp.username> <新しいパスワード>
systemctl --user restart gnome-remote-desktop-headless.service
```

- ユーザー名は env.yaml の `rdp.username` と同じにする
- 2 行目で RDP のデーモンを再起動するまでは、古いパスワードのままになる(デーモンは起動したときの認証情報を使い続ける。VirtualBox で確認)。再起動すると今の接続が切れるので、新しいパスワードで入りなおす。セッションと端末の中の処理は続く
- 「Init TPM credentials failed because No TPM device found, using GKeyFile as fallback」は、TPM のない機械では毎回出る(ファイルに保存したという意味で、失敗ではない)
- 端末の履歴にパスワードが残るので、気になるなら打ったあとに `history -d` で消す
- `just update` は、RDP の認証情報がまだないときだけ仮の値を入れるので、変えたパスワードは上書きされない。移行(下の「移行」)でも、ホームごと移る
- 変えたあとの `just verify-rdp` は、その人を「未検証」と出す(失敗ではない)。今のパスワードで確かめるなら `just verify-rdp <ホスト> --ask <名前> <env.yaml>`
- 忘れたとき: 管理者が `sudo rm <その人のホーム>/.local/share/gnome-remote-desktop/credentials.ini` で消してから `just update <ホスト>` を実行すると、仮の値に戻る(デーモンも再起動する)(TPM のある機械では認証情報が TPM に入り、このファイルがないことがある。未確認)

## 5. RDP でつなぐ

```
just rdp <ホスト> <ポート>   # build/<ホスト>-<ポート>.rdp を作る(Windows のリモート デスクトップ接続用。ポートはその人の port)
```

接続先は `<ホスト>:<その人の port>`。ユーザーは env.yaml の `rdp.username`、パスワードは最初は `rdp.initial_password`(上の 4 で変える)。RDP のクライアントは何でもよい(Windows の mstsc、Linux の Remmina・FreeRDP、macOS の Windows App など)。`just rdp` の接続ファイルは mstsc 向けで、次の設定になっている(ほかのクライアントでも同じにするとよい)。

- Windows キーを常にホストへ送る(Super+Space などが使える)。クリップボードを共有する。色は 24 ビット(同じ 26.04 で mstsc の 32 ビットは遅いという報告があって 24 にした。ただし mstsc が既定で使うグラフィックス パイプラインでは、ホストが 32 ビットで送るので、ホストの負荷は変わらない)。回線の自動検出を有効にする(VPN のように遅延の大きい回線で、ホストが送る量を絞りすぎない)
- 初回の証明書の警告で、mstsc なら「このコンピューターへの接続について今後確認しない」を選ぶと、次から出ない
- **Claude Code や Codex などのサブスクリプションは個人の契約なので、ログインを複数の人で共有しない(規約に反するおそれがある)。1 台を複数の人で使うときは、人ごとに `users` を分け、それぞれが自分のホームで自分のアカウントにログインする。ほかの人の RDP の接続先(port)には入らない。sysadmin(root)は全員のホームを読める**
- 1 台で動かせる人数の目安: 何もしていないセッションで 1 人あたり 0.5〜1GB(エージェントとビルドの分は別。VirtualBox で測った)

使い勝手:

- 日本語入力は Ctrl+Space(半角/全角キーは RDP では押しっぱなしで届き、使えない。#21)、スクリーンショットは Ctrl+Shift+Alt+S(Windows のクライアントでは、PrintScreen は手元に取られることがある)。撮った画像はクリップボードに入るので、Claude Code に Ctrl+V で貼れる
- 上部のバーの Clipboard Indicator から、コピーの履歴を選んで貼れる
- 端末(Ctrl+Alt+T)は Xfce Terminal。右クリックで貼り付け、選択でコピー
- PDF は Atril で開く(Files でダブルクリック)
- Caps Lock はホストでは何もしない(RDP で手元と状態がずれるため)。大文字は Shift で打つ

以降の 6〜13 は、利用者がそれぞれ RDP で自分のデスクトップに入って行う。

## 6. Claude Code のログイン

端末で `claude` を起動してログインする。ブラウザ(Chrome)が開く。

## 7. Codex のログイン

1. 事前に ChatGPT の設定 → セキュリティで「Codex、Excel、PowerPoint、Word のデバイスコードによるサインイン」を有効にする(Workspace なら管理者の権限設定)。有効でないと、`codex login --device-auth` は「ChatGPT のセキュリティ設定で…デバイスコードによるサインインを有効にしてから…もう一度実行してください」と出して止まる
2. 端末で `codex login --device-auth` を実行し、表示された URL とコードを手元の PC のブラウザで入力する(VirtualBox + RDP で確認済み)

## 8. Orca の初回起動

1. Orca は自動起動している。初回の案内に従う。Yolo モード(確認なしでコマンドを実行)は最初からオンなので、使い方の方針に合わせて決める
2. `~/.claude` / `~/.codex` の設定を取り込む
3. Settings → Privacy の「Share anonymous usage data」をオフにする(環境変数 ORCA_TELEMETRY_DISABLED=1 でも止めているが、設定にも残す)
4. Settings → Notifications の「Update available」をオフにする。.deb 版は自分では更新しない。更新の確認の通信そのものは止められない(notes.md)

## 9. 追加のエージェントのログイン(env.yaml の agents で選んだものだけ)

- OpenCode: `opencode auth login` で、使うモデルのプロバイダーの API キーや OAuth を設定する
- GitHub Copilot CLI: `copilot` を起動し `/login` → デバイスコード(github.com/login/device)。Copilot の契約が要る
- Antigravity CLI: `agy` を起動し、表示された URL を手元のブラウザで開き、得たコードを端末に貼り付ける。テレメトリはアカウント側の `/config` で切り替える

## 10. GitHub・Gitea の認証(push する場合)

どのアカウントで認証するかを先に決める(エージェント専用のアカウントか、権限を絞ったトークンが無難)。

GitHub:

```
gh auth login        # GitHub.com → HTTPS → ブラウザ(デバイスコード)で認証
gh auth setup-git    # git の push に gh の認証を使う
gh auth status
```

Gitea(tea):Gitea の画面の「設定 → アプリケーション」でアクセストークンを作る(repository と issue の書き込み、user の読み取り。tea でリポジトリを作るなら user の書き込みも)。
env.yaml に `gitea_url` を書いていれば、接続先は自動で入る(書いていなければ `--url https://<Gitea のホスト>` を足す)。

```
tea login add --name gitea --token <トークン> --git-credentials   # git の HTTPS の push にも tea の認証を使う
tea login list
tea whoami
```

## 11. Docker Hub とクラウドの CLI のログイン

### Docker Hub

1 つのグローバル IP をまとめて外に出る環境では、ログインなしの Docker Hub からの取得は 6 時間に 100 回までで、エージェントが使うとすぐ当たる。`docker login` する(アクセストークンを使う)。

### クラウドの CLI のログイン(env.yaml の clouds で選んだものだけ)

どれもブラウザ(Chrome)が開くので、そこでログインする。

```
aws configure sso                       # 初回だけ: SSO の開始 URL、リージョン、アカウント、ロール
aws sso login                           # 切れたらこれで入りなおす
gcloud auth login                       # gcloud コマンド用
gcloud auth application-default login   # SDK・Terraform などのプログラム用(使う場合)
gcloud config set project <プロジェクト ID>
az login                                # サブスクリプションを選ぶ
```

認証情報はその利用者のホーム(`~/.aws`、`~/.config/gcloud`、`~/.azure`)に残り、エージェントは確認なしでコマンドを動かせる。長く使えるアクセスキー(`aws configure` で入れるものやサービスアカウントの鍵)は置かず、上の短い時間だけ有効なログインを使う。本番の権限は渡さず、開発用に権限を絞ったアカウント・プロジェクト・サブスクリプションを使う。

## 12. 通知の確認(env.yaml の notify を書いた場合)

```
agent-notify approval テスト "通知のテストです"
```

Slack と IP Messenger の両方に届くことを確かめる(done は Slack だけ)。IP Messenger の受け取り側の PC は、UDP 2425 番の受信を許可しておく。

## 13. スマホからの操作(Claude Code の Remote Control、Orca Mobile)

### Claude Code の Remote Control

Claude Code に Pro / Max / Team / Enterprise のアカウントでログインしているときだけ使える。通信は Anthropic のサービスを通る。

1. 作業するディレクトリで `claude remote-control`(または動いているセッションで `/remote-control`)。初回は確認に `y` で答える
2. 表示された URL か QR コードを、スマホの Claude アプリか claude.ai/code で開く
3. スマホへのプッシュ通知: Claude アプリに同じアカウントでログインし、端末で `/config` から「Push when actions required」などをオンにする

### Orca Mobile

Orca のワークツリーやターミナルの出力をスマホで見て、コマンドを送れる(Orca の公式のアプリ)。**スマホから利用者のターミナルを操作できるので、スマホを持つ人はエージェントを丸ごと操作できる。** 画面のロックをかけたスマホだけをペアリングし、無くしたら Orca の Settings → Mobile(日本語の表示では「設定 > モバイル」)からその端末を外す。

つなぎ方は 2 つある(Orca の画面で選ぶ)。

| つなぎ方 | 通り道 | このホストでの準備 |
|---|---|---|
| LAN | スマホがホストの 6768 番に直接つなぐ(通信は暗号化される)。アカウントは要らない | env.yaml の `dev_ports` に `6768` を足して `just update`(`lan_cidrs` からだけ開く)。LAN の外からは、VPN か、ホストとスマホの両方に Tailscale などを入れて、そのアドレスを選ぶ |
| Orca Relay(ベータ) | ホストとスマホが Orca のサーバーに外向きにつなぎ、サーバーが中継する。モバイル回線からも使える | ポートは開けない。ホストの Orca で Orca のアカウントにサインインする(アカウントによっては使えない)。通信は Orca のサービスを通る |

1. RDP で入り、Orca の Settings → Mobile(日本語の表示では「設定 > モバイル」)で、つなぎ方を選んで QR コードを作る(LAN ならアドレスに LAN の IP を選ぶ)
2. スマホの Orca Mobile の「Pair Desktop」で QR コードを読む

Orca は 6768 番を普段は 127.0.0.1 だけで待ち受け、ペアリングの操作で LAN にも開く。一度つないだ端末があれば、次の起動からは最初から LAN にも開く(v1.4.237 のソース。このホストでは未確認)。1 台を複数の人で使うと、2 人目以降の Orca は 6768 が使われているので別のポートに移る見込み(Orca の CLI の serve の説明から。未確認)。LAN でつなぐなら、その人の Orca の画面に出るポートも `dev_ports` に足す。

## 14. ファイルのやり取り(SFTP)

env.yaml の `users` の `ssh_authorized_keys` に公開鍵を書いた人は、SFTP でその利用者に入れる(シェルには入れない)。作業の置き場所は `/home/<名前>/work`。

Windows では [WinSCP](https://winscp.net/) を使う。

1. 「新しいサイト」で、転送プロトコル `SFTP`、ホスト名 `<ホスト>`、ポート 22、ユーザー名 `<利用者の name>`
2. 「設定」→ SSH →「認証」→「秘密鍵」に鍵のファイルを選ぶ。OpenSSH の形式の鍵は PuTTY の形式(`.ppk`)への変換を勧められるので、変換して保存する
3. 「保存」して「ログイン」。初回はホスト鍵の指紋が出るので、ホストで `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` の結果と同じか確かめてから受け入れる

macOS や Linux からは、FileZilla か、端末の `sftp <名前>@<ホスト>` を使う。FileZilla は公式サイトの標準のインストーラーにほかのソフトの勧誘が付くので、付かない版を選ぶ。

小さなファイルは、RDP のクリップボードでのコピー&貼り付けでも渡せる(未確認)。

## 15. 設定やスクリプトを変えたとき(運用)

env.yaml を直したとき、スクリプトや固定するバージョンを直したときは、OS を入れなおさずに反映できる。ただし、インストールのときにしか効かない項目もある(下の表)。

```
just update <ホスト>   # env.yaml から設定を作りなおし、スクリプトを入れ替えて、構成を再実行する
```

| env.yaml の項目 | just update で | 注記 |
|---|---|---|
| `hostname`・`network`・`keyboard_layout` | **反映しない(入れなおす)** | インストールのときだけ効く。`hostname` を変えた env.yaml では、ホスト名の照合で止まる。ネットワークを変えると SSH が切れて戻せない恐れがあるので、反映しない |
| `sysadmin` | 反映する | 鍵とパスワードを env.yaml の内容に置き換える(下の注意) |
| `users` | 反映する | 足した人は作ってセッションを立て、外した人はログインとセッションを止める(上の 3)。`rdp.initial_password` は、その人に RDP の認証情報がまだないときだけ入る(変えたパスワードは上書きしない) |
| `desktop_color` | 反映する(セッション) | セッションが動いていればその場で、そうでなければ次にセッションが立つときに。Dock も、入っているエディターが変わると入れなおす |
| `editors`・`agents`・`clouds`・`vscode_extensions`・`zed_extensions` | 足すだけ | 外しても消さない(消すときは手で)。Zed の拡張機能は次に Zed を起動したときに入る |
| `lan_cidrs`・`dev_ports` | 足すだけ | ufw の許可は外しても消えない(下の注意) |
| `proxy`・`ca_certs`・`ntp_servers`・`gitea_url`・`notify`・`ups` | 反映する | 利用者の環境変数(プロキシ、Gitea の URL、クラウドの CLI の設定など)は、セッションが動いていれば次にセッションが立つときに効く |

この表は `scripts/render-autoinstall.py` の `UPDATE_SCOPE` と合わせている(`just test` が項目の漏れを確かめる)。

- env.yaml のホスト名と、つないだホストの名前が違うと止まる(別のホストの設定を流さないため)
- 元の一式はホストの `/opt/agent-host.prev` に残る
- sysadmin の SSH の鍵とパスワードは、env.yaml の `sysadmin` に置き換わる(ホストで手で足した鍵や `passwd` で替えたパスワードは戻る)。鍵を替えるときは、今つないでいる鍵を外さない順で行う。反映のあと、入りなおせるかを確かめ、入れなければ止まって知らせる
- RDP のパスワードは本人が変える(上の 4)。env.yaml の `rdp.initial_password` を替えても、すでに認証情報がある人には効かない
- NVIDIA の GPU があるのにドライバーが入っていないと、構成の記録に注意が出る。`just ssh <ホスト>` → `sudo ubuntu-drivers install` → 再起動
- 反映したら `just verify <ホスト>` で、固定の版と設定が仕様どおりかを確かめる
- どの版の道具(と構成)を置いたかは `/opt/agent-host/BUILD-INFO` に残り、`just status <ホスト>` の「置いた版」に出る。構成が最後まで成功した版は `/var/lib/agent-host/BUILD-INFO.ok` に残り、「最後に適用に成功した版」に出る。just update が途中で失敗すると「構成: 前回の実行が最後まで終わっていない」と出るので、`just logs` の「最後の just update」(ホストの `/var/log/agent-host-update.log`)で止まったスクリプトを見て、直してから just update する。台帳のための情報(機種、シリアル、MAC、鍵の指紋)は `just facts <ホスト>`
- ufw の許可は足すだけなので、`lan_cidrs` や `dev_ports` から外したものは手で消す(利用者の RDP のポートは、外した人の分を just update が消す)(`just ssh <ホスト>` → `sudo ufw status numbered` → `sudo ufw delete <番号>`)
- セッションが動いている利用者には、環境変数の変更は次にセッションが立つとき(再起動など)に反映される
- 壁紙の色と Dock は、セッションが立つたびに動く自動起動(`first-login/desktop-env.sh`)が、env.yaml かエディターが変わったときだけ入れなおす。自分で変えた Dock は、それまで残る
- Chrome は Google のリポジトリに最新版しかないため固定せず、unattended-upgrades が自動で上げる

## 16. 環境を入れ替える(OS の入れなおし、機種の交換)

利用者(env.yaml の `users`)全員の分を移す。取り込むのは、新しいホストの `users` にいる名前の分だけ(同じ名前で合わせる)。ホストの身元(SSH のホスト鍵、利用者ごとの RDP の証明書と、本人が変えた RDP のパスワード)、ログインと設定(エージェント、GitHub・Gitea の CLI、クラウドの CLI、Orca、エディター)、`~/work` と Orca の worktree を移す。ツールの本体、mise の言語、Docker のイメージ、Chrome のプロファイルは移さない(作りなおせる)。`~/work` の中の `node_modules`・`__pycache__`・`.venv` と Orca のキャッシュも除く(取り込みの最後に、除いたものが出る。`npm install` や `uv sync` で作りなおす)。ほかの名前(`dist`、`target` など)は、ビルドの出力でも除かない。ホームの分は、書き出しも取り込みもその利用者の権限で行う。利用者に読めないもの(rootless Docker のコンテナが作ったデータなど)は書き出さず、書き出しと取り込みの最後に一覧が出る(移すなら、元のホストで読めるようにしてから書き出しなおす)。取り込み先のホームに、ホームの外を指すリンクがあると、その利用者の取り込みは失敗する(ほかの人の分とホストの身元は取り込み、最後に失敗として終わる)。

1. Orca とエージェントの作業を止める(書き出しの途中で書き換わらないように)
2. 書き出す。sudo のパスワードを 1 回聞かれる。ホストには保存されない
   ```
   just backup <ホスト>   # build/backups/<ホスト>-<日時>.tar.zst に書き出す
   ```
3. Docker のボリュームに残したいデータがあれば、手で書き出す(例: `docker run --rm -v <ボリューム>:/v -v $PWD:/b alpine tar czf /b/<ボリューム>.tgz -C /v .`)
4. 同じ env.yaml で `just iso` を作り、新しいホストを入れる
5. 取り込むまでは、一時の known_hosts でつなぐ(下の「ホスト鍵」)
   - 新しいホストの画面(RDP の端末でもよい)で、新しいホスト鍵の指紋を見る
     ```
     ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
     ```
   - 手元の PC で、一時の known_hosts を使うようにする(ほかに `AGENT_HOST_SSH_OPTS` を使っていれば後ろに足す)
     ```
     export AGENT_HOST_SSH_OPTS="-o UserKnownHostsFile=$PWD/build/known_hosts.migrate"
     just status <ホスト>   # 最初に出る指紋が、上で見たものと同じなら yes
     ```
6. 構成が終わったら取り込み、再起動する
   ```
   just restore <ホスト> build/backups/<ホスト>-<日時>.tar.zst
   unset AGENT_HOST_SSH_OPTS; rm -f build/known_hosts.migrate   # 取り込むと元のホスト鍵に戻るので、一時のものは要らない
   just ssh <ホスト>      # sudo systemctl reboot(元の known_hosts でつながる)
   ```
7. `just verify <ホスト>` と、受け入れテストの 4・5 を行う

**ホスト鍵:** 入れなおすと SSH のホスト鍵が新しくなり、取り込むと書き出したときの鍵に戻る(sshd も再起動する)。そのため、取り込むまでは手元の known_hosts の鍵と合わず、`just status` も `just restore` も「REMOTE HOST IDENTIFICATION HAS CHANGED」で止まる。known_hosts の古い鍵は消さない(消すと、取り込んだあとにもう一度食い違う)。`StrictHostKeyChecking=no` などで確かめずにつなぐと、書き出し(ログインの情報が入る)と sudo のパスワードを、確かめていない相手に送ることになるので使わない。

**書き出したファイルにはログインの情報が入る。暗号化された場所に移し、取り込んだら消す。**

## 17. 定期的な再起動(運用)

unattended-upgrades はセキュリティ更新を自動で入れるが、自動では再起動しない(作業中のエージェントを止めないため)。カーネルなどの更新は再起動するまで反映されないので、月 1 回、エージェントが作業していない時間に再起動する。

```
just ssh <ホスト>
[ -f /var/run/reboot-required ] && cat /var/run/reboot-required.pkgs   # 再起動待ちの更新
sudo systemctl reboot
```

再起動後は何もしなくても RDP で接続できる状態に戻る(受け入れテスト 4)。

## 付録 A. just を使わない場合

just のレシピがしていることを、手で行うときのコマンド。リポジトリの直下で実行する。

### ISO を作る(Linux。xorriso と python3-yaml が要る)

```
python3 scripts/render-autoinstall.py autoinstall/autoinstall.yaml autoinstall/env.yaml /tmp/check   # 検査
curl -fLO https://releases.ubuntu.com/26.04/ubuntu-26.04.1-desktop-amd64.iso
curl -fsSL https://releases.ubuntu.com/26.04/SHA256SUMS | grep 'desktop-amd64' | sha256sum -c --ignore-missing
scripts/build-usb.sh ubuntu-26.04.1-desktop-amd64.iso build/agent-host.iso autoinstall/env.yaml
```

`--build-info <ファイル>` を渡さないと、ホストに置いた版の記録(`/opt/agent-host/BUILD-INFO`)が置かれず、`just status` は「記録なし」、`just verify` は「置いた版の記録がある」が ✗ になる(just は自動で作って渡す)。

Windows では Docker の Ubuntu の中で同じことをする(Git Bash から)。

```
MSYS_NO_PATHCONV=1 docker run --rm -v "$(pwd -W):/repo" -w /repo ubuntu:26.04 bash -c \
  'apt-get update -qq && apt-get install -y -qq xorriso python3-yaml &&
   bash scripts/build-usb.sh build/ubuntu-26.04.1-desktop-amd64.iso build/agent-host.iso autoinstall/env.yaml'
```

### 状態と記録を見る

```
ssh sysadmin@<ホスト>
test -f /var/lib/agent-host/provisioned && echo 構成済み
ss -tln                                                  # RDP の待ち受け(利用者ごとの port)
sudo journalctl -u agent-host-provision.service           # 初回の構成の記録
sudo tail -40 /var/log/agent-host-update.log               # 最後の just update の記録
sudo cat /home/<名前>/.local/state/agent-host/first-login.log
sudo /opt/agent-host/verify.sh                             # 仕様どおりかを確かめる(just verify と同じ)
```

### 設定やスクリプトを変えたとき

`scripts/stage.sh autoinstall/env.yaml <作業ディレクトリ>`(env.yaml は複数並べられる)で `<作業ディレクトリ>/agent-host/` を作り、ホストの `/opt/agent-host` と入れ替えてから(env.sh・sysadmin_authorized_keys・users/ の中は 600、users/ は 700、所有者は root)、`sudo /opt/agent-host/provision.sh` を実行する。

### 移行の書き出しと取り込み

sudo のパスワードは標準入力の先頭の 1 行で渡す(標準入力は書き出しの受け渡しにも使うので、端末で入力できない)。

```
read -rsp "sysadmin のパスワード: " PW; echo
printf '%s\n' "$PW" | ssh sysadmin@<ホスト> 'sudo -S -p "" agent-host-backup' > agent-host-<ホスト名>-<日付>.tar.zst
{ printf '%s\n' "$PW"; cat agent-host-<ホスト名>-<日付>.tar.zst; } | ssh sysadmin@<ホスト> 'sudo -S -p "" agent-host-restore'
unset PW
```

### RDP の接続ファイル

`docs/agent-host.rdp.example` をコピーし、`full address` を `<ホスト>:<その人の port>` に直す(改行は CRLF のまま)。
