# HANDOVER.md

## これまでの経緯(設計段階で決めたこと)

1. オンプレPCへの Ubuntu 自動構成は、公式の autoinstall を使う。Server 専用ではなく Desktop でも使える
2. 常時稼働させたいが、AI エージェントを動かすためにデスクトップが必要 → Desktop 版に常時稼働の設定を足す方針
3. エージェントの作業環境は Orca(stablyai/orca。Claude Code や Codex を git worktree ごとに並列実行する ADE)。Codex も併用する
4. 遠隔操作は当初 xrdp を検討したが、以下の理由で GNOME 標準の「デスクトップ共有」(RDP)に変更
   - Ubuntu 26.04 LTS は Wayland のみで、xrdp が使えない
   - xrdp やリモートログインは別セッションを作るため、再起動後に誰かがログインするまで Orca が起動しない
   - デスクトップ共有は物理セッションを共有するので、自動ログイン + Orca 自動起動と両立する
5. 自動ログインではキーリングが開かず、デスクトップ共有の認証情報が読めない問題がある → `agent` ユーザーのキーリングを空パスワードにする(専用ユーザー・秘密情報なしが前提)

詳細は SPEC.md §8 を参照。

## 現状(2026-10-24)

- §9 を調査し(結果は下)、autoinstall.yaml・env.example.yaml・scripts/・justfile・docs/manual-steps.md・docs/acceptance-test.md・docs/setup-guide.tex(PDF の手順書)・docs/release.md(リリースの手順)を一通り作った
- 2026-10-24 に、すべての修正を含めた ISO で VirtualBox に新しく入れなおし、受け入れテスト 1〜6・8 の範囲を確かめた(下の「次にやること」の 1)。残りは実機での確認(テスト 7 など)と、最初のリリース(v0.1.0)
- shellcheck(0.11.0、Docker の ubuntu:26.04)は指摘なし
- **VirtualBox で一通り動いた(2026-10-23)。** ubuntu-26.04.1-desktop-amd64.iso から build-usb.sh で作った ISO で、確認画面なしにインストール → 初回起動の構成 → agent の自動ログイン → first-login → RDP の待ち受けまで、手を触れずに通った。再起動と強制電源オフ後も、何もせずに RDP の認証が通る(受け入れテスト 1・3・4 の範囲。結果は docs/acceptance-test.md)
  - 環境: Windows 10 + VirtualBox 7.2.6。Hyper-V(Docker Desktop)が有効なため VirtualBox は NEM モードで動き、CPU 2 つ以上ではゲストのカーネルが止まった。CPU 1・メモリ 4GB で試した(インストールに約 47 分)
  - 2026-10-24 に作業者が mstsc(101 キーボード)で入り、受け入れテスト 2・4・5・6 を確かめた(結果は docs/acceptance-test.md)。テスト 7 は実機で行う
- 実装の都合で SPEC.md から変えた点: post-install は late-commands の中ではなく、初回起動時の `agent-host-provision.service` が実行する(インストール中の chroot では ufw などが動かないため)。SPEC.md §5.2 に反映済み

## 次にやること(この順で)

- (2026-10-24 追加)最初のリリースは、実機での受け入れテスト(下の 2)が通ってから docs/release.md の手順で v0.1.0(pre-release)として出す(作業者の判断。1.0 はしばらく運用してから)。手順書の PDF を GitHub Release に付ける Actions も、そのときが初めての実行になる
1. ~~すべての修正を含めた ISO で VirtualBox の VM を入れ直し、新規インストールでしか確かめられない点を見る: sizing-policy: all、env.yaml の network(固定 IP)、英語のフォルダー名、gnome-initial-setup が出ないこと、TLS の設定順、us 配列 + mozc-on~~ 済み(2026-10-24、feature/release-flow の ISO)。USB からの起動から構成の完了まで約 67 分、再起動から RDP の待ち受けまで約 80 秒。ルートがディスクのほぼ全部、固定 IP、英語のフォルダー名、初回の案内が出ない、TLS、us + mozc-on、caps:none、Clipboard Indicator、Xfce Terminal、追加のエージェントとエディター、rootless Docker を確かめた。構成の途中で mask したサービス(cups.path など)と syslog.socket が failed のまま残っていたので、36-minimize.sh で reset-failed し、syslog.socket も止めるようにした
2. 実機で受け入れテスト(SPEC.md §7、docs/acceptance-test.md)。特にダミープラグでの RDP、社内ネットワークでの固定 IP と NTP、lan_cidrs の外からの到達(テスト 7)
3. 下の「未確認」を潰す

