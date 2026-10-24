# agent-host-autoinstall — SPEC

手元に置く物理 PC を、AIコーディングエージェント(Claude Code / Codex)を Orca(ADE)で並列稼働させる「常時稼働エージェントホスト」として自動構成するための仕様。

## 1. 目的

背景: コーディングエージェントは 1 つの作業に長い時間がかかり、確認なしで動かすことも多い。手元の PC で並べて動かすと、閉じられず、私的なファイルや個人のログイン情報のある環境を触らせることになる。クラウドのエージェントは各社ごとに別々で、GitHub が前提で、LAN の資源に届かない。そこで、LAN の中に専用の PC を置き、Orca でエージェントを並べて見比べ、どこからでも RDP でその画面に入れるようにする。Orca の Remote Orca Server と同じく「作業する PC」と「操作する PC」を分ける形で、作業する側を OS ごと人手なしで保つ(比較は notes.md「専用の PC を置く理由」)。

- USBメモリ1本から、決まった構成の Ubuntu Desktop を無人に近い形でインストールできること
- 再起動やセッションの異常終了のあとも、人手を介さず Orca が起動し、RDP で接続できる状態に戻ること(電源が戻ったときに起動するのは BIOS の設定で行う)
- 構成をコードとして管理し、同じ環境を何台でも再現できること

## 2. 対象環境

| 項目 | 内容 |
|---|---|
| OS | Ubuntu Desktop 26.04 LTS(GNOME のセッションは Wayland のみ。xrdp は別のセッションを作り、GNOME の画面の前のセッションを共有できないため不採用) |
| 言語・地域 | 日本語の環境向け。ロケール ja_JP.UTF-8、タイムゾーン Asia/Tokyo、日本語入力 Mozc(autoinstall.yaml と first-login で固定) |
| ハードウェア | x86_64 の物理PC。メモリ 32GB 以上、NVMe SSD 推奨 |
| 画面 | 物理モニターなし運用。HDMI ダミープラグを挿す |
| ネットワーク | LAN。固定IP(または DHCP 予約) |
| 遠隔操作 | GNOME 標準リモートデスクトップの「デスクトップ共有」(RDP) |
| 管理操作 | SSH(鍵認証のみ) |

## 3. 全体の流れ

```
電源投入
  → agent ユーザーで自動ログイン
  → GNOME 起動(ログインキーリングは空パスワードなので自動で開く)
  → デスクトップ共有(RDP :3389)が待ち受け開始
  → Orca が autostart で起動
LAN の RDP クライアント → :3389 → agent のデスクトップを操作
管理者 → SSH → sysadmin ユーザー
```

## 4. ユーザー

| ユーザー | 用途 | sudo | ログイン |
|---|---|---|---|
| `sysadmin` | OS 管理・更新 | あり | SSH 鍵認証のみ(パスワード認証は無効) |
| `agent` | Orca / Claude Code / Codex の実行 | なし | GDM 自動ログイン。SSH は SFTP 専用(env.yaml に鍵を書いた人だけ。シェルには入れない) |

`agent` はこのホストを使う 1 人のためのユーザー。置く秘密は、その人の各サービスのログイン(サブスクリプションを含む)だけにする。複数の人で 1 台を共有しない(サブスクリプションの共有になる)。

## 5. 機能要件

### 5.1 OS インストール(autoinstall)
- ロケール `ja_JP.UTF-8`、タイムゾーン `Asia/Tokyo`(日本語入力の ibus-mozc と日本語フォントは、ロケールの指定でインストーラーが入れる)
- キーボード配列は env.yaml の `keyboard_layout`(`us` / `jp`)で台ごとに決める。RDP ではキーの位置がそのまま送られ、ホスト側の配列で文字になるので、RDP で使う人のキーボードに合わせる
- ストレージは LVM、ディスク全体を使用(`sizing-policy: all`。既定の scaled はボリュームグループの半分ほどを空けて残す。暗号化はオプション。§8 参照)
- ネットワークは env.yaml の `network` で、DHCP か固定 IP(アドレス、ゲートウェイ、DNS、検索ドメイン)を台ごとに決める。インストール中もこの設定で通信し、インストール後は NetworkManager が管理する
- `sysadmin` ユーザーと SSH 公開鍵を登録
- openssh-server を導入

