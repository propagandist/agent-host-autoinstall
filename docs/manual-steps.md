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
   - `agent_ssh_authorized_keys` は SFTP で agent に入る人の公開鍵。`dev_ports` は手元の PC から開発サーバーを見るときのポート
   - `ups` は UPS を使うときだけ(下の「UPS」)
   - `sysadmin.password_hash` は `mkpasswd -m sha-512`(または `openssl passwd -6`)で作る
2. 検査して ISO を作る
   ```
   just check-env      # env.yaml を検査する
   just fetch-iso      # Ubuntu の ISO を build/ に取得して照合する
   just iso            # build/agent-host.iso を作る
   ```
3. `build/agent-host.iso` を USB メモリに書き込む(Rufus なら「DD イメージ」モード)

できた ISO と USB メモリには、パスワードハッシュ、RDP のパスワード、Slack の Webhook の URL、UPS のパスワード(netclient のとき)が入る。使い終わったら消す。env.yaml は安全な場所に保管しておく(入れなおしや移行で使う)。

env.yaml は複数のファイルに分けて重ねられる(`just check-env common.yaml host.yaml`、`just iso build/x.iso common.yaml host.yaml`。後のファイルの値が勝つ)。ホストが 2 台以上になったら、env.yaml を別の非公開リポジトリで管理する([fleet.md](fleet.md))。

**注意:** この USB から起動すると、確認なしでディスク全体を消してインストールが始まる。対象以外の PC に挿したまま起動しない。インストールが終わって再起動したら、すぐに USB を抜く。

## 1. BIOS

- Restore on AC Power Loss(名称は機種による)を **Power On** にする
- UEFI で起動する。USB から起動できるようにする
- NVIDIA の GPU で Secure Boot が有効なら、そのままにしておく(インストールの中で入る NVIDIA のドライバーが、署名済みのモジュールで動くかは未確認。動かなければ just verify の「GPU」が ✗ になる)
- UPS を使うとき(env.yaml の `ups`)は、下の「UPS」も行う
- HDMI ダミープラグを挿す。デスクトップ共有は実際の画面をそのまま映すので、RDP の解像度はプラグの解像度になる(手元からは変えられない)。1920×1080 のプラグを選ぶ(4K だと文字がとても小さい)

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
3. 構成が終わると agent で自動ログインし、first-login がデスクトップ共有を有効にする

結果を確かめる。

```
just status <ホスト>   # 構成・RDP・セッション・ディスク・メモリ・失敗した unit
just logs <ホスト>     # 構成・最後の just update・first-login・セッションの見張りの記録
just verify <ホスト>   # 仕様どおりかを 100 項目あまりで確かめる(✗ の行を直す。何も変えない)
just verify-rdp <ホスト>   # env.yaml の rdp で RDP の認証が通るか(画面は開かない)
```

構成が失敗したときは、原因を直してから `just update <ホスト>`(構成を再実行する)。

## 3. agent のログインキーリング(自動で効かなかったときだけ)

80-agent-session.sh は空パスワードのキーリングを最初から置く。first-login の記録に `set-credentials` の失敗が出ていたら、これが効いていない。そのときは手でパスワードを空にする。

1. 物理画面(または一時的に別の手段)で agent のデスクトップを開く
2. 「パスワードと鍵」(seahorse。無ければ `sudo apt install seahorse`)を起動する
3. 「ログイン」キーリングを右クリック → パスワードの変更 → 新しいパスワードを空にする(平文で保存する警告には「続ける」)
4. ターミナルで `/opt/agent-host/first-login/first-login.sh` を実行する

## 4. デスクトップ共有(first-login が失敗したときだけ)

first-login が成功していれば不要。失敗していたら、agent のデスクトップで次を行う。

- 設定 → システム → リモートデスクトップ → 「デスクトップ共有」をオン、「リモート操作」をオン
- 認証情報(ユーザー名・パスワード)を env.yaml の `rdp` の値にする
- 「リモートログイン」は**オンにしない**(デスクトップ共有が 3390 番に移る)

## 5. RDP でつなぐ

```
just rdp <ホスト>      # build/<ホスト>.rdp を作る(Windows のリモート デスクトップ接続用)
```

ユーザーとパスワードは env.yaml の `rdp` の値。RDP のクライアントは何でもよい(Windows の mstsc、Linux の Remmina・FreeRDP、macOS の Windows App など)。`just rdp` の接続ファイルは mstsc 向けで、次の設定になっている(ほかのクライアントでも同じにするとよい)。

