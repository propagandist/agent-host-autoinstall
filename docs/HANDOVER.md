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

## 現状(2026-10-23)

- §9 を調査し(結果は下)、autoinstall.yaml・env.example.yaml・scripts/・docs/manual-steps.md・docs/acceptance-test.md を一通り作った
- shellcheck(0.11.0、Docker の ubuntu:26.04)は指摘なし
- **VirtualBox で一通り動いた(2026-10-23)。** ubuntu-26.04.1-desktop-amd64.iso から build-usb.sh で作った ISO で、確認画面なしにインストール → 初回起動の構成 → agent の自動ログイン → first-login → RDP の待ち受けまで、手を触れずに通った。再起動と強制電源オフ後も、何もせずに RDP の認証が通る(受け入れテスト 1・3・4 の範囲。結果は docs/acceptance-test.md)
  - 環境: Windows 10 + VirtualBox 7.2.6。Hyper-V(Docker Desktop)が有効なため VirtualBox は NEM モードで動き、CPU 2 つ以上ではゲストのカーネルが止まった。CPU 1・メモリ 4GB で試した(インストールに約 47 分)
  - RDP は FreeRDP の `/auth-only /sec:nla` で認証が通ることだけを確かめた(間違ったパスワードは LOGON_FAILURE で拒否)。画面の操作と、切断・再接続(受け入れテスト 6)は未確認
- 実装の都合で SPEC.md から変えた点: post-install は late-commands の中ではなく、初回起動時の `agent-host-provision.service` が実行する(インストール中の chroot では ufw などが動かないため)。SPEC.md §5.2 に反映済み

## 次にやること(この順で)

1. VirtualBox の VM に RDP クライアント(mstsc など)で入り、画面の操作、Claude Code / Codex のログインとタスク実行、切断・再接続(受け入れテスト 2・5・6)を確かめる
2. 実機で受け入れテスト(SPEC.md §7、docs/acceptance-test.md)。特にダミープラグでの RDP と、lan_cidrs の外からの到達(テスト 7)
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
- 日本語入力: locale ja_JP.UTF-8 と keyboard jp の指定で、インストーラーが ibus-mozc・language-pack-ja・Noto CJK を入れ、agent の入力ソースは `[('xkb', 'jp'), ('ibus', 'mozc-jp')]` になる(VirtualBox で確認済み)。**未確認: RDP 越しに半角/全角キーなどで切り替えて日本語を打てるか**
- Google Chrome は 75-chrome.sh が公式 apt リポジトリから入れ、agent の `~/.config/mimeapps.list` で既定のブラウザにする(VirtualBox で確認済み。156.0.8078.47)
  - Google のリポジトリには最新版しかないので固定しない。unattended-upgrades の許可元に `Google LLC:stable` を足して自動更新する(dry-run で許可元を確認済み)
  - パッケージは入ると自分用のリポジトリ定義 `google-chrome.sources`(接続先 `chrome-stable/deb`、署名鍵は `/usr/share/keyrings/google-chrome.gpg`)を作る。`/etc/default/google-chrome` の `repo_add_once="false"` でも止まらなかった。75-chrome.sh は導入用の定義を最初の導入にだけ使い、導入後に消す
  - 署名鍵の主鍵の fingerprint は EB4C1BFD4F042F6DDDCCEC917721F63BD38B4796

### 社外アクセスの VPN 方式
- 未着手。社内既定の方針に合わせる(SPEC.md §9)

## 注意点

- Codex のログインはデバイスコード認証(`codex login --device-auth`)。ChatGPT 側の設定で事前に有効化しておかないと、エラーにならず止まって見える
- Codex の認証情報は `~/.codex/auth.json` に平文で保存される。`agent` のホームの権限を絞る
- Orca は .deb 版なら自分では更新を適用しない(通知は出る)。apt-mark hold で固定している。上げるときは 70-orca.sh の版と SHA256 を直す
- バージョンを上げるときは 60-devtools.sh / 70-orca.sh の先頭の値を直し、`sudo /opt/agent-host/provision.sh` を再実行する
- build-usb.sh で作った ISO と、ターゲットの `/opt/agent-host/env.sh`(root のみ読める)には秘密情報が入る
- デスクトップ共有とリモートログインを両方有効にすると、デスクトップ共有が 3390 番に移る。リモートログインは有効にしない
- いちばん崩れやすいのは受け入れテスト4(再起動後、何もせずに RDP がつながるか)。ここを最優先で検証する
- リポジトリを Public にするときは、GitHub の secret scanning と push protection を有効にする。公開前に `git log --all --format='%ae %ce' | sort -u` を実行し、作成者のメールアドレスが noreply だけであることを確かめなおす