### 5.2 インストール後の構成(late-commands / スクリプト)
late-commands は同梱スクリプトを `/opt/agent-host` に置き、初回起動時の構成サービス(`agent-host-provision.service`)を有効にするだけにする。構成そのものは、初回起動時にこのサービスが `post-install/` を番号順に実行する(GDM の起動前)。インストール中の chroot では ufw などが動かないため。`agent` のセッションが要る設定(gsettings、grdctl)は first-login で行う。

- `agent` ユーザー作成(sudo なし)
- GDM 自動ログイン:`/etc/gdm3/custom.conf` に `AutomaticLoginEnable=true` / `AutomaticLogin=agent`。GNOME のセッションが落ちてログイン画面のままになったら、見張りのタイマーが GDM を再起動して自動ログインさせ、通知する
- スリープ無効化:`systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target`
- `agent` のホームのフォルダー名(デスクトップ、ダウンロードなど)は英語名(Desktop、Downloads など)にする
- `agent` の GNOME 設定(初回ログイン時に適用):
  - 入力ソースを `[('xkb', <配列>), ('ibus', 'mozc-on')]` にし、切り替えに Ctrl+Space を足す(101 キーボードには半角/全角キーがなく、Super は RDP クライアント側に取られやすい)
  - `org.gnome.desktop.session idle-delay 0`
  - `org.gnome.desktop.screensaver lock-enabled false`
  - `org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'`
  - `org.gnome.mutter check-alive-timeout 0`(忙しいアプリに「応答していません」を出さない)