## §9 の調査結果(2026-10-23)

確度: 確認済み = 公式文書かソースで確かめた / 推定 = 記述から導いた / 未確認 = 実機で試していない、または一次情報がない

### 26.04 Desktop の autoinstall
- Desktop 23.04 以降は autoinstall に公式対応(確認済み)。GUI(ubuntu-desktop-provision)が subiquity を呼ぶ構成
- 設定は ISO 直下の `/autoinstall.yaml` を `/cdrom/autoinstall.yaml` として読む(確認済み、subiquity のソース)。dd で書いた USB には後から足せないので、build-usb.sh は xorriso で ISO を作り直す
- 確認画面を出さないにはカーネル引数 `autoinstall` が要る(確認済み)。build-usb.sh が grub.cfg の linux 行に足す
- Desktop ISO には openssh-server が入っていない(確認済み)。インストール中にネットワークが要る
- identity は Desktop では省略できるが、ここでは sysadmin を作るために使う(確認済み)。`admin` は予約名で使えない(VirtualBox で確認済み: "Username is reserved by the system")
- 既定のカーネルは Desktop では hwe(確認済み)
- GDM の自動ログイン設定は 26.04(gdm3 50.x)でも `/etc/gdm3/custom.conf` の `[daemon]`(確認済み、ソース)。PreSession などのスクリプトは 26.04 で廃止
- 26.04 は GNOME 50、Wayland のみ(確認済み、リリースノート)
- late-commands の時点で `/cdrom` はマウントされていて、同梱スクリプトをコピーできた(VirtualBox で確認済み)
- 26.04.1 ISO の grub.cfg は `linux /casper/vmlinuz ... --- quiet splash` の形で、build-usb.sh の書き換えが効いた(確認済み)
- `ssh.install-server: true` でインストール中に openssh-server が入った(VirtualBox で確認済み)
- 未確認: コミュニティで報告のある「shutdown が効かない」「ufw の debconf 設定が効かない」(ここでは使っていない)/ Desktop で使えないキーの公式一覧