- Windows キーを常にホストへ送る(Super+Space などが使える)。クリップボードを共有する。色は 24 ビット(同じ 26.04 で mstsc の 32 ビットは遅いという報告があって 24 にした。ただし mstsc が既定で使うグラフィックス パイプラインでは、ホストが 32 ビットで送るので、ホストの負荷は変わらない)。回線の自動検出を有効にする(VPN のように遅延の大きい回線で、ホストが送る量を絞りすぎない)
- 初回の証明書の警告で、mstsc なら「このコンピューターへの接続について今後確認しない」を選ぶと、次から出ない
- **このホストは 1 人で使う。Claude Code や Codex などのサブスクリプションは個人の契約なので、ログインを複数の人で共有しない(規約に反するおそれがある)。複数の人で使うときは、人数分のホストを用意する(2 台目からは構成リポジトリでまとめて管理できる。docs/fleet.md)。デスクトップ共有は画面の前のセッションをそのまま映すので、入るのは本人だけ**

使い勝手:

- 日本語入力は Ctrl+Space、スクリーンショットは Ctrl+Shift+Alt+S(Windows のクライアントでは、PrintScreen は手元に取られることがある)。撮った画像はクリップボードに入るので、Claude Code に Ctrl+V で貼れる
- 上部のバーの Clipboard Indicator から、コピーの履歴を選んで貼れる
- 端末(Ctrl+Alt+T)は Xfce Terminal。右クリックで貼り付け、選択でコピー
- PDF は Atril で開く(Files でダブルクリック)
- Caps Lock はホストでは何もしない(RDP で手元と状態がずれるため)。大文字は Shift で打つ

以降の 6〜13 は、RDP で agent のデスクトップに入って行う。

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

認証情報は agent のホーム(`~/.aws`、`~/.config/gcloud`、`~/.azure`)に残り、エージェントは確認なしでコマンドを動かせる。長く使えるアクセスキー(`aws configure` で入れるものやサービスアカウントの鍵)は置かず、上の短い時間だけ有効なログインを使う。本番の権限は渡さず、開発用に権限を絞ったアカウント・プロジェクト・サブスクリプションを使う。

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

Orca のワークツリーやターミナルの出力をスマホで見て、コマンドを送れる(Orca の公式のアプリ)。**スマホから agent のターミナルを操作できるので、スマホを持つ人はエージェントを丸ごと操作できる。** 画面のロックをかけたスマホだけをペアリングし、無くしたら Orca の Settings → Mobile(日本語の表示では「設定 > モバイル」)からその端末を外す。

つなぎ方は 2 つある(Orca の画面で選ぶ)。

| つなぎ方 | 通り道 | このホストでの準備 |
|---|---|---|
| LAN | スマホがホストの 6768 番に直接つなぐ(通信は暗号化される)。アカウントは要らない | env.yaml の `dev_ports` に `6768` を足して `just update`(`lan_cidrs` からだけ開く)。LAN の外からは、VPN か、ホストとスマホの両方に Tailscale などを入れて、そのアドレスを選ぶ |
| Orca Relay(ベータ) | ホストとスマホが Orca のサーバーに外向きにつなぎ、サーバーが中継する。モバイル回線からも使える | ポートは開けない。ホストの Orca で Orca のアカウントにサインインする(アカウントによっては使えない)。通信は Orca のサービスを通る |

1. RDP で入り、Orca の Settings → Mobile(日本語の表示では「設定 > モバイル」)で、つなぎ方を選んで QR コードを作る(LAN ならアドレスに LAN の IP を選ぶ)
2. スマホの Orca Mobile の「Pair Desktop」で QR コードを読む

Orca は 6768 番を普段は 127.0.0.1 だけで待ち受け、ペアリングの操作で LAN にも開く。一度つないだ端末があれば、次の起動からは最初から LAN にも開く(v1.4.237 のソース。このホストでは未確認)。

## 14. ファイルのやり取り(SFTP)

env.yaml の `agent_ssh_authorized_keys` に公開鍵を書いた人は、SFTP で agent に入れる(シェルには入れない)。作業の置き場所は `/home/agent/work`。

