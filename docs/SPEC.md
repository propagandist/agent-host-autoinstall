# agent-host-autoinstall — SPEC

手元に置く物理 PC を、AIコーディングエージェント(Claude Code / Codex)を Orca(ADE)で並列稼働させる「常時稼働エージェントホスト」として自動構成するための仕様。

## 1. 目的

背景: コーディングエージェントは 1 つの作業に長い時間がかかり、確認なしで動かすことも多い。手元の PC で並べて動かすと、閉じられず、私的なファイルや個人のログイン情報のある環境を触らせることになる。クラウドのエージェントは各社ごとに別々で、標準では GitHub が前提で、LAN の資源に届かない(組織が自前の実行環境を用意すれば別)。そこで、LAN の中に専用の PC を置き、Orca でエージェントを並べて見比べ、どこからでも RDP でその画面に入れるようにする。Orca の Remote Orca Server と同じく「作業する PC」と「操作する PC」を分ける形で、作業する側を OS ごと人手なしで保つ(比較は notes.md「専用の PC を置く理由」)。

- USBメモリ1本から、決まった構成の Ubuntu Desktop を無人に近い形でインストールできること
- 再起動やセッションの異常終了のあとも、人手を介さず Orca が起動し、RDP で接続できる状態に戻ること(電源が戻ったときに起動するのは BIOS の設定で行う)
- 構成をコードとして管理し、同じ環境を何台でも再現できること

## 2. 対象環境

| 項目 | 内容 |
|---|---|
| OS | Ubuntu Desktop 26.04 LTS(GNOME のセッションは Wayland のみ。xrdp の Xorg のセッションでは GNOME が動かないため不採用) |
| 言語・地域 | 日本語の環境向け。ロケール ja_JP.UTF-8、タイムゾーン Asia/Tokyo、日本語入力 Mozc(autoinstall.yaml、76-desktop.sh、first-login で固定) |
| ハードウェア | x86_64 の物理PC。メモリ 32GB 以上(利用者 1 人あたり、セッションに 0.5〜1GB とエージェント・ビルドの分)、NVMe SSD 推奨、有線 LAN。GPU は Intel の第 6 世代以降の内蔵 GPU か AMD を推奨(RDP の画面を GPU で符号化する) |
| 画面 | 物理モニターなし運用。利用者ごとのセッションはヘッドレス(ダミープラグは要らない) |
| ネットワーク | LAN。固定IP(または DHCP 予約) |
| 遠隔操作 | GNOME のリモートデスクトップ(gnome-remote-desktop)の headless の RDP。利用者ごとにポートを分ける |
| 管理操作 | SSH(鍵認証のみ) |

## 3. 全体の流れ

```
電源投入
  → GDM 起動(自動ログインはしない)
  → 利用者ごとに gnome-headless-session@<名前> がヘッドレスの GNOME のセッションを立てる
    (ログインキーリングは空パスワードなので自動で開く)
  → 利用者ごとの RDP(gnome-remote-desktop の headless、env.yaml の users[].port)が待ち受け開始
  → Orca が autostart で起動
LAN の RDP クライアント → :<その人の port> → その人のデスクトップを操作
管理者 → SSH → sysadmin ユーザー
```

## 4. ユーザー

| ユーザー | 用途 | sudo | ログイン |
|---|---|---|---|
| `sysadmin` | OS 管理・更新 | あり | SSH 鍵認証のみ(パスワード認証は無効) |
| 利用者(env.yaml の `users`。1 人以上) | Orca / Claude Code / Codex の実行 | なし | systemd が立てるヘッドレスのセッション(Linux のパスワードはロック)。RDP はその人の port と、その人の RDP の認証情報。SSH は SFTP 専用(env.yaml に鍵を書いた人だけ。シェルには入れない) |

利用者は 1 人 1 つの Linux のユーザーで、ホームは 700。本人の各サービスのログイン(サブスクリプションを含む)を本人のホームに置き、ほかの利用者とは共有しない(サブスクリプションの共有を避ける)。利用者どうしを隔てるのは Linux のユーザーと、利用者ごとの RDP の認証情報(env.yaml の値は初回だけの仮のもので、本人が変える)。Claude Code・Codex の認証情報はホームの平文のファイルなので、sysadmin(root)は全員の分を読める。env.yaml から外した利用者は、ユーザーとホームを残したままログインを止める(期限切れ、`AllowUsers` から外す、セッション・linger・ufw のポートを止める)。