- `agent` では更新の通知(update-notifier)を出さない。apport(クラッシュ報告)は無効にする。どちらも誰も見ていない画面に残るため
- `agent` の git:名前とメールアドレス(env.yaml の `git_user_name` / `git_user_email`)と `init.defaultBranch main`
- 時刻同期:chrony。env.yaml の `ntp_servers` を同期先に足す(空なら Ubuntu の既定と DHCP で配られたサーバー)
- inotify の上限:`max_user_watches=524288`、`max_user_instances=1024`(worktree を並べてファイル監視を動かすため)
- 開けるファイルの数の既定:65536(EMFILE を避けるため)
- HTTP プロキシと独自の CA 証明書(env.yaml の `proxy` / `ca_certs`。空なら何もしない):`/etc/environment`、apt、Chrome のポリシー、agent の environment.d と Chrome の証明書データベースに入れる
- ufw:env.yaml の `dev_ports` を LAN から開ける(開発サーバーを手元の PC から見るため)
- `agent` の mise(プロジェクトごとの言語のバージョン。shims を PATH に入れる)と、エージェント向けのホストの説明(`~/.claude/CLAUDE.md`、`~/.codex/AGENTS.md`。既にあれば上書きしない)
- エディター:env.yaml の `editors` で vscode / neovim / zed から選ぶ
- VS Code の表示は日本語にする(Language Pack を入れ、`~/.vscode/argv.json` に `"locale": "ja"` を書く)
- VS Code の拡張機能:日本語の表示、Claude Code、Codex、EditorConfig、YAML、TOML、ShellCheck、Container Tools、Git Graph、GitHub Pull Requests、Python・Pylance・Ruff、ESLint・Prettier を版を固定して入れる。clouds に合わせて AWS Toolkit・Google Cloud Code・Azure Resources・Terraform を足す。env.yaml の `vscode_extensions` で追加できる。自動更新は止める
- Zed の拡張機能:TOML、Dockerfile、Docker Compose、HTML、Make、SQL、env、Git Firefly(clouds を選んだら Terraform)を、設定の auto_install_extensions で次の起動時に入れる。Zed には版を指定する方法がないので、入ったときの最新にし、その後は auto_update_extensions で更新を止める。env.yaml の `zed_extensions` で追加できる
- 追加の AI エージェント:env.yaml の `agents` で OpenCode / GitHub Copilot CLI / Antigravity CLI から選ぶ(Claude Code と Codex はいつも入れる)。版を固定し、自動更新を止める
- クラウドの CLI:env.yaml の `clouds` で AWS CLI v2 / Google Cloud CLI / Azure CLI から選ぶ。版を固定し、利用状況の送信を止める。認証は短い時間だけ有効なログインと、権限を絞った開発用のアカウントで使う。Terraform・OpenTofu・kubectl・Helm などはホストに入れず、エージェントが mise で入れる
- 通知:Claude Code の hooks(承認待ち・入力待ち・API のエラー)と Codex の notify(完了)から `agent-notify` を呼び、env.yaml の `notify` の Slack(Incoming Webhook)と IP Messenger(LAN 内の UDP)に送る。承認待ちとエラーは両方、完了は Slack だけ
- スマホからの操作は Claude Code の Remote Control を使う(手作業。docs/manual-steps.md)
- UPS(任意。env.yaml の `ups`):NUT で見る。`usb` はこの PC につないだ UPS をドライバーで読み(upsd は 127.0.0.1 だけ)、`netclient` はほかの機器の NUT サーバーを見る。バッテリーが少なくなるか、NUT サーバーが終了を指示したら正しく終了する。`usb` では終了の最後に UPS の出力を止め、電源が戻ったら UPS が出力を戻し、BIOS の「電源が戻ったら起動」で起動する(そのあとは自動ログインと RDP まで人手なしで戻る)。停電・復電・まもなく終了などを `agent-notify` で知らせる
- IP Messenger の通知先は、ユーザー名・PC 名・ニックネームか IP で指定する。名前は送るたびに LAN へブロードキャストして探す(DHCP で IP が変わっても届く)
- サービスは最小限にする:印刷、avahi、ModemManager、Bluetooth、root の containerd、rsyslog などを mask する。Canonical への利用状況の送信(ubuntu-insights)と定期の取得を止める。agent のファイルの索引作り、予定表、Xwayland の常時起動などを止める。snap と snapd(apt でも入らないように止める)、kdump、使わないパッケージ(画面の読み上げ・点字、印刷のドライバー、sssd、VPN・モデム、Bluetooth、中国語の入力、whoopsie・apport・ubuntu-report・ubuntu-insights)を消す。cups 本体はデスクトップのまとめの必須なので、消さずに止める
- 資源の最適化:zram(メモリの半分)、電源のプロファイル performance(ない機種では balanced のまま)、RDP の画面の符号化を GPU に任せる(gnome-remote-desktop の Vulkan と VA-API による H.264。Intel は VA-API の full 版、AMD は Mesa、NVIDIA はインストールの中でプロプライエタリ ドライバーを入れて NVENC)、Docker の通信は pasta・ログは 10MB×3・週 1 回の掃除、ディスクの使用率 85% 超を通知、GRUB の待ちを 5 秒、構成の最後に apt のキャッシュと古いダウンロードを消す
- デスクトップ:端末は Xfce Terminal(右クリックで貼り付け、選択でコピー)、Caps Lock は無効(caps:none)、クリップボードの履歴は Clipboard Indicator、スクリーンショットに Ctrl+Shift+Alt+S、アニメーションなし、壁紙は env.yaml の desktop_color の単色、Dock を絞る、Chrome の利用統計・パスワードの保存を止める
- 移行:agent-host-backup / agent-host-restore で、ホストの身元・ログインと設定・~/work を移す(ツールの本体、Docker のイメージ、Chrome のプロファイルは移さない。~/work からは実際に見つけた node_modules・__pycache__・.venv だけを除き、名前だけでは除かない)
- SSH:パスワード認証無効、root ログイン無効
- ufw:SSH(22)と RDP(3389)を LAN だけ許可、それ以外は拒否
- unattended-upgrades:セキュリティ更新と Google Chrome のみ、自動再起動しない
- 開発ツール:git、Node.js(LTS)、Claude Code、Codex(`@openai/codex`)、GitHub CLI(`gh`)、Gitea CLI(`tea`。env.yaml の `gitea_url` を tea のログインの既定の接続先にし、エージェント向けの説明にも載せる)、uv、mise、CCManager、corepack(pnpm / yarn)、build-essential、python3-dev、python3-venv、python3-pip、pkg-config、libssl-dev、ripgrep、fd-find、jq、tree、htop、tmux、sqlite3、shellcheck、zip、unzip、wget、rsync、git-lfs、wl-clipboard、dnsutils、netcat-openbsd
- Docker:公式 apt リポジトリから導入し、`agent` 専用の rootless Docker にする(linger で再起動後も自動で起動)。root で動く通常のデーモンは止める。`agent` を docker グループに入れると実質 root になるので入れない
- Orca:公式 .deb を導入し、`agent` の `~/.config/autostart/orca.desktop` で自動起動
- Google Chrome:公式 apt リポジトリから導入し、`agent` の既定のブラウザにする。最新版しか配布されないので固定せず、unattended-upgrades で自動更新する
- Node.js、npm パッケージ、Claude Code、Orca、GitHub CLI、Gitea CLI、Docker、uv、mise、VS Code、Zed、クラウドの CLI はバージョンを固定する(勝手に上がらないように)