Windows では [WinSCP](https://winscp.net/) を使う。

1. 「新しいサイト」で、転送プロトコル `SFTP`、ホスト名 `<ホスト>`、ポート 22、ユーザー名 `agent`
2. 「設定」→ SSH →「認証」→「秘密鍵」に鍵のファイルを選ぶ。OpenSSH の形式の鍵は PuTTY の形式(`.ppk`)への変換を勧められるので、変換して保存する
3. 「保存」して「ログイン」。初回はホスト鍵の指紋が出るので、ホストで `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` の結果と同じか確かめてから受け入れる

macOS や Linux からは、FileZilla か、端末の `sftp agent@<ホスト>` を使う。FileZilla は公式サイトの標準のインストーラーにほかのソフトの勧誘が付くので、付かない版を選ぶ。

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
| `rdp`・`desktop_color` | 反映する(セッション) | agent がログイン中ならその場で、そうでなければ次のログインで。Dock も、入っているエディターが変わると入れなおす |
| `editors`・`agents`・`clouds`・`vscode_extensions`・`zed_extensions` | 足すだけ | 外しても消さない(消すときは手で)。Zed の拡張機能は次に Zed を起動したときに入る |
| `lan_cidrs`・`dev_ports` | 足すだけ | ufw の許可は外しても消えない(下の注意) |
| `proxy`・`ca_certs`・`ntp_servers`・`git_user_*`・`gitea_url`・`notify`・`agent_ssh_authorized_keys`・`ups` | 反映する | agent の環境変数(プロキシ、Gitea の URL、クラウドの CLI の設定など)は、ログイン中なら次のログインで効く |

この表は `scripts/render-autoinstall.py` の `UPDATE_SCOPE` と合わせている(`just test` が項目の漏れを確かめる)。

- env.yaml のホスト名と、つないだホストの名前が違うと止まる(別のホストの設定を流さないため)
- 元の一式はホストの `/opt/agent-host.prev` に残る
- sysadmin の SSH の鍵とパスワードは、env.yaml の `sysadmin` に置き換わる(ホストで手で足した鍵や `passwd` で替えたパスワードは戻る)。鍵を替えるときは、今つないでいる鍵を外さない順で行う。反映のあと、入りなおせるかを確かめ、入れなければ止まって知らせる
- RDP の認証情報(env.yaml の `rdp`)を替えると、agent がログイン中ならその場で、そうでなければ次のログインで入れ替わる(古いものは使えなくなる)
- NVIDIA の GPU があるのにドライバーが入っていないと、構成の記録に注意が出る。`just ssh <ホスト>` → `sudo ubuntu-drivers install` → 再起動
- 反映したら `just verify <ホスト>` で、固定の版と設定が仕様どおりかを確かめる
- どの版の道具(と構成)を置いたかは `/opt/agent-host/BUILD-INFO` に残り、`just status <ホスト>` の「置いた版」に出る。構成が最後まで成功した版は `/var/lib/agent-host/BUILD-INFO.ok` に残り、「最後に適用に成功した版」に出る。just update が途中で失敗すると「構成: 前回の実行が最後まで終わっていない」と出るので、`just logs` の「最後の just update」(ホストの `/var/log/agent-host-update.log`)で止まったスクリプトを見て、直してから just update する。台帳のための情報(機種、シリアル、MAC、鍵の指紋)は `just facts <ホスト>`
- ufw の許可は足すだけなので、`lan_cidrs` や `dev_ports` から外したものは手で消す(`just ssh <ホスト>` → `sudo ufw status numbered` → `sudo ufw delete <番号>`)
- agent がログイン中だと、agent の環境変数の変更は次のログインで反映される
- 壁紙の色と Dock は、ログインのたびに動く自動起動(`first-login/desktop-env.sh`)が、env.yaml かエディターが変わったときだけ入れなおす。自分で変えた Dock は、それまで残る
- Chrome は Google のリポジトリに最新版しかないため固定せず、unattended-upgrades が自動で上げる

## 16. 環境を入れ替える(OS の入れなおし、機種の交換)

ホストの身元(SSH のホスト鍵、RDP の証明書)、ログインと設定(エージェント、GitHub・Gitea の CLI、クラウドの CLI、Orca、エディター)、`~/work` と Orca の worktree を移す。ツールの本体、mise の言語、Docker のイメージ、Chrome のプロファイルは移さない(作りなおせる)。`~/work` の中の `node_modules`・`__pycache__`・`.venv` と Orca のキャッシュも除く(取り込みの最後に、除いたものが出る。`npm install` や `uv sync` で作りなおす)。ほかの名前(`dist`、`target` など)は、ビルドの出力でも除かない。

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
ss -tln | grep 3389                                      # RDP の待ち受け
sudo journalctl -u agent-host-provision.service           # 初回の構成の記録
sudo tail -40 /var/log/agent-host-update.log               # 最後の just update の記録
sudo cat /home/agent/.local/state/agent-host/first-login.log
sudo /opt/agent-host/verify.sh                             # 仕様どおりかを確かめる(just verify と同じ)
```

### 設定やスクリプトを変えたとき

`scripts/stage.sh autoinstall/env.yaml <作業ディレクトリ>`(env.yaml は複数並べられる)で `<作業ディレクトリ>/agent-host/` を作り、ホストの `/opt/agent-host` と入れ替えてから(env.sh・agent_authorized_keys・sysadmin_authorized_keys は 600、所有者は root)、`sudo /opt/agent-host/provision.sh` を実行する。

### 移行の書き出しと取り込み

sudo のパスワードは標準入力の先頭の 1 行で渡す(標準入力は書き出しの受け渡しにも使うので、端末で入力できない)。

```
read -rsp "sysadmin のパスワード: " PW; echo
printf '%s\n' "$PW" | ssh sysadmin@<ホスト> 'sudo -S -p "" agent-host-backup' > agent-host-<ホスト名>-<日付>.tar.zst
{ printf '%s\n' "$PW"; cat agent-host-<ホスト名>-<日付>.tar.zst; } | ssh sysadmin@<ホスト> 'sudo -S -p "" agent-host-restore'
unset PW
```

### RDP の接続ファイル

`docs/agent-host.rdp.example` をコピーし、`full address` をホスト名に直す(改行は CRLF のまま)。