## 5. 機能要件

### 5.1 OS インストール(autoinstall)
- ロケール `ja_JP.UTF-8`、タイムゾーン `Asia/Tokyo`(日本語入力の ibus-mozc・言語パック・日本語フォントは、インストーラーが入れないことがあったので 76-desktop.sh で入れる)
- キーボード配列は env.yaml の `keyboard_layout`(`us` / `jp`)で台ごとに決める。RDP ではキーの位置がそのまま送られ、ホスト側の配列で文字になるので、RDP で使う人のキーボードに合わせる
- ストレージは LVM、ディスク全体を使用(`sizing-policy: all`。既定の scaled はボリュームグループの半分ほどを空けて残す。暗号化はしない。§8 参照)
- ネットワークは env.yaml の `network` で、DHCP か固定 IP(アドレス、ゲートウェイ、DNS、検索ドメイン)を台ごとに決める。インストール中もこの設定で通信し、インストール後は NetworkManager が管理する
- `sysadmin` ユーザーと SSH 公開鍵を登録
- openssh-server を導入
- 要る機種では追加のドライバー(NVIDIA など)をインストールの中で入れる(`drivers: install: true`)
- env.yaml の `proxy` をインストール中の apt にも使う

### 5.2 インストール後の構成(late-commands / スクリプト)
late-commands は同梱スクリプトを `/opt/agent-host` に置き、初回起動時の構成サービス(`agent-host-provision.service`)を有効にするだけにする。構成そのものは、初回起動時にこのサービスが `post-install/` を番号順に実行する(GDM の起動前。最初に起動画面(plymouth)を閉じる)。インストール中の chroot では ufw などが動かないため。利用者ごとの設定は、利用者の権限と、linger で常にある利用者のユーザーのバスで行う(gsettings・grdctl はセッションがなくても書ける)。初回だけの GNOME の設定は、セッションを立てる前に first-login.sh を利用者のバスで実行する。env.yaml で変わるもの(壁紙の色と Dock)は、セッションが立つたびの自動起動(first-login/desktop-env.sh)が変わったときだけ入れ、`just update` のときにセッションが動いていればその場でも入れる。root は利用者のホームの中を root で書かない(利用者の権限で書く)。