### 5.3 手作業(初回のみ。docs/manual-steps.md に手順化する)
1. BIOS:Restore on AC Power Loss を Power On に
2. `agent` のログインキーリングを空パスワードに変更
3. 設定 → システム → リモートデスクトップ → デスクトップ共有をオン、リモート操作をオン、RDP 用の認証情報を設定
4. Claude Code のログイン
5. Codex のログイン(`codex login --device-auth`。事前に ChatGPT のセキュリティ設定でデバイスコード認証を有効化)
6. Orca 初回起動、`~/.claude` / `~/.codex` 設定の取り込み、利用統計と更新の通知をオフ
7. GitHub の認証(`gh auth login`、`gh auth setup-git`)、Gitea の認証(`tea login add --git-credentials`)、Docker Hub へのログイン(`docker login`)
8. 選んだ追加のエージェント(OpenCode・Copilot CLI・Antigravity CLI)とクラウドの CLI(`aws sso login`・`gcloud auth login`・`az login`)のログイン
9. 通知の確認と、使う場合は Claude Code の Remote Control

2〜3 はスクリプト化した(2 は空パスワードのキーリングを最初から置く、3 は first-login で `grdctl` を実行する)。ただし実機では未確認なので、効かなかったときの手作業を docs/manual-steps.md に残す。

## 6. 非機能要件
- スクリプトは冪等(何度流しても同じ結果)
- リポジトリに秘密情報を含めない(パスワードハッシュ・SSH 公開鍵・IP 範囲などの環境固有値は別ファイルに分離し、サンプルのみコミット)
- 構成変更は OS 再インストールなしで適用できる形を目指す(後で Ansible 化しやすいように、late-commands からは同梱スクリプトを呼ぶだけにする)
- 実機の構成は、別の非公開リポジトリ(構成リポジトリ)で管理できるようにする(docs/fleet.md)。env.yaml は複数のファイルを重ねて使え(共通 + ホスト)、知らないキーはエラーにする。リポジトリの外の env.yaml も扱える。作った版(道具の版、構成の版、作った日時)をホストの `/opt/agent-host/BUILD-INFO` に残し、`just status` と `just facts` で見せる
- 受け入れテストのうち人が見なくても判定できるものは、機械で確かめられるようにする(docs/acceptance-test.md「機械で確かめる」)。env.yaml の検査の試験(`just test`)、ホストの構成の検査(`just verify`。読むだけ)、RDP の認証(`just verify-rdp`)、VM への入れなおしから電源断・セッションの異常終了からの戻りまでの通し(`just vm-test`)