### デスクトップ共有(gnome-remote-desktop 50.x)
- grdctl はユーザーのセッションの D-Bus が要る(確認済み、ソース)。インストール時には使えないので first-login で実行する
- `grdctl rdp enable` は gnome-remote-desktop.service(systemd user)の起動と永続的な有効化まで行う(確認済み、49.rc 以降)
- TLS 証明書は grdctl もデーモンも作らない(確認済み)。first-login が openssl で作る。GNOME 設定のトグルだけは自動で作る
- 認証情報はログインキーリング(libsecret)にしか保存されない(確認済み)。自動ログインではキーリングが開かない問題は upstream で直る見込みがない(issue #27)
- `gnome-keyring-daemon --unlock` に空入力を渡しても空パスワードのキーリングは作られない(確認済み、ソース)
- 空パスワードのキーリングは平文の `login.keyring` として保存される(確認済み、ソース)。80-agent-session.sh はその形式のファイルを最初から置く。**これで自動ログイン後に grdctl set-credentials が通り、再起動後も RDP の認証が通った(VirtualBox で確認済み)**
- 画面がロックされると RDP が切れる(確認済み、upstream の文書)。first-login で自動ロックとアイドルを止める
- view-only が既定で true なので `disable-view-only` が要る(確認済み)
- 指定ポートが使用中だと、10 個先まで空いているポートへずれる(negotiate-port、確認済み)。`disable-port-negotiation` で 3389 に固定する
- デスクトップ共有とリモートログインを両方有効にすると 3390 に移る(確認済み、Ubuntu 公式文書)
- agent の初回ログインで gnome-initial-setup の案内が前面に出る。`~/.config/gnome-initial-setup-done` と `~/.config/gnome-initial-setup/upgrade-<版>-done` を置くと出ない(26.04 の systemd user unit の条件で確認済み)
- 未確認: モニターなし(ダミープラグ)で動くか(VirtualBox には仮想ディスプレイがある)。`screen-share-mode=extend` で仮想モニターを作れるが、ダミープラグが不要になるかは不明

### Orca・Claude Code・Codex・Node.js
- Orca 1.4.237(2026-10-21)。.deb の URL は `releases/download/v<ver>/orca-ide_<ver>_amd64.deb`、SHA256 は GitHub API の digest(確認済み)。GUI 本体は `/opt/Orca/orca-ide`、`/usr/bin/orca-ide` は CLI 用のシム(確認済み、.deb を展開)
- Orca の .deb 版は自分では更新を適用しないが、更新の通知は出る。止める設定・環境変数はソースに見当たらない(確認済み、v1.4.237 のソース)
- `/opt/Orca/orca-ide` の autostart で GUI が起動し、Wayland ネイティブ(`--ozone-platform=wayland`)で動く。依存パッケージも解決した。Orca は Claude と Codex を検出した(VirtualBox で確認済み)
- Orca は `~/.codex/config.toml` に hooks の設定を追記する。こちらが置いた `check_for_update_on_startup = false` は先頭に残る(確認済み)
- Claude Code は公式 apt リポジトリ(`downloads.claude.ai/claude-code/apt/stable`)から 2.1.308-1 を入れ、apt-mark hold する。パッケージマネージャー経由では自動更新しない(確認済み、公式文書)。署名鍵の fingerprint は 31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE
- Codex 0.164.0(npm)。自分で黙って更新はせず、起動時の確認は `~/.codex/config.toml` の `check_for_update_on_startup = false` で止まる(確認済み)。`codex login --device-auth` が現行の名前(確認済み、beta 扱い)
- Node.js は公式 tar.xz の v24.22.1 を /opt に展開する。v24 は 2026-10-20 に Maintenance LTS、v26 は 2026-10-28 に Active LTS になる予定。26.04 標準の nodejs は 22 系(universe)
- パスワードを設定していない(ロック状態の)agent で GDM の自動ログインが通る(VirtualBox で確認済み)

### SSH・日本語入力・Chrome(2026-10-23 追加)
- SSH: sysadmin で鍵認証により接続できる。パスワード認証・root ログインは無効(VirtualBox で確認済み)。agent は SSH 鍵を持たない
- 日本語入力: locale ja_JP.UTF-8 と keyboard jp の指定で、インストーラーが ibus-mozc・language-pack-ja・Noto CJK を入れ、agent の入力ソースは `[('xkb', 'jp'), ('ibus', 'mozc-jp')]` になる(VirtualBox で確認済み)。RDP 越しに Ctrl+Space で切り替えて日本語を打てる(VirtualBox + 101 キーボード + mstsc で確認済み)
- キーボード配列は env.yaml の `keyboard_layout` で決める(作業者の手元は 101 キーボード)。first-login が入力ソースを `[('xkb', <配列>), ('ibus', 'mozc-on')]` にし、切り替えに Ctrl+Space を足す。Mozc の ibus エンジンの配列は `default`(システムの配列に従う)
- インストーラーが入れる `mozc-jp` は、切り替えた直後が直接入力で、ひらがなにするには半角/全角キーが要る。101 キーボードでは切り替えはできても日本語を打てなかった。`mozc-on`(切り替えた時点でひらがな)にして打てた(確認済み)
- 動いている VM の配列を `localectl set-x11-keymap` で変えようとしたら、sudo でも "Access denied" になった。`/etc/default/keyboard` を直接書き換えて代えた(原因は未調査)
- Google Chrome は 75-chrome.sh が公式 apt リポジトリから入れ、agent の `~/.config/mimeapps.list` で既定のブラウザにする(VirtualBox で確認済み。156.0.8078.47)
  - Google のリポジトリには最新版しかないので固定しない。unattended-upgrades の許可元に `Google LLC:stable` を足して自動更新する(dry-run で許可元を確認済み)
  - パッケージは入ると自分用のリポジトリ定義 `google-chrome.sources`(接続先 `chrome-stable/deb`、署名鍵は `/usr/share/keyrings/google-chrome.gpg`)を作る。`/etc/default/google-chrome` の `repo_add_once="false"` でも止まらなかった。75-chrome.sh は導入用の定義を最初の導入にだけ使い、導入後に消す
  - 署名鍵の主鍵の fingerprint は EB4C1BFD4F042F6DDDCCEC917721F63BD38B4796

### ホームのフォルダー名(2026-10-24 追加)
- xdg-user-dirs はロケール ja_JP に合わせて「デスクトップ」などの日本語名で作る。80-agent-session.sh が英語名にし、`~/.config/user-dirs.dirs` と Files のブックマークも書き換える。ログイン時の「フォルダー名を更新しますか」(xdg-user-dirs-gtk-update)は agent の autostart で止める(VirtualBox で、日本語名から英語名への移行と冪等性を確認済み。新規インストールでも確認済み)

### 初期設定の見直し(2026-10-24 追加)
- autoinstall の LVM は既定(sizing-policy: scaled)だとボリュームグループの半分ほどしかルートに使わない(VirtualBox で 37GB 中 18.5GB。公式リファレンスで確認済み)。`sizing-policy: all` にした(新規インストールで、ルートがディスクのほぼ全部になることを確認済み)
- ネットワークは env.yaml の `network` から autoinstall の `network:`(netplan、renderer NetworkManager、`match: name: en*`)を作る(VirtualBox の新規インストールで、固定 IP がインストール後も NetworkManager で同じ設定になることを確認済み。実機の社内ネットワークでは未確認)
- 26.04 の時刻同期は chrony(systemd-timesyncd は入っていない)。同期先は `/etc/chrony/sources.d/*.sources`、DHCP で配られた NTP も使う。35-system.sh が `ntp_servers` を `agent-host.sources` に書く(VirtualBox で確認済み)
- agent の git 設定、GitHub CLI(リリースの .deb を SHA256 照合、2.103.2。apt リポジトリは最新版しか置かない)、build-essential 等、inotify の上限、apport の無効化、update-notifier の停止、`check-alive-timeout 0` を足した(動いている VM に反映して確認済み)
- 未確認: systemd-oomd がメモリ不足のときに Orca ごと止めることがある。実機で様子を見る
- SPEC.md §10 の対象外だが気付いた点: Orca の初回の案内で「Yolo モード」(確認なしでコマンド実行)が最初からオン。agent でログインしたアカウントのスキルが `~/.claude/skills/synced/` に同期される。どのアカウントでログインするかは決めておく

### Docker(2026-10-24 追加)
- 公式 apt リポジトリ(26.04 resolute 対応、過去の版も残る)から docker-ce 29.9.2 ほか 5 つ(合わせて 6 つ)を版指定で入れて hold する。署名鍵の fingerprint は 9DC858229FC7DD38854AE2D88D81803C0EBFCD88
- agent は rootless Docker。docker グループは実質 root になるので使わない(作業者の判断)。root のデーモンは止め、agent に linger を付けて `dockerd-rootless-setuptool.sh install` を agent で実行する。`DOCKER_HOST` は `~/.config/environment.d/60-docker.conf`
- Ubuntu 24.04 以降は特権のないユーザー名前空間を AppArmor で制限しているが、deb で入れた rootlesskit のプロファイルは apparmor パッケージに含まれる(Docker の公式文書)
- 26.04 で上の手順が通り、hello-world が動くことを VirtualBox の新規インストールで確認済み。1024 未満のポートを待ち受けられないなど rootless の制限がある

### 開発環境の追加(2026-10-24)
- agent に sudo がないので、エージェントが要る道具は構成で入れるか、mise(言語のバージョン)と rootless Docker(サービス)で済ませる。その事実を agent の `~/.claude/CLAUDE.md` と `~/.codex/AGENTS.md` に書いて置く
- 版を固定して足したもの: uv 0.13.5、mise 2026.10.18(どちらもリリースの tar を SHA256 照合)、CCManager 4.4.9(npm)、VS Code 1.143.1(Microsoft の apt、hold)、Zed 1.25.3(リリースの tar)。apt で足したもの: python3-dev、pkg-config、libssl-dev、fd-find、tree、htop、tmux、sqlite3、shellcheck、zip、wget、rsync、git-lfs、wl-clipboard、dnsutils、netcat-openbsd、libnss3-tools、neovim(選んだとき)
- env.yaml に足した項目: proxy、ca_certs、editors、agent_ssh_authorized_keys(agent は SFTP 専用)、dev_ports
- Orca: `ORCA_TELEMETRY_DISABLED=1` を agent の environment.d に置く。利用統計と「Update available」の通知は設定画面でもオフにする(手順書)。更新の確認の通信(1 日 1 回と 30 分ごとの nudge.json)は止める手段がない(v1.4.237 のソースで確認)
- Orca は MIT・開発が活発で、代替(Emdash、Nimbalyst、Superset、Warp など)より良い選択肢はなかった(2026-10-24 の調査)。予備の TUI として CCManager を入れた
- 未確認: プロキシと CA 証明書の実際の動作(VirtualBox ではプロキシなし。CA は試験用の自己署名で登録まで確認する)、(VS Code の debconf と、Zed の GPU なしでの動作は、のちに確認済み。下の節を参照)RDP のクリップボードでのファイルのコピー

### VirtualBox での確認(2026-10-24、入れ直しと feature/dev-env)
- 新規インストールで確認済み: sizing-policy: all(ルート 37GB、VG の空き 0)、env.yaml の network(固定 IP。インストーラーが /etc/netplan/00-installer-config.yaml に renderer NetworkManager で書き、NetworkManager の接続 netplan-lan になる)、英語のフォルダー名、gnome-initial-setup が出ない、us 配列 + mozc-on、rootless Docker の hello-world
- インストール中、ライブ環境の GDM が自動ログインせずログイン画面で止まったことがある。インストール自体は裏で進んでいた(Enter で入るとコピー中だった)。原因は未調査
- インストーラーは最後に ISO を取り出す。VirtualBox で入れ直すときは ISO を入れ直す
- first-login の "RDP server certificate is invalid" は、TLS の証明書を先に設定しても出る。最終的な状態は正常(原因は未調査)
- feature/dev-env を動いている VM に流して確認済み: 追加のエージェント(OpenCode、Copilot CLI、Antigravity CLI)、エディター(VS Code、Neovim、Zed)、mise、uv、pnpm、CCManager、SFTP 専用、試験用の CA 証明書の登録(システム、/etc/environment、agent の environment.d、Chrome の NSS)、Claude Code の hooks と Codex の notify(Orca が入れた hooks は残る)、2 回目の実行で設定が二重にならない
- VS Code は debconf の `code code/add-microsoft-repo boolean false` で、パッケージが自分のリポジトリ定義を足さなかった(確認済み)
- environment.d はファイル名の順に読まれ、`/usr/lib/environment.d/99-environment.conf`(= /etc/environment)が PATH を固定の値で上書きする。PATH を足すファイルは `995-` で始める(確認済み)
- Orca(Electron)は /proc/<pid>/environ が読めない(プロセス名の書き換えのため)。環境変数は `systemctl --user show-environment` で確かめる
- corepack は pnpm / yarn の初回に取得の確認を出すことがある。`COREPACK_ENABLE_DOWNLOAD_PROMPT=0` を agent の環境に入れた
- IP Messenger への通知は、VM(NAT)から Windows の IP Messenger(v5 系)に UTF-8・暗号化なし・NOADDLISTOPT で届き、日本語も文字化けしなかった(2026-10-24 確認済み)
- 未確認: Slack への実際の送信、プロキシの下での動作、Remote Control

### 最小化・最適化・使い勝手・移行(2026-10-24、VirtualBox で確認)
- 動いているシステムのサービスは 34 → 23、外から待ち受けるのは 22 と 3389 だけになった。agent の常駐から evolution、localsearch、Xwayland などが消えた
- kdump は `crashkernel=…,4G-32G:512M,32G-64G:1024M` で予約していた。消すと VM で約 500MB、32GB の機種では約 1GB 空く
- 電源のプロファイル performance は VM になく(power-saver / balanced だけ)、警告を出して進む。実機で確かめる
- rootless Docker は既定では gvisor-tap-vsock で中継していた。passt を入れて `DOCKERD_ROOTLESS_ROOTLESSKIT_NET=pasta` にし、コンテナから外を取得できた
- linger で agent の systemd が構成の途中(65)から動くため、そのあとに置いた environment.d を読まない。80-agent-session.sh で、agent がログインしていなければ user@ を再起動する(新規インストールのとき)
- Clipboard Indicator は `gnome-extensions enable` だと、Shell が拡張機能を知らないとき(構成の途中で置いたとき)に失敗する。`org.gnome.shell enabled-extensions` に足す形で有効になった
- VS Code のデスクトップファイルは `com.microsoft.VSCode.desktop`。Ctrl+Alt+T は `xdg-terminal-exec`(既定は Ptyxis)と `org.gnome.desktop.default-applications.terminal` を見る
- IP Messenger: VM(NAT)からホストの IP Messenger に BR_ENTRY を送ると ANSENTRY が返り、名前(ユーザー名・ホスト名・ニックネーム)で探して送れた。NAT はブロードキャストを外に出さないので、VM では `ipmsg_broadcast` にホストの IP を入れて試した。実機の LAN では既定の 255.255.255.255 で探す(未確認)
- 移行: 書き出し → 消す → 取り込みで、~/work と ~/.codex の中身が戻った(node_modules は除かれる)。sysadmin の sudo はパスワードが要り、標準入力を受け渡しに使うので、パスワードを標準入力の先頭の 1 行で `sudo -S` に渡す
- 端末: VirtualBox で 1 つ開いたときの PSS は Xfce Terminal 約 27MB、Alacritty 約 73MB、Ghostty 約 148MB(GPU なしのソフトウェア描画)。作業者が RDP で Xfce Terminal と Ghostty を試し、どちらも日本語入力・右クリックの貼り付け・選択でコピーが問題なかったので、軽い Xfce Terminal にした
- Caps Lock: RDP(mstsc)で手元とホストの状態がずれた。原因は未調査(gnome-remote-desktop 50 にはロックキーの同期の修正が入っている。IBus が先に受け取っている可能性)。caps:none で使わないことにした
- mstsc の色 32 ビットは遅いという報告(gnome-remote-desktop #333、同じ 26.04)があるので、.rdp のひな形は 24 ビットにした
- RDP の extend モード(仮想の画面を足し、大きさを手元に合わせる)は、VirtualBox(GPU なし)で仮想の画面を足した直後に GNOME Shell が signal 11 で異常終了した。採用せず mirror-primary のまま。実機での動作は未確認
- GNOME のセッションが落ちると、自動ログインは起動時の 1 回だけなのでログイン画面のままになり、再起動まで RDP に戻れない。TimedLogin は agent がログイン画面の一覧に出ないので効かなかった。見張りのタイマー(agent-host-session-watchdog、1 分ごと、2 回続けて seat0 にログインのセッションがなければ GDM を再起動)を置き、GNOME Shell をわざと落として約 1 分 20 秒で戻ることを確かめた

### 手順書の PDF(2026-10-24)
- 表紙、ヘッダー・フッター(版は日付と `git describe`)、色付きの囲み(注意・ヒント・確認)、どこで打つかのラベル付きのコマンドの枠、TikZ の図 4 つ、印を付けるチェックリストにした
- tcolorbox などが手元の TeX Live 2022 になかったため、`just guide` は docs/guide.Dockerfile(Ubuntu 26.04 の TeX Live 2025)のイメージを作り、その中で作る。イメージは約 1GB、初回の作成は数分
- tcolorbox の環境名 `check` は既にある命令とぶつかるので `confirm`、TikZ の style 名 `step` も既にあるキーなので `pstep` にした
- 表紙の絵は Gemini(gemini-3-pro-image)で作った docs/cover.jpg。作りなおすときは .env に GEMINI_API_KEY を書き、`python3 scripts/local/gen-cover.py build/cover.jpg 3` で候補を作って選ぶ。横長だと下半分が空き、縦長で「余白を空けて」と頼むと色の違う帯ができたので、「継ぎ目のない 1 枚の絵」と書いた。Gemini で作った絵には見えない透かし(SynthID)が入る

### Gitea(2026-10-24 追加、VirtualBox で確認)
- Gitea CLI の tea 0.16.0 をいつも入れる(dl.gitea.com の単体のバイナリを SHA256 で照合。/opt/tea-<版>/tea)。env.yaml の gitea_url を書くと、agent の environment.d に GITEA_SERVER_URL を置き(tea login add の既定の接続先)、エージェント向けの説明にも載せる
- 手元の Docker の Gitea 28.2.0 に VM から接続し、`tea login add --token … --git-credentials` → HTTPS の clone・push(tea が git の credential helper になる)→ `tea issues create` が通った
- トークンの権限は repository と issue の書き込み、user の読み取りで足りる。`tea repo create` だけは write:user が要った
- 社内の Gitea が社内の CA の証明書を使うときは、env.yaml の ca_certs に入れれば tea(Go)もシステムの証明書として信頼する(未確認)

### クラウドの CLI(2026-10-24 追加、VirtualBox で確認)
- env.yaml の clouds で AWS CLI v2(2.38.5)、Google Cloud CLI(590.0.1)、Azure CLI(2.91.0)を選んで入れる(63-clouds.sh)。3 つで約 1.8GB(/opt/aws-cli 275MB、/usr/lib/google-cloud-sdk 846MB、/opt/az 647MB)。初回の構成で約 6 分、2 回目は入れなおさない
- AWS CLI は SHA256 を配っていない。2.38.5 の zip の PGP 署名(.sig)を AWS CLI Team の鍵(FB5DB77FD5C118B80511ADA8A6310ACC4672475C)で確かめ、その zip の SHA256 を固定した。鍵はキーサーバーの写しでは 2026-07-07 で期限切れになっていたが、署名は Good だった。版を上げるときも同じ手順で確かめる
- Azure CLI は Microsoft の apt に 26.04(resolute)向けがある。鍵は VS Code と同じ
- agent の environment.d に AWS_PAGER=(出力を less に渡さない)、CLOUDSDK_CORE_DISABLE_USAGE_REPORTING、CLOUDSDK_COMPONENT_MANAGER_DISABLE_UPDATE_CHECK、AZURE_CORE_COLLECT_TELEMETRY=false を置く
- ログイン(SSO・ブラウザ)は試していない(実際のアカウントが要る)。未確認
- Terraform・OpenTofu・kubectl・Helm などはホストに入れず、エージェントが mise で入れる(エージェント向けの説明に書いた)

### VS Code の拡張機能(2026-10-24 追加、VirtualBox で確認)
- 72-editors.sh の先頭で ID を固定し、agent として `code --install-extension` で入れる。版は Marketplace の正式版(プレリリースでない)で、linux-x64 と VS Code 1.143 に合う最新を選んだ
- settings.json に extensions.autoUpdate / autoCheckUpdates = false と redhat.telemetry.enabled = false(YAML の拡張機能が初回に聞いてくる)を、足りないときだけ足す(JSON として読めないときは触らない)
- 容量: 3 つのクラウドを選んで 26 個・約 2.7GB。大きいのは Codex(openai.chatgpt)1.1GB、Cloud Code 300MB、Claude Code 290MB、Gemini Code Assist 240MB(Cloud Code が必ず一緒に入れる)
- Azure Tools(ms-vscode.vscode-node-azure-pack)は 12 個のまとめで Windows AI Studio や Jupyter まで入り約 600MB 増えたので、土台の Azure Resources だけにした
- 依存やまとめで入る拡張機能の版は固定できない(入れたときの最新)。外した拡張機能のフォルダーは VS Code を次に起動したときに消える
- Language Pack を入れて LANG が ja_JP.UTF-8 でも、表示は英語のままだった(VM の画面で確認)。「表示言語を構成する」と同じく ~/.vscode/argv.json に "locale": "ja" を書く。argv.json はコメント入りなので、locale がないときだけ { の次の行に足す
- Language Pack の最新は 1.131(VS Code 1.143 より古いが、engine は ^1.131.0 で使える。新しい画面の文言は英語のまま残りうる)

### Zed の拡張機能(2026-10-24 追加、VirtualBox で確認)
- Zed には拡張機能を版を指定して入れるコマンドがない。settings.json の auto_install_extensions に書くと、Zed を起動したときに最新が入る。入ったあとは auto_update_extensions を false にして更新を止める
- 設定は VS Code と同じく、足りない項目だけ足す(72-editors.sh の merge_agent_json。JSON として読めないときは触らない)
- VM(GPU なし、llvmpipe のソフトウェア描画)で Zed を閉じてから起動しなおすと、約 2 分で 10 個(terraform と env.yaml の biome を含む)が入った。動いている Zed に設定を足しても入らない(起動時に読む)。Zed は 1 つしか動かないので、`zed` を実行しても動いている Zed に引き渡されて終わる
- Ruff は Zed の Python に最初から入っているので、拡張機能としては入らない(一覧から外した)
- 画面の日本語化はできない。Zed には UI を翻訳する仕組みがない(要望 #7409 は 2026-08 時点で開いたまま。翻訳の仕組みの PR #52157・#54185・#60633・#62027 は取り込まれずに閉じた)
- 漢字の字形: agent の LANG が ja_JP.UTF-8 なので、既定のままで日本の字形(Noto Sans CJK JP)で出る。フォントを Noto Sans Mono CJK JP と SC に切り替えて VM の画面を見比べ、既定が JP と同じ形(「角」の縦線が突き抜けない、「骨」の上の向き)であることを確かめた。代わりのフォントの設定(buffer_font_fallbacks / ui_font_fallbacks)は macOS と Windows だけで、Linux では効かない
- 日本語入力(Mozc)を Zed で使えるかは未確認

### ホームディレクトリを NFS に(2026-10-24 検討、見送り)
- agent のホーム全体を NFS にはしない。NFS が見えないと自動ログインが失敗して停電からの自動復帰が崩れる、rootless Docker の置き場が NFS の上で動かない、Chrome・Claude・Codex・Orca の SQLite が NFS のロックで壊れうる、node_modules・worktree が遅く inotify が効かない、平文のキーリングやログインの情報が Kerberos(sec=krb5p)なしでは LAN に流れる、UID をそろえる必要がある、のため
- 要るようになったら、ホームはローカルのまま、env.yaml で指定した場所(例 ~/shared)だけを `x-systemd.automount,nofail` でマウントする形にする(未実装)

### 社外アクセスの VPN 方式
- 未着手。社内既定の方針に合わせる(SPEC.md §9)

## 注意点

- Codex のログインはデバイスコード認証(`codex login --device-auth`)。ChatGPT 側の設定で事前に有効化しておかないと、エラーにならず止まって見える
- Codex の認証情報は `~/.codex/auth.json` に平文で保存される。`agent` のホームの権限を絞る
- Orca は .deb 版なら自分では更新を適用しない(通知は出る)。apt-mark hold で固定している。上げるときは 70-orca.sh の版と SHA256 を直す
- バージョンを上げるときは、版を持つスクリプト(60-devtools.sh、62-agents.sh、63-clouds.sh、65-docker.sh、70-orca.sh、72-editors.sh、76-desktop.sh)の先頭の値を直し、手順書の付録「固定しているバージョン」も直して、`just update <ホスト>` で反映する
- build-usb.sh で作った ISO と、ターゲットの `/opt/agent-host/env.sh`(root のみ読める)には秘密情報が入る
- デスクトップ共有とリモートログインを両方有効にすると、デスクトップ共有が 3390 番に移る。リモートログインは有効にしない
- いちばん崩れやすいのは受け入れテスト4(再起動後、何もせずに RDP がつながるか)。ここを最優先で検証する
- リポジトリを Public にするときは、GitHub の secret scanning と push protection を有効にする。公開前に `git log --all --format='%ae %ce' | sort -u` を実行し、作成者のメールアドレスが noreply だけであることを確かめなおす。main と develop の強制 push と削除を禁止する保護も、そのときに入れる(Private のままでは今の契約で設定できない)