- 利用者のユーザー作成(sudo なし。全員を `agent-host-users` グループに入れる)。外した利用者のログインを止める
- `sysadmin` の SSH の鍵とパスワードは、`just update` のたびに env.yaml の `sysadmin` に合わせる(手で足した鍵は消える。反映のあと入りなおせるかを確かめる)
- 利用者ごとのヘッドレスのセッション:`gnome-headless-session@<名前>.service`(gdm3)を有効にする。ユニットのままでは立たず(DynamicUser)、gnome-shell が落ちても戻らない(on-failure)ので、drop-in で `DynamicUser=no`・`User=gdm`・`Restart=always`・`RestartSec=5` にする。GDM の自動ログインは使わない(0.2 までの見張りは外す)
- 利用者ごとの RDP:`grdctl --headless` でポート(env.yaml の `users[].port`。ずらさない)、TLS の証明書、操作の許可を設定し、`gnome-remote-desktop-headless.service`(user)を有効にする。RDP の認証情報は、まだないときだけ env.yaml の `rdp.initial_password` を入れる(本人が変えたものは上書きしない)
- スリープ無効化:`systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target`
- 利用者のホームのフォルダー名(デスクトップ、ダウンロードなど)は英語名(Desktop、Downloads など)にする
- 利用者の GNOME 設定(セッションを立てる前に一度だけ適用。画面ロックの無効化は毎回):
  - 入力ソースを `[('xkb', <配列>), ('ibus', 'mozc-on')]` にし、切り替えに Ctrl+Space を足す(101 キーボードには半角/全角キーがなく、Super は RDP クライアント側に取られやすい。jp でも半角/全角キーは RDP で押しっぱなしで届き、使えない。#21)
  - `org.gnome.desktop.session idle-delay 0`
  - `org.gnome.desktop.screensaver lock-enabled false`、`org.gnome.desktop.lockdown disable-lock-screen true`(利用者のパスワードはロックしてあるので、ロックされると本人も外せない)
  - `org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'`
  - `org.gnome.mutter check-alive-timeout 0`(忙しいアプリに「応答していません」を出さない)
- 利用者のセッションでは更新の通知(update-notifier)を出さない。apport(クラッシュ報告)は無効にする。どちらも誰も見ていない画面に残るため
- 利用者の git:名前とメールアドレス(env.yaml の `users[].git_user_name` / `git_user_email`)と `init.defaultBranch main`
- 時刻同期:chrony。env.yaml の `ntp_servers` を同期先に足す(空なら Ubuntu の既定と DHCP で配られたサーバー)
- inotify の上限:`max_user_watches=524288`、`max_user_instances=1024`(worktree を並べてファイル監視を動かすため)
- 開けるファイルの数の既定:65536(EMFILE を避けるため)
- HTTP プロキシと独自の CA 証明書(env.yaml の `proxy` / `ca_certs`。空なら何もしない):`/etc/environment`、apt、Chrome のポリシー、利用者の environment.d と Chrome の証明書データベースに入れる
- ufw:env.yaml の `dev_ports` を LAN から開ける(開発サーバーを手元の PC から見るため。利用者全員で共有し、`users[].port` とは重ねない)
- 利用者の mise(プロジェクトごとの言語のバージョン。shims を PATH に入れる)と、エージェント向けのホストの説明(`~/.claude/CLAUDE.md`、`~/.codex/AGENTS.md`。既にあれば上書きしない)
- エディター:env.yaml の `editors` で vscode / neovim / zed から選ぶ
- VS Code の表示は日本語にする(Language Pack を入れ、`~/.vscode/argv.json` に `"locale": "ja"` を書く)
- VS Code の拡張機能:日本語の表示、Claude Code、Codex、EditorConfig、YAML、TOML、ShellCheck、Container Tools、Git Graph、GitHub Pull Requests、Python・Pylance・Ruff、ESLint・Prettier を版を固定して入れる。clouds に合わせて AWS Toolkit・Google Cloud Code・Azure Resources・Terraform を足す。env.yaml の `vscode_extensions` で追加できる。自動更新は止める
- Zed の拡張機能:TOML、Dockerfile、Docker Compose、HTML、Make、SQL、env、Git Firefly(clouds を選んだら Terraform)を、設定の auto_install_extensions で次の起動時に入れる。Zed には版を指定する方法がないので、入ったときの最新にし、その後は auto_update_extensions で更新を止める。env.yaml の `zed_extensions` で追加できる
- 追加の AI エージェント:env.yaml の `agents` で OpenCode / GitHub Copilot CLI / Antigravity CLI から選ぶ(Claude Code と Codex はいつも入れる)。版を固定し、自動更新を止める
- クラウドの CLI:env.yaml の `clouds` で AWS CLI v2 / Google Cloud CLI / Azure CLI から選ぶ。版を固定し、利用状況の送信を止める。認証は短い時間だけ有効なログインと、権限を絞った開発用のアカウントで使う。Terraform・OpenTofu・kubectl・Helm などはホストに入れず、エージェントが mise で入れる
- 通知:Claude Code の hooks(承認待ち・入力待ち・API のエラー)と Codex の notify(完了)から `agent-notify` を呼び、env.yaml の `notify` の Slack(Incoming Webhook)と IP Messenger(LAN 内の UDP)に送る。承認待ちとエラーは両方、完了は Slack だけ。本文の頭は `[ホスト名/利用者名]`
- スマホからの操作は Claude Code の Remote Control を使う(手作業。docs/manual-steps.md)
- UPS(任意。env.yaml の `ups`):NUT で見る。`usb` はこの PC につないだ UPS をドライバーで読み(upsd は 127.0.0.1 だけ)、`netclient` はほかの機器の NUT サーバーを見る。バッテリーが少なくなるか、NUT サーバーが終了を指示したら正しく終了する。`usb` では終了の最後に UPS の出力を止め、電源が戻ったら UPS が出力を戻し、BIOS の「電源が戻ったら起動」で起動する(そのあとは利用者ごとのセッションと RDP まで人手なしで戻る)。停電・復電・まもなく終了などを `agent-notify` で知らせる
- IP Messenger の通知先は、ユーザー名・PC 名・ニックネームか IP で指定する。名前は送るたびに LAN へブロードキャストして探す(DHCP で IP が変わっても届く)
- サービスは最小限にする:印刷、avahi、ModemManager、Bluetooth、root の containerd、rsyslog などを mask する。Canonical への利用状況の送信(ubuntu-insights)と定期の取得を止める。利用者のセッションのファイルの索引作り、予定表、Xwayland の常時起動などを止める。snap と snapd(apt でも入らないように止める)、kdump、使わないパッケージ(画面の読み上げ・点字、印刷のドライバー、sssd、VPN・モデム、Bluetooth、中国語の入力、whoopsie・apport・ubuntu-report・ubuntu-insights)を消す。cups 本体はデスクトップのまとめの必須なので、消さずに止める
- 資源の最適化:zram(メモリの半分。vm.swappiness 180、vm.page-cluster 0)、電源のプロファイル performance(ない機種では balanced のまま)、RDP の画面の符号化を GPU に任せる(gnome-remote-desktop の Vulkan と VA-API による H.264。Intel は VA-API の full 版、AMD は Mesa、NVIDIA はインストールの中でプロプライエタリ ドライバーを入れて NVENC)、Docker の通信は pasta・ログは 10MB×3・週 1 回の掃除、ディスクの使用率 85% 超を通知、GRUB の待ちを 5 秒、起動画面(splash)を出さない、構成の最後に apt のキャッシュと古いダウンロードを消す
- デスクトップ:端末は Xfce Terminal(右クリックで貼り付け、選択でコピー)、Caps Lock は無効(caps:none)、クリップボードの履歴は Clipboard Indicator、PDF は Atril(既定のアプリ)、スクリーンショットに Ctrl+Shift+Alt+S、アニメーションなし、壁紙は env.yaml の desktop_color の単色、Dock を絞る、Chrome の利用統計・パスワードの保存を止める
- 移行:agent-host-backup / agent-host-restore で、ホストの身元・利用者全員のログインと設定・~/work を移す(取り込みはこのホストの users にいる名前の分だけ。RDP の認証情報もホームごと移る)(ツールの本体、Docker のイメージ、Chrome のプロファイルは移さない。~/work からは実際に見つけた node_modules・__pycache__・.venv だけを除き、名前だけでは除かない)
- SSH:パスワード認証無効、root ログイン無効
- SSH に入れるのは sysadmin と今の利用者だけ(`AllowUsers`)
- ufw:SSH(22)と利用者ごとの RDP のポート(外した人の分は消す)、`dev_ports`、IP Messenger を使うときの UDP 2425 を LAN(`lan_cidrs`)だけ許可、それ以外は拒否
- unattended-upgrades:セキュリティ更新と Google Chrome のみ、自動再起動しない
- 開発ツール:git、Node.js(LTS)、Claude Code、Codex(`@openai/codex`)、GitHub CLI(`gh`)、Gitea CLI(`tea`。env.yaml の `gitea_url` を tea のログインの既定の接続先にし、エージェント向けの説明にも載せる)、uv、mise、CCManager、corepack(pnpm / yarn)、build-essential、python3-dev、python3-venv、python3-pip、python-is-python3(`python` を python3 にする)、pkg-config、libssl-dev、ripgrep、fd-find、jq、tree、htop、tmux、sqlite3、shellcheck、zip、unzip、wget、rsync、git-lfs、wl-clipboard、dnsutils、netcat-openbsd
- Docker:公式 apt リポジトリから導入し、利用者ごとの rootless Docker にする(linger で再起動後も自動で起動)。root で動く通常のデーモンは止める。利用者を docker グループに入れると実質 root になるので入れない
- Orca:公式 .deb を導入し、利用者ごとの `~/.config/autostart/orca.desktop` で自動起動
- Google Chrome:公式 apt リポジトリから導入し、利用者の既定のブラウザにする。最新版しか配布されないので固定せず、unattended-upgrades で自動更新する
- Node.js、npm パッケージ、Claude Code、Orca、GitHub CLI、Gitea CLI、Docker、uv、mise、VS Code とその拡張機能、Zed、クラウドの CLI、Clipboard Indicator はバージョンを固定する(勝手に上がらないように)

### 5.3 手作業(初回のみ。docs/manual-steps.md に手順化する)
1. BIOS:Restore on AC Power Loss を Power On に
2. (利用者ごと)最初の RDP で、自分の RDP のパスワードを変える(`grdctl --headless rdp set-credentials`)
3. (利用者ごと、以下同じ)Claude Code のログイン
4. Codex のログイン(`codex login --device-auth`。事前に ChatGPT のセキュリティ設定でデバイスコード認証を有効化)
5. Orca 初回起動、`~/.claude` / `~/.codex` 設定の取り込み、利用統計と更新の通知をオフ
6. GitHub の認証(`gh auth login`、`gh auth setup-git`)、Gitea の認証(`tea login add --git-credentials`)、Docker Hub へのログイン(`docker login`)
7. 選んだ追加のエージェント(OpenCode・Copilot CLI・Antigravity CLI)とクラウドの CLI(`aws sso login`・`gcloud auth login`・`az login`)のログイン
8. 通知の確認と、使う場合は Claude Code の Remote Control

ログインキーリング(空パスワード)と RDP の設定(ポート、TLS、仮の認証情報)はスクリプト化した。0.2 までの手作業(キーリングのパスワードを空にする、デスクトップ共有をオンにする)は要らない。

## 6. 非機能要件
- スクリプトは冪等(何度流しても同じ結果)
- リポジトリに秘密情報を含めない(パスワードハッシュ・SSH 公開鍵・IP 範囲などの環境固有値は別ファイルに分離し、サンプルのみコミット)
- 構成の変更は `just update` で OS を入れなおさずに反映する。hostname・network・keyboard_layout はインストールのときだけ効き、desktop_color はセッションで反映する。users の rdp.initial_password は、その利用者に RDP の認証情報がまだないときだけ入る(線引きは render-autoinstall.py の UPDATE_SCOPE と manual-steps の表)。late-commands からは同梱スクリプトを呼ぶだけにする(後で Ansible 化しやすいように)
- root は利用者のホームの中を root で読み書きしない(`agent_run`・`write_agent_file`。利用者の置いたリンクをたどってホームの外を書き換えないため)
- 手元の一時ファイル(写した env.yaml、ISO など)は、実行ごとの `build/.run.XXXXXX` に置き、終わったら消す
- 実機の構成は、別の非公開リポジトリ(構成リポジトリ)で管理できるようにする(docs/fleet.md)。env.yaml は複数のファイルを重ねて使え(共通 + ホスト)、知らないキーはエラーにする。リポジトリの外の env.yaml も扱える。置いた版(道具の版、構成の版、作った日時)をホストの `/opt/agent-host/BUILD-INFO`、構成が最後まで成功した版を `/var/lib/agent-host/BUILD-INFO.ok` に残し、実行中の印 `provision-incomplete` で失敗・中断を見分ける。`just status`・`just facts`・`just verify` で見せる
- 受け入れテストのうち人が見なくても判定できるものは、機械で確かめられるようにする(docs/acceptance-test.md「機械で確かめる」)。env.yaml の検査の試験(`just test`)、ホストの構成の検査(`just verify`。読むだけ)、RDP の認証(`just verify-rdp`。仮のパスワードで通らなければ「未検証」、`--ask` で今のパスワード)、VM への入れなおし(2 人の env)から電源断・セッションの異常終了からの戻りまでの通し(`just vm-test`)

## 7. 受け入れテスト
1. USB からインストール → 手作業なしで完了する
2. 手作業(§5.3)を実施
3. 電源ケーブルを抜き差し → 自動で起動する
4. 何も操作せず、手元PCから RDP 接続 → Orca 起動済みの画面が出る(利用者ごとの port。2 人が同時につなげる)
5. Orca から Claude Code / Codex でそれぞれ簡単なタスクを1本ずつ実行できる
6. RDP 切断 → 10分後に再接続 → タスクが継続している
7. LAN の外(または許可範囲外)から 22 / 利用者の RDP のポートに到達できない
8. GNOME のセッションが落ちても、何もしなくてもその人のセッションと RDP が戻り、ほかの利用者は影響を受けない
9. 利用者どうしは、互いのホームを読めない

1・3・4(認証まで)・8 は `just vm-test` が VM で人手なしに行う。

## 8. 設計上の決定と理由

| 決定 | 理由 |
|---|---|
| エージェントの作業環境は Orca | Linux の .deb、Claude Code と Codex の併用、worktree ごとの並列、MIT、アカウント不要、.deb 版は自分で更新しない(版を固定できる)、利用統計を止められる、の条件をすべて満たし、開発がもっとも活発。代替の比較は notes.md「Orca を選んだ理由」。GUI が使えないときの予備に TUI の CCManager を入れる |
| Ubuntu Desktop 26.04 LTS | 常時稼働でもGUIが必要。Server + デスクトップ追加より手直しが少ない |
| xrdp ではなく gnome-remote-desktop | Ubuntu の GNOME のセッションは 25.10 から Wayland だけで、xrdp の Xorg のセッションでは GNOME が動かない(Xfce などは動く) |
| 利用者ごとのヘッドレスのセッション(全員。seat0 の自動ログインとデスクトップ共有はやめた) | 1 つのセッションを共有すると、全員が同じ Claude Code・Codex のログイン(ひとりのサブスクリプション)で動く。セッションの中で設定の場所を分けても、同じセッションに入れる人は誰の認証情報でも使える。systemd が起動のときに全員のセッションを立て、落ちたら立てなおすので、人手なしで戻る目的も保てる。1 人の台も同じ作り(比較は notes.md「利用者ごとのヘッドレスのセッション」) |
| GDM の「リモートログイン」は使わない | ログインするまでセッションと Orca が動かず、再起動のあとに人手が要る |
| 利用者のキーリングを空パスワードに | パスワードなしで立てるセッションではキーリングが開かず、アプリが新しいキーリングのパスワードを聞いてくるため。中身はホームの 700 だけで守られる(sysadmin は読める) |
| RDP のパスワードは仮の値を入れ、本人が変える | env.yaml の値は ISO と構成リポジトリの管理者に見える。利用者どうしを隔てる実質の境界なので、本人だけが知る値にする |
| RDP のポートは利用者に固定する(env.yaml で必須) | 並び順で決めると、利用者を外したり並べ替えたりしたときに、残った人の接続先が変わる |
| sudo のない専用ユーザーと rootless Docker(docker グループは使わない) | docker グループに入れると実質 root と同じになる |
| ホームはローカルのディスク(NFS は使わない) | NFS が見えないとセッションが立たない。rootless Docker の置き場や各ツールの SQLite が NFS の上では崩れる |
| ディスクは暗号化しない | 選ぶ手段は用意していない。使うなら TPM 連動の暗号化(パスフレーズなしで無人再起動できる)を autoinstall.yaml を手で直して行う(未対応・未確認)。パスフレーズ方式は無人復帰と両立しない |
| LAN の外からは VPN 経由 | RDP のポートをインターネットに開けない |

## 9. 未確定事項(実装時に確認)

調べた結果と、まだ確認できていない点は notes.md の「調査と検証の記録」と「確認できていないこと」に書く。
- [済] Ubuntu Desktop 26.04 の autoinstall で、上記要件がすべて表現できるか(Server 版との差分)
- [VM で済、実機は未] 26.04 で「利用者ごとのヘッドレスのセッション + 空パスワードキーリング + headless の RDP」が再起動後に確実に有効になるか(実機の GPU での符号化は未確認)
- [済] headless の RDP の設定と認証情報を、root から `grdctl --headless` でスクリプト化できるか
- [済] Orca .deb の入手 URL とバージョン固定・自動更新停止の方法
- [済] Claude Code の Linux 上での推奨インストール方法(公式の apt リポジトリ)
- [対象外] LAN の外からの接続方式(VPN など)は、使う組織の方針に任せる

## 10. 対象外
- Orca / Claude Code / Codex の利用ルール。誰に使わせるか(アカウントは利用者ごとに分けるが、誰を利用者にするかは対象外)
- 複数台の一括展開(PXE、MAAS 等)
- Ansible 化(将来課題。スクリプト構成はそれを妨げないようにする)