## 7. 受け入れテスト
1. USB からインストール → 手作業なしで完了する
2. 手作業(§5.3)を実施
3. 電源ケーブルを抜き差し → 自動で起動する
4. 何も操作せず、手元PCから RDP 接続 → Orca 起動済みの画面が出る
5. Orca から Claude Code / Codex でそれぞれ簡単なタスクを1本ずつ実行できる
6. RDP 切断 → 10分後に再接続 → タスクが継続している
7. LAN の外(または許可範囲外)から 22 / 3389 に到達できない
8. GNOME のセッションが落ちても、何もしなくてもセッションと RDP が戻る

1・3・4(認証まで)・8 は `just vm-test` が VM で人手なしに行う。

## 8. 設計上の決定と理由

| 決定 | 理由 |
|---|---|
| エージェントの作業環境は Orca | Linux の .deb、Claude Code と Codex の併用、worktree ごとの並列、MIT、アカウント不要、.deb 版は自分で更新しない(版を固定できる)、利用統計を止められる、の条件をすべて満たし、開発がもっとも活発。代替の比較は notes.md「Orca を選んだ理由」。GUI が使えないときの予備に TUI の CCManager を入れる |
| Ubuntu Desktop 26.04 LTS | 常時稼働でもGUIが必要。Server + デスクトップ追加より手直しが少ない |
| xrdp ではなく GNOME デスクトップ共有 | xrdp は別のセッションを作るので、自動ログインで起動した Orca が見えない。また Ubuntu の GNOME のセッションは 25.10 から Wayland だけで、xrdp の Xorg のセッションでは GNOME が動かない(Xfce などは動く)。デスクトップ共有は物理セッションを共有するので、自動ログイン + Orca 自動起動と両立し、再起動後も人手不要 |
| 「リモートログイン」モードは使わない | 再起動後にログインするまでOrcaが動かない。併用するとデスクトップ共有が3390番に移り混乱する |
| `agent` のキーリングを空パスワードに | 自動ログインではキーリングが開かず、デスクトップ共有の認証情報が読めないため。`agent` は 1 人で使う専用ユーザーで、置く秘密はその人の各サービスのログインだけ、という前提で許容 |
| HDMI ダミープラグ | モニターなしだと描画されない機種がある |
| ディスク暗号化はオプション | 使うなら TPM 連動の暗号化(パスフレーズなしで無人再起動できる)。パスフレーズ方式は無人復帰と両立しない |
| LAN の外からは VPN 経由 | 3389 をインターネットに開けない |

## 9. 未確定事項(実装時に確認)

調べた結果と、まだ確認できていない点は notes.md の「調査と検証の記録」と「確認できていないこと」に書く。
- [済] Ubuntu Desktop 26.04 の autoinstall で、上記要件がすべて表現できるか(Server 版との差分)
- [VM で済、実機は未] 26.04 で「自動ログイン + 空パスワードキーリング + デスクトップ共有」が再起動後に確実に有効になるか
- [済] デスクトップ共有の有効化と RDP 認証情報の設定を `grdctl` でスクリプト化できるか
- [済] Orca .deb の入手 URL とバージョン固定・自動更新停止の方法
- [済] Claude Code の Linux 上での推奨インストール方法(公式の apt リポジトリ)
- [対象外] LAN の外からの接続方式(VPN など)は、使う組織の方針に任せる

## 10. 対象外
- Orca / Claude Code / Codex の利用ルールやアカウント管理
- 複数の人で 1 台を使う仕組み(利用者ごとのセッション)。今は 1 人 1 台
- 複数台の一括展開(PXE、MAAS 等)
- Ansible 化(将来課題。スクリプト構成はそれを妨げないようにする)
