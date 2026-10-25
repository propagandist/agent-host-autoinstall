# 技術メモ

このリポジトリを作るときに調べたこと・確かめたことの記録。仕様は [SPEC.md](SPEC.md)、手順は [manual-steps.md](manual-steps.md) と手順書(setup-guide.tex)にある。
版を上げるときや、挙動が想定と違うときに、ここで理由と確かめた範囲を見る。

## 検証した環境

- VirtualBox 7.2.6 の VM(UEFI、メモリ 4GB)。ホストは Windows 10 で、Hyper-V(Docker Desktop)と共存させたため VirtualBox は NEM モードで動き、CPU 2 つ以上ではゲストのカーネルが止まった。そのため CPU 1 で試した
- ISO は ubuntu-26.04.1-desktop-amd64.iso から build-usb.sh で作った。USB からの起動から構成の完了まで約 47〜67 分、再起動から RDP の待ち受けまで約 80 秒
- RDP は Windows のリモート デスクトップ接続(mstsc)と FreeRDP で確かめた。キーボードは 101(英字配列)
- shellcheck は 0.11.0(Docker の ubuntu:26.04)で指摘なし
- v0.2.0 から、`just test`(Docker の中の試験)、`just verify`(ホストの 100 項目あまり)、`just verify-rdp`、`just vm-test`(VirtualBox で入れなおしからの通し)で機械的に確かめている
- 実機ではまだ確かめていない(下の「確認できていないこと」)

## 設計で決めたこと

1. 物理 PC への Ubuntu の自動構成は、公式の autoinstall を使う。Server 専用ではなく Desktop でも使える
2. 常時稼働させたいが、AI エージェントを動かすためにデスクトップが必要 → Desktop 版に常時稼働の設定を足す
3. エージェントの作業環境は Orca(stablyai/orca。Claude Code や Codex を git worktree ごとに並列実行する ADE)。Codex も併用する
4. 遠隔操作は xrdp ではなく、GNOME 標準の「デスクトップ共有」(RDP)にする
   - xrdp やリモートログインは別セッションを作るため、再起動後に誰かがログインするまで Orca が起動しない(主な理由)
   - Ubuntu の GNOME のセッションは 25.10 から Wayland だけ(上流の mutter が 49 で X11 を既定で無効にし、50 で削除)。xrdp は Xorg のセッションを作るので、GNOME を動かせない。xrdp・xorgxrdp と、Xfce などの X11 のセッションは 26.04 にもある(Ubuntu 26.04 のリリースノート「Other desktop sessions, such as KDE on X11, Xfce, ... can still be launched using an X.org session」。2026-10-25 に確認)
   - デスクトップ共有は物理セッションを共有するので、自動ログイン + Orca 自動起動と両立する
5. 自動ログインではキーリングが開かず、デスクトップ共有の認証情報が読めない → `agent` ユーザーのキーリングを空パスワードにする(1 人で使う専用ユーザーで、置く秘密はその人の各サービスのログインだけ、が前提)
6. post-install は late-commands の中ではなく、初回起動時の `agent-host-provision.service` が実行する(インストール中の chroot では ufw などが動かないため)
7. 1 台は 1 人で使う。複数の人が同じセッション(agent)に入ると、Claude Code・Codex のログインが 1 つになり、ひとりのサブスクリプション(個人の契約)を全員で使うことになる。`CLAUDE_CONFIG_DIR` などで分けても、同じセッションに入れる人は誰の認証情報でも使えるので、分けたことにならない。複数の人で使うときはホストを人数分にする

詳細は SPEC.md §8 を参照。

## 調査と検証の記録

SPEC.md §9 の未確定事項から始めた調査と、機能を足したときに確かめたこと。見出しの日付は調べた日

確度: 確認済み = 公式文書かソースで確かめた / 推定 = 記述から導いた / 未確認 = 実機で試していない、または一次情報がない

### 26.04 Desktop の autoinstall
- Desktop 23.04 以降は autoinstall に公式対応(確認済み)。GUI(ubuntu-desktop-provision)が subiquity を呼ぶ構成
- 設定は ISO 直下の `/autoinstall.yaml` を `/cdrom/autoinstall.yaml` として読む(確認済み、subiquity のソース)。dd で書いた USB には後から足せないので、build-usb.sh は xorriso で ISO を作り直す
- 確認画面を出さないにはカーネル引数 `autoinstall` が要る(確認済み)。build-usb.sh が grub.cfg の linux 行に足す
- Desktop ISO には openssh-server が入っていない(確認済み)。インストール中にネットワークが要る
- identity は Desktop では省略できるが、ここでは sysadmin を作るために使う(確認済み)。`admin` は予約名で使えない(VirtualBox で確認済み: "Username is reserved by the system")
- 既定のカーネルは Desktop では hwe(確認済み)
- GDM の自動ログイン設定は 26.04(gdm3 50.x)でも `/etc/gdm3/custom.conf` の `[daemon]`(確認済み、ソース)。PreSession などのスクリプトは 26.04 で廃止
- 26.04 は GNOME 50。GNOME のセッションは Wayland のみ(25.10 から。確認済み、リリースノート)
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
- キーボード配列は env.yaml の `keyboard_layout` で決める(検証は 101 キーボードで行った)。first-login が入力ソースを `[('xkb', <配列>), ('ibus', 'mozc-on')]` にし、切り替えに Ctrl+Space を足す。Mozc の ibus エンジンの配列は `default`(システムの配列に従う)
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
- ネットワークは env.yaml の `network` から autoinstall の `network:`(netplan、renderer NetworkManager、`match: name: en*`)を作る(VirtualBox の新規インストールで、固定 IP がインストール後も NetworkManager で同じ設定になることを確認済み。実機の LAN では未確認)
- 26.04 の時刻同期は chrony(systemd-timesyncd は入っていない)。同期先は `/etc/chrony/sources.d/*.sources`、DHCP で配られた NTP も使う。35-system.sh が `ntp_servers` を `agent-host.sources` に書く(VirtualBox で確認済み)
- agent の git 設定、GitHub CLI(リリースの .deb を SHA256 照合、2.103.2。apt リポジトリは最新版しか置かない)、build-essential 等、inotify の上限、apport の無効化、update-notifier の停止、`check-alive-timeout 0` を足した(動いている VM に反映して確認済み)
- 未確認: systemd-oomd がメモリ不足のときに Orca ごと止めることがある。実機で様子を見る
- SPEC.md §10 の対象外だが気付いた点: Orca の初回の案内で「Yolo モード」(確認なしでコマンド実行)が最初からオン。agent でログインしたアカウントのスキルが `~/.claude/skills/synced/` に同期される。どのアカウントでログインするかは決めておく

### Docker(2026-10-24 追加)
- 公式 apt リポジトリ(26.04 resolute 対応、過去の版も残る)から docker-ce 29.9.2 ほか 5 つ(合わせて 6 つ)を版指定で入れて hold する。署名鍵の fingerprint は 9DC858229FC7DD38854AE2D88D81803C0EBFCD88
- agent は rootless Docker。docker グループは実質 root になるので使わない。root のデーモンは止め、agent に linger を付けて `dockerd-rootless-setuptool.sh install` を agent で実行する。`DOCKER_HOST` は `~/.config/environment.d/60-docker.conf`
- Ubuntu 24.04 以降は特権のないユーザー名前空間を AppArmor で制限しているが、deb で入れた rootlesskit のプロファイルは apparmor パッケージに含まれる(Docker の公式文書)
- 26.04 で上の手順が通り、hello-world が動くことを VirtualBox の新規インストールで確認済み。1024 未満のポートを待ち受けられないなど rootless の制限がある

### 専用の PC を置く理由(2026-10-25 の調査)

エージェントをどこで動かすかを比べた。各社の文書は 2026-10-25 に読んだもの。

- **手元の PC**: エージェントの CLI は手元で動くので、閉じる・スリープ・再起動で止まる。確認なしで動かすと、私的なファイルや個人のログイン情報(SSH の鍵、ブラウザのログイン、パスワードの管理ソフトなど)と同じ環境で動くことになる
- **Claude Code の cloud sessions**(code.claude.com/docs/en/claude-code-on-the-web): Anthropic が管理する隔離された VM で動き、手元を閉じても続く。Pro・Max・Team と一部の Enterprise で使え、利用の上限はほかの Claude の利用と共有。リポジトリの clone と PR の作成は GitHub が要る(Team・Enterprise は GitHub Enterprise Server も)。GitLab などは手元から送れるが、そのリモートには push で戻せない。ネットワークは既定で制限され、許可した先にだけ届く。組織が自前の実行環境(self-hosted environment)を用意すれば、そちらで動かせる。使わない時間が続くと VM が片付けられ、動いていたコマンドは戻らない。組織が IP の許可リストを使っていると失敗する
- **Codex cloud**(learn.chatgpt.com/docs/cloud): 作業ごとに作業場所があり、手元が眠っていても続く。手順は GitHub のリポジトリを選ぶところから始まる。インターネットへの接続は環境ごとに設定する。どのプランで使えるか、時間の上限、LAN の中に届くかは、読んだ範囲では書かれていなかった
- **クラウドの VM**: Orca は SSH の先や VPS でも動く(Orca の文書の Ways to run)。費用は比べていない。LAN の資源には VPN が要る。このリポジトリの autoinstall は物理の PC に USB から入れる前提で、クラウドの VM のイメージでは試していない
- **Orca の想定**(Orca の文書の Remote Orca Servers、v1.4.237 のソースの docs): Remote Orca Server では、作業する側がプロジェクト・worktree・端末・タブ・エージェントのアカウントとセッションを持ち、クライアントは画面になる。クライアントのノート PC が眠っても、つながりが切れても、エージェントは動き続ける。ログインは作業する側で行い、ノート PC のログインは引き継がれない。Remote Orca Servers はベータで、Tailscale か信頼できる LAN の中で使うことを勧めている。画面のない Linux では `orca-ide serve` で同じことができる
- この構成は、その「作業する側」を、OS の自動ログイン・キーリング・RDP・セッションの見張り・UPS まで含めて人手なしで保つもの。画面のない `orca serve` ではなくデスクトップと RDP にしたのは、ログインにブラウザが要るため(Claude Code は Chrome でログインした。受け入れテスト 2)、手元に何も入れずに Windows のリモート デスクトップ接続でつなげるため、人が同じデスクトップで手を入れられるため
- 未確認: このホストの Orca を Remote Orca Server として公開し、手元の Orca からつなぐこと(LAN なら env.yaml の dev_ports に 6768 を足すことになるはず)

### Orca を選んだ理由(2026-10-24 の調査)

この用途で要る条件は次のとおり。Linux で動く(できれば .deb)、Claude Code と Codex を同じ画面で使える、エージェントごとに git の worktree を分けて並べられる、OSS、アカウントなしで使える、自分では更新を適用しない(版を固定できる)、利用統計を止められる、sudo のない agent で動く、RDP(Wayland)の画面で使える、開発が続いている。

- **Orca**(stablyai/orca、MIT): 条件をすべて満たした。.deb 版は自分では更新を適用せず、通知と apt のコマンドを出すだけ(公式の文書)。利用統計(PostHog)は既定でオンだが、設定と `ORCA_TELEMETRY_DISABLED=1` で止まる。対応エージェントは Claude Code・Codex・OpenCode・Copilot ほか端末で動くもの。SSH の worktree とヘッドレスの `orca serve`、スマホのアプリ(Orca Mobile)もある。調べた時点で、GitHub のスターは約 10 万、直近 1 週間にデスクトップ版のリリースが 7 本と、候補の中でもっとも活発だった。VirtualBox の RDP の画面で、Wayland ネイティブで動くことを確かめた
- **Emdash**(Apache-2.0): いちばん近い。Linux の .deb、Claude Code と Codex、worktree、SSH に対応し、利用統計も止められる。ただし更新の確認が 1 時間ごとで、止める設定がソースに見当たらず、Orca より良くなる点がなかった
- **Nimbalyst**(MIT。Crystal の後継): Linux の .deb、Claude Code と Codex、worktree に対応し、利用統計も止められる。更新の確認と通知を止められるかは確かめられず、Orca より良くなる点が見当たらなかった
- **Superset**: Elastic License 2.0(ソースは公開されているが OSS ではない)。Linux は AppImage だけで実験的の扱い。更新の確認(4 時間ごと)を止める `DISABLE_UPDATE_CHECK` は macOS でしか効かない(ソース)。利用統計の止め方の文書がない
- **Warp**: 無料のプランでは、利用統計を止めると AI の機能が使えない。.deb を入れると apt のリポジトリが登録され、自動で更新される
- **Conductor**: Mac だけ
- **Crystal**、**Vibe Kanban**: 開発が終わっている(Crystal は 2026-02、Vibe Kanban は運営が 2026-04 に終了を発表)
- **Sculptor**: Codex への対応が明記されていない
- **Zed**: エディターとして選べるようにした(env.yaml の editors)。エージェントの並列(Parallel Agents)もあるが、作業の中心にするには、調べた時点で GPU のない RDP での描画が未確認だった(のちに VM で動くことは確かめた)
- **TUI(Claude Squad、CCManager、Agent of Empires)**: 端末だけで使えるのは強み。ただ、エージェントの作業を並べて見比べるには GUI のほうが向くので、主にはしない。GUI が落ちたときや RDP がつながらないときの予備に、MIT で tmux が要らず npm で版を固定できる CCManager を入れた(Claude Squad は AGPL-3.0 で tmux が要る)
- Orca の弱点: 更新の確認の通信(1 日 1 回と 30 分ごとの nudge.json)は止められない(v1.4.237 のソース)。.deb 版は自分で更新しないので、出るのは通知だけ。確認なしでコマンドを実行する「Yolo モード」が最初からオン(README の「利用上の注意」)
- 出典: github.com/stablyai/orca、onorca.dev/docs(install・telemetry・settings)、github.com/generalaction/emdash、github.com/Nimbalyst/nimbalyst、github.com/superset-sh/superset、docs.warp.dev、conductor.build/docs、vibekanban.com/shutdown、github.com/kbwo/ccmanager、github.com/smtg-ai/claude-squad

### 開発環境の追加(2026-10-24)
- agent に sudo がないので、エージェントが要る道具は構成で入れるか、mise(言語のバージョン)と rootless Docker(サービス)で済ませる。その事実を agent の `~/.claude/CLAUDE.md` と `~/.codex/AGENTS.md` に書いて置く
- 版を固定して足したもの: uv 0.13.5、mise 2026.10.18(どちらもリリースの tar を SHA256 照合)、CCManager 4.4.9(npm)、VS Code 1.143.1(Microsoft の apt、hold)、Zed 1.25.3(リリースの tar)。apt で足したもの: python3-dev、pkg-config、libssl-dev、fd-find、tree、htop、tmux、sqlite3、shellcheck、zip、wget、rsync、git-lfs、wl-clipboard、dnsutils、netcat-openbsd、libnss3-tools、neovim(選んだとき)
- env.yaml に足した項目: proxy、ca_certs、editors、agent_ssh_authorized_keys(agent は SFTP 専用)、dev_ports
- Orca: `ORCA_TELEMETRY_DISABLED=1` を agent の environment.d に置く。利用統計と「Update available」の通知は設定画面でもオフにする(手順書)。更新の確認の通信(1 日 1 回と 30 分ごとの nudge.json)は止める手段がない(v1.4.237 のソースで確認)
- Orca は MIT・開発が活発で、代替(Emdash、Nimbalyst、Superset、Warp など)より良い選択肢はなかった(2026-10-24 の調査。下の「Orca を選んだ理由」)。予備の TUI として CCManager を入れた
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

### 新規インストールでの確認(2026-10-24)
- release/0.1.0 の ISO での入れなおしでは、インストーラーが日本語のフォント(fonts-noto-cjk)だけを入れ、ibus-mozc・mozc-utils-gui・language-pack-ja・language-pack-gnome-ja が入らず、日本語を打てなかった(前の入れなおしでは入っていた。インストーラーの言語サポートの導入は当てにならない)。76-desktop.sh で明示的に入れるようにした
- VS Code は Language Pack と argv.json の locale があっても、最初の起動だけ英語になった。Language Pack の一覧 ~/.config/Code/languagepacks.json を VS Code が最初の起動の途中で作り、表示言語はそれより前に決まるため。72-editors.sh が同じ形の一覧を先に作る(hash は UUID と版をつなげた MD5。VS Code が作ったものと一致を確認)。VS Code を手で起動して確かめるときは、DISPLAY=:0 と XAUTHORITY(/run/user/<uid>/.mutter-Xwaylandauth.*)が要る(X11 で動くため)
- 入れた直後に just update すると、unattended-upgrades が dpkg のロックを握っていて、構成が "Could not get lock /var/lib/dpkg/lock-frontend" で止まった。provision.sh が /etc/apt/apt.conf.d/90-agent-host-lock-timeout に DPkg::Lock::Timeout "1800" を置き、ロックが空くまで待つようにした
- すべての修正を含めた ISO で VM に新しく入れなおし、ルートがディスクのほぼ全部、固定 IP、英語のフォルダー名、初回の案内が出ない、TLS、us + mozc-on、caps:none、Clipboard Indicator、Xfce Terminal、追加のエージェントとエディター、rootless Docker を確かめた
- 構成の途中で mask したサービス(cups.path など)と syslog.socket が failed のまま残っていた。36-minimize.sh で reset-failed し、syslog.socket も止めるようにした

### 最小化・最適化・使い勝手・移行(2026-10-24、VirtualBox で確認)
- 動いているシステムのサービスは 34 → 23、外から待ち受けるのは 22 と 3389 だけになった。agent の常駐から evolution、localsearch、Xwayland などが消えた
- kdump は `crashkernel=…,4G-32G:512M,32G-64G:1024M` で予約していた。消すと VM で約 500MB、32GB の機種では約 1GB 空く
- 電源のプロファイル performance は VM になく(power-saver / balanced だけ)、警告を出して進む。実機で確かめる
- rootless Docker は既定では gvisor-tap-vsock で中継していた。passt を入れて `DOCKERD_ROOTLESS_ROOTLESSKIT_NET=pasta` にし、コンテナから外を取得できた
- linger で agent の systemd が構成の途中(65)から動くため、そのあとに置いた environment.d を読まない。80-agent-session.sh で、agent がログインしていなければ user@ を再起動する(新規インストールのとき)
- Clipboard Indicator は `gnome-extensions enable` だと、Shell が拡張機能を知らないとき(構成の途中で置いたとき)に失敗する。`org.gnome.shell enabled-extensions` に足す形で有効になった
- VS Code のデスクトップファイルは `com.microsoft.VSCode.desktop`。Ctrl+Alt+T は `xdg-terminal-exec`(既定は Ptyxis)と `org.gnome.desktop.default-applications.terminal` を見る
- IP Messenger: VM(NAT)からホストの IP Messenger に BR_ENTRY を送ると ANSENTRY が返り、名前(ユーザー名・ホスト名・ニックネーム)で探して送れた。NAT はブロードキャストを外に出さないので、VM では `ipmsg_broadcast` にホストの IP を入れて試した。実機の LAN では既定の 255.255.255.255 で探す(未確認)
- 移行: 書き出し → 消す → 取り込みで、~/work と ~/.codex の中身が戻った(node_modules は除かれる。2026-10-25 に、名前だけでの除外をやめ、~/work の中で見つけた node_modules・__pycache__・.venv のパスだけを除く形にした。tests/test_backup.py)。sysadmin の sudo はパスワードが要り、標準入力を受け渡しに使うので、パスワードを標準入力の先頭の 1 行で `sudo -S` に渡す
- 端末: VirtualBox で 1 つ開いたときの PSS は Xfce Terminal 約 27MB、Alacritty 約 73MB、Ghostty 約 148MB(GPU なしのソフトウェア描画)。RDP で Xfce Terminal と Ghostty を試し、どちらも日本語入力・右クリックの貼り付け・選択でコピーが問題なかったので、軽い Xfce Terminal にした
- Caps Lock: RDP(mstsc)で手元とホストの状態がずれた。原因は未調査(gnome-remote-desktop 50 にはロックキーの同期の修正が入っている。IBus が先に受け取っている可能性)。caps:none で使わないことにした
- mstsc の色 32 ビットは遅いという報告(gnome-remote-desktop #333、同じ 26.04)があるので、.rdp のひな形は 24 ビットにした
- RDP の extend モード(仮想の画面を足し、大きさを手元に合わせる)は、VirtualBox(GPU なし)で仮想の画面を足した直後に GNOME Shell が signal 11 で異常終了した。採用せず mirror-primary のまま。実機での動作は未確認
- GNOME のセッションが落ちると、自動ログインは起動時の 1 回だけなのでログイン画面のままになり、再起動まで RDP に戻れない。TimedLogin は agent がログイン画面の一覧に出ないので効かなかった。見張りのタイマー(agent-host-session-watchdog、1 分ごと、2 回続けて seat0 にログインのセッションがなければ GDM を再起動)を置き、GNOME Shell をわざと落として約 1 分 20 秒で戻ることを確かめた

### 手順書の PDF(2026-10-24)
- 表紙、ヘッダー・フッター(版は日付と `git describe`)、色付きの囲み(注意・ヒント・確認)、どこで打つかのラベル付きのコマンドの枠、TikZ の図 4 つ、印を付けるチェックリストにした
- tcolorbox などが古い TeX Live(2022)にないため、`just guide` は docs/guide.Dockerfile(Ubuntu 26.04 の TeX Live 2025)のイメージを作り、その中で作る。イメージは約 1GB、初回の作成は数分
- tcolorbox の環境名 `check` は既にある命令とぶつかるので `confirm`、TikZ の style 名 `step` も既にあるキーなので `pstep` にした
- 表紙の絵は Gemini(gemini-3-pro-image)で作った docs/cover.jpg。作りなおすときは .env に GEMINI_API_KEY を書き、`python3 scripts/local/gen-cover.py build/cover.jpg 3` で候補を作って選ぶ。横長だと下半分が空き、縦長で「余白を空けて」と頼むと色の違う帯ができたので、「継ぎ目のない 1 枚の絵」と書いた。Gemini で作った絵には見えない透かし(SynthID)が入る

### Gitea(2026-10-24 追加、VirtualBox で確認)
- Gitea CLI の tea 0.16.0 をいつも入れる(dl.gitea.com の単体のバイナリを SHA256 で照合。/opt/tea-<版>/tea)。env.yaml の gitea_url を書くと、agent の environment.d に GITEA_SERVER_URL を置き(tea login add の既定の接続先)、エージェント向けの説明にも載せる
- Docker で立てた Gitea 28.2.0 に VM から接続し、`tea login add --token … --git-credentials` → HTTPS の clone・push(tea が git の credential helper になる)→ `tea issues create` が通った
- トークンの権限は repository と issue の書き込み、user の読み取りで足りる。`tea repo create` だけは write:user が要った
- Gitea が独自の CA の証明書を使うときは、env.yaml の ca_certs に入れれば tea(Go)もシステムの証明書として信頼する(未確認)

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

### 使わないパッケージの削除(2026-10-24 追加、VirtualBox で確認)
- 36-minimize.sh で、snapd(残っていた snap 8 個も消える)と firefox(snap を入れるための中身のないパッケージ)を消し、/etc/apt/preferences.d/agent-host-no-snapd.pref で apt からも入らないようにした。ディスクが約 2GB 空き、snap のループデバイスと snapd の常駐(約 30MB)がなくなった
- 画面の読み上げ(orca・speech-dispatcher・espeak)と点字(brltty)を消した。読み上げの orca は /usr/bin/orca で、端末で `orca` と打つと Orca(orca-ide)ではなく読み上げが起動していた
- 印刷のドライバー(hplip・printer-driver-*)、sssd、openvpn・pptp・ppp・ModemManager、bluez、ibus-table(中国語)、whoopsie・apport・ubuntu-report・ubuntu-insights を消した。合わせて 47 個(パッケージは 1647 → 1591)
- 消せないもの: cups 本体は ubuntu-desktop-minimal の必須(消すとまとめが外れる)。whoopsie-preferences と apport-symptoms は、報告のパッケージと一緒に消すと gdm3・gnome-shell まで外れた。どちらも止めるだけにした。消す前に apt-get -s で、デスクトップを巻き込まないことを確かめてから消す
- 残したもの: 機器のファームウェア(実機で要るかもしれない)、1 つ前のカーネル、日本語のフォント
- 消したあとに再起動し、約 1 分で自動ログインと RDP の待ち受けまで戻った。失敗した unit はなかった

### 構成リポジトリに合わせた道具の変更(2026-10-24 追加、VirtualBox で確認)
- env.yaml を複数のファイルで重ねられるようにした(render-autoinstall.py。後のファイルが勝ち、辞書はキーごと、並びと値は置き換え)。知らないキーと、SOPS で暗号化されたままのファイルはエラーにする
- Docker の中から見えるのはこのリポジトリだけなので、scripts/local/envs.sh が env.yaml を build/ の下の実行ごとの一時ディレクトリ(build/.run.XXXXXX)に写してから渡し、終わったら消す(固定の名前を共有すると、並行に動かしたときに別のホストの env.yaml が混ざった。Issue #9)。相対パスは just を呼んだディレクトリ(invocation_directory)から見る。ISO も build/ に作ってから出力先に移す
- 置いた版を /opt/agent-host/BUILD-INFO(道具の git describe、AGENT_HOST_CONFIG_REV、env のファイル名、日時)に、構成が最後まで成功した版を /var/lib/agent-host/BUILD-INFO.ok に残し、just status に出す(#10)。just facts で台帳のための YAML(機種、シリアル、MAC、ディスク、メモリ、OS、ホスト鍵と RDP の証明書の指紋)を出す
- just update のホスト名の確認は、重ねた結果の env.sh の AH_HOSTNAME で行う
- 確かめたこと: リポジトリの外の common.yaml + hosts/x.yaml で check-env・iso・update が通る。書き間違い・暗号化のまま・hostname がないときは止まる。別のホストの env.yaml では update が止まる。examples/fleet をコピーし、sops 3.13.3 と age 1.3.2 で common.yaml の秘密情報を暗号化した構成リポジトリから、just check・update・status・facts が通り、復号したファイルが残らない
- 手順は docs/fleet.md、ひな形は examples/fleet/

### 機械的な検証(2026-10-24 追加、VirtualBox で確認)

- `just verify` は `scripts/verify.sh` を SSH で流し、sudo で読むだけの検査をする。固定の版は、ホストの `/opt/agent-host/post-install/*.sh` の `NAME=値` と `NAME=( ... )` を読んで比べる(版を二重に持たない)。動いている VM で 106 項目が通り、gh の hold を外す・画面のロックを有効にすると、その 2 項目が ✗ になり終了コード 1 になった
- `apt-mark showhold | grep -qx` は `set -o pipefail` のもとで、grep が先に終わると apt-mark が SIGPIPE になり、hold されていても失敗と判定した。一覧を変数に取ってから探す
- agent のセッションの gsettings と `grdctl status` は、root から `runuser -u agent` に `XDG_RUNTIME_DIR` と `DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/<uid>/bus` を渡すと読める。`grdctl status` は `Unit status`・`Status`・`Port`・`View-only`・`Negotiate port`・`Username: (hidden)` の行で判定する
- IBus はセッションのバスではなく、`~/.config/ibus/bus/<machine-id>-unix-wayland-0` に書かれた `IBUS_ADDRESS` で話す。そのファイルを読み込んで `ibus list-engine` すると `mozc-on`・`mozc-off`・`mozc-jp` が出る
- FreeRDP 3(Ubuntu 26.04 の freerdp3-x11)の `+auth-only` は、画面なしで NLA の認証だけをする。成功すると「Authentication only, exit status 1」を出して終了コード 0、パスワードが違うと終了コード 134、つながらないと「exit status 0」で終了コード 141 だった。`just verify-rdp` は終了コード 0 とこの行の両方で判定する。Docker の中からは、手元の PC の 127.0.0.1 を `host.docker.internal` で見る
- `just test` の stage.sh の試験(ファイルの権限)は Windows の python では通らないので、Linux(Docker)で動かす(in-ubuntu.sh の `<要るコマンド>` を `-` にすると、手元に python3 があっても Linux で動かす)

### ホームディレクトリを NFS に(2026-10-24 検討、見送り)
- agent のホーム全体を NFS にはしない。NFS が見えないと自動ログインが失敗して停電からの自動復帰が崩れる、rootless Docker の置き場が NFS の上で動かない、Chrome・Claude・Codex・Orca の SQLite が NFS のロックで壊れうる、node_modules・worktree が遅く inotify が効かない、平文のキーリングやログインの情報が Kerberos(sec=krb5p)なしでは LAN に流れる、UID をそろえる必要がある、のため
- 要るようになったら、ホームはローカルのまま、env.yaml で指定した場所(例 ~/shared)だけを `x-systemd.automount,nofail` でマウントする形にする(未実装)

### GPU による RDP の画面の符号化(2026-10-24 調査)

- gnome-remote-desktop 50.2(Ubuntu 26.04)は libva と libvulkan にリンクしていて、RDP のクライアントが AVC(H.264)に対応していれば、Vulkan で色を変換し VA-API で H.264 を作る経路を、設定なしで試す(50.2 のソース `grd-rdp-renderer.c`・`grd-hwaccel-vaapi.c`。VA-API の `VAProfileH264High` に `VAEntrypointEncSlice` か `EncSliceLP` が要る)。成功すると `[HWAccel.VAAPI] Successfully initialized VAAPI ... vendor: ...` を記録する。NVIDIA は CUDA と NVENC の別の経路(`grd-hwaccel-nvidia.c`)で、成功の記録は出ない
- Intel の VA-API は、Ubuntu に free 版(`intel-media-va-driver`、universe。`ENABLE_NONFREE_KERNELS=OFF`)と full 版(`intel-media-va-driver-non-free`、multiverse)がある。Intel の media-driver の README の表では、free 版は Broadwell で H.264 を符号化できず、Skylake〜Ice Lake は低電力の符号化(VDEnc。HuC のファームウェアが要る)だけ。パフォーマンスを優先して full 版にした(37-gpu.sh)。multiverse が無ければ free 版に戻す
- AMD の VA-API(radeonsi)は 26.04 では `mesa-libgallium` に入っている(`mesa-va-drivers` は無くなり、`mesa-libgallium` が Provides する)。Vulkan は `mesa-vulkan-drivers`(libvulkan1 の Recommends)。Ubuntu の Mesa で radeonsi の H.264 の符号化が有効かは未確認
- NVIDIA は、autoinstall の `drivers: install: true` で、インストールの中で ubuntu-drivers が推奨のドライバーを入れる(初回の起動からそのドライバーで動く。構成の途中で再起動しなくてよい)。Intel・AMD・VM では何も入らないはず。NVIDIA の実機と Secure Boot のときの動作は未確認
- VirtualBox の VM の GPU(vmsvga、vendor 0x15ad)では符号化できないので、just verify は「対象外」と出す

### just vm-test で見つかったこと(2026-10-24)

- 初回の起動では、起動画面(plymouth)が構成のあいだ(約 23 分)出たままで CPU を 1 分 20 秒使い、GDM の起動のときに SEGV で落ちて plymouth-start.service が failed で残った。構成サービスの最初に `plymouth quit` し、GRUB の `GRUB_CMDLINE_LINUX_DEFAULT` を `quiet` にした(splash を外す)
- 初回の起動のカーネル引数は、インストーラーが書いたもの(crashkernel あり)のまま。kdump を消して update-grub しても、再起動するまで /proc/cmdline には残る。just verify は GRUB の設定(grub.cfg)で確かめ、動いているカーネルに残っているときは「再起動で反映」と出すだけにした
- 入れなおしから RDP の待ち受けまで人手なし、強制的な電源断のあと、gnome-shell の SEGV のあと、のいずれも、verify(106 項目)と verify-rdp が通った(VirtualBox 7.2、CPU 1、メモリ 4GB)
- 2026-10-25、v0.2.0 の前(レビューの指摘 #1〜#14 の修正と全体の整合の直しを含むスクリプト)で、もう一度 just vm-test を通した。ISO の起動から RDP の待ち受けまで約 75 分(CPU 1)。入れた直後・強制的な電源断のあと・gnome-shell の SEGV のあとのいずれも、verify(128 項目。agent の設定の確認を足した版)と verify-rdp が通り、8 項目すべて通った。入れた直後はカーネルの引数に splash が残る旨を出す(再起動で反映)。GPU は VM にないので対象外

### UPS(2026-10-24 追加)

- Ubuntu 26.04 の NUT は 2.8.4(nut-server・nut-client)。`/usr/lib/systemd/system-shutdown/nutshutdown` が、終了の最後に `upsmon -K`(POWERDOWNFLAG の `/etc/killpower` があるか)を見て `upsdrvctl shutdown` で UPS の出力を止める。`nut.conf` が `MODE=none` なら何もしない(パッケージのスクリプトで確認)
- 先に PC を正しく終了しても、UPS が出力を出し続けると、BIOS の「電源が戻ったら起動」の条件(電源がいったん切れること)が満たされず、復電しても起動しない。usb では primary の upsmon が `/etc/killpower` を作り、上の流れで出力を止めさせる。netclient(secondary)では出力を止めるのは NUT サーバーの側
- upsmon は `RUN_AS_USER nut` で動き、NOTIFYCMD も nut で動く。通知の送り先(`/etc/agent-host/notify.env`、640 root:agent)は ACL で nut にだけ読ませる(`setfacl -m u:nut:r`)。84-notify.sh が書きなおしても同じファイルなので ACL は残り、85-ups.sh も毎回付けなおす
- upsd は 127.0.0.1 と ::1 だけで待ち受ける(LAN の他の機器には配らない。配るなら別に設定する)。upsmon が upsd に入るパスワードはホストで作り、`/var/lib/agent-host/ups-upsmon.password` に置く
- VirtualBox で、NUT の擬似ドライバー(`driver: dummy-ups`、`port: dummy.dev`。`/etc/nut/dummy.dev` に `ups.status: OL` などを書く)で確かめた。状態を OB にすると「on battery」、OL に戻すと「on line power」を記録して通知を送り(nut で agent-notify が動いた)、`upsmon -c fsd` で「Executing automatic power-fail shutdown」から約 20 秒で電源断まで進んだ。起動しなおすと `/etc/killpower` は消えていて、just verify(117 項目)と verify-rdp が通った
- NUT は設定ファイルの ASCII 以外の文字を捨てる(`addchar: discarding invalid character`)。85-ups.sh が書く設定は英語にした。nut-server のパッケージを入れた時点で、設定が空の upsd が起動して失敗を繰り返し、起動の回数の上限に掛かった。設定を書いたあとに `systemctl reset-failed 'nut-*'` してから起動する
- 37-gpu.sh で、`apt-cache policy` の出力が日本語(「候補:」)だったので `Candidate:` を探す判定が外れた(構成は ja_JP.UTF-8 で動く)。`LC_ALL=C` を付けた。vainfo は 26.04 では `vainfo` のパッケージ(libva-utils ではない)
- 未確認: 実際の UPS での終了・出力の停止・復電での起動。USB の HID の UPS を GNOME の upower も見て、電池が少ないときに GNOME が別の動作をしないか

### Orca Mobile(2026-10-24 調査、v1.4.237 のソース)

- スマホのアプリからデスクトップの Orca につなぐ。つなぎ方は LAN(`ws://<ホスト>:6768` に直接。アカウントは不要)と Orca Relay(ベータ。両方が Orca のサーバーへ外向きにつなぎ、サーバーが中継する。デスクトップで Orca のアカウントにサインインが要り、アカウントによっては使えない)
- LAN でも、スマホとの通信はエンドツーエンドで暗号化する作り(`src/main/runtime/rpc/e2ee-channel.ts`)。ペアリングは QR コード
- 待ち受けは普段 127.0.0.1:6768(VirtualBox の ss でも確認)。ペアリングの操作をすると 0.0.0.0 に広げ、一度つないだ端末があれば次の起動からは最初から広げる(`runtime-rpc-pairing-types.ts`、`runtime-rpc-network-exposure.ts`)。自動ログインで起動した Orca にも、そのままつながるはず(未確認)
- このリポジトリでは対応のための設定を足さない。LAN で使うなら env.yaml の `dev_ports` に 6768 を足せば `lan_cidrs` からだけ開く。Relay はポートを開けずに使える
- スマホから agent のターミナルにコマンドを送れるので、スマホの管理(画面のロック、無くしたときにペアリングを外す)を手順に書いた

### レビューの指摘への対応(2026-10-25、VirtualBox で確認)

- #1: agent のホームの中は、すべて agent の権限(`agent_run` = runuser)で書く。write_agent_file は同じディレクトリの一時ファイルから `mv -T` で置き換える(末端のリンクは置き換わるだけで、途中のディレクトリのリンクは agent の権限で止まる)。tests/test_agent_home.py で、末端と途中のディレクトリのリンクでホームの外が変わらないことを確かめる(Docker の中)。動いている VM に just update して verify が通った
- #2: sysadmin の鍵(`/opt/agent-host/sysadmin_authorized_keys` → `~sysadmin/.ssh/authorized_keys`。インストーラーもここに書いていた)とパスワード(`usermod -p`)を just update のたびに env.yaml に合わせる。VM で、鍵を 1 本足すと入れ、外すと `Permission denied (publickey)` になること、パスワードのハッシュを替えると新しいパスワードで sudo でき、古いものでは通らないことを確かめた
- #3: RDP の認証情報は、渡したもののハッシュを `/var/lib/agent-host/rdp-credentials.sha256`(root だけ)に置き、env.yaml と違えば `rdp.env` を置きなおす。キーリングに入れるのは `first-login/rdp-credentials.sh`(ログインのたびの自動起動)。agent がログイン中なら just update がその場でセッションのバスを通して呼ぶ。VM で、パスワードを替えると新しいもので verify-rdp が通り、古いものでは通らない(終了コード 134)ことを確かめた。動いている gnome-remote-desktop は、再起動なしで新しい認証情報を使った
- 未確認: agent-host-restore(root の tar の展開と chown -R)が、細工した書き出しで #1 と同じ問題を起こすか
- #4: 移行の書き出しは、名前だけでの除外をやめ、~/work の中で見つけた node_modules・__pycache__・.venv のパスと、Orca のキャッシュ(~/.config/orca の中に固定したパターン)だけを除く。tests/test_backup.py で、同じ名前のファイルとブランチが残ることを確かめる(Docker の中)。VM での書き出しと取り込みの通しはしていない
- #5: netclient では nut-server を入れないので、nut の HOME(/var/lib/nut)が無く、通知が送られなかった。85-ups.sh が mode に関わらず作り、agent-notify は記録を書けなくても送る。HOME の無いユーザーで偽の Slack に届くことを Docker で確かめた。netclient を VM・実機の NUT サーバーにつないでは確かめていない
- #7: 移行の書き出しに ~/.aws・~/.config/gcloud(logs を除く)・~/.azure・~/.config/tea・~/.config/mise を足した(tests/test_backup.py)
- #8: env.yaml の検査に型の表(TYPES)、hostname・ハッシュ・SSH の鍵の形、dev_ports の順、ipmsg_broadcast の IPv4 を足した(tests/test_render.py)
- #9: 手元の一時ファイルは実行ごとの build/.run.XXXXXX、構成リポジトリのひな形の復号先は build/.dec/<ホスト>.XXXXXX に置く(tests/test_envs.py で寿命を重ねても混ざらないことを確かめる)
- #10: provision.sh が実行中の印 provision-incomplete を置き、成功したら消して BUILD-INFO.ok を残す。VM で、存在しない UPS のドライバーで 85-ups.sh を失敗させると just status が「前回の実行が最後まで終わっていない」を出し、verify の 2 項目が失敗し、直して just update すると戻ることを確かめた。just update の構成の出力はホストの /var/log/agent-host-update.log に残り、just logs で見られる
- #11: 入れなおしたホストに取り込むまでは、一時の known_hosts でつなぎ、指紋を新しいホストの画面で照らす(文書だけ。検証のときに Docker で回避できることを再現した)
- #12: /dev/dri がなくても verify が止まらない(静的に確認)
- #13: just update で反映する範囲を UPDATE_SCOPE と文書の表に持つ。壁紙の色と Dock は first-login/desktop-env.sh がログインのたびに、変わったときだけ入れる。VM で desktop_color を変えて just update すると、ログイン中のセッションの壁紙の色がその場で変わった
- #14: xrdp を採らなかった主な理由を「別のセッションを作る」に直した(上の「設計で決めたこと」)
- #6: Node.js はシステムの証明書ストアを見ないので、05-proxy-ca.sh が CA を OS に入れても、構成の途中の npm は TLS を検査するプロキシの下で `UNABLE_TO_VERIFY_LEAF_SIGNATURE` になる(自己署名の CA と https のサーバーを Docker で立てて再現。`NODE_EXTRA_CA_CERTS` で通る)。provision.sh が CA があるとき `NODE_EXTRA_CA_CERTS`・`SSL_CERT_FILE`・`REQUESTS_CA_BUNDLE` を export し、`apt-get update` を 05-proxy-ca.sh のあとに回した。実際の TLS を検査するプロキシの下での通しは未確認のまま

### Windows で作られた和文の本のリポジトリ(2026-10-25、VirtualBox で確認)

v0.2.0 の VM で、Windows の PC で書かれてきた upLaTeX の和文の本のリポジトリ 5 本を、agent として扱えるかを確かめた(手元の clone を git bundle で持ち込んだ)。

- 日本語まわりは問題がなかった
  - PDF は rootless Docker の TeX Live のコンテナ(paperist/texlive-ja)で組め、出力の所有者は agent だった
  - 和文フォント(原ノ味)はすべて埋め込まれ、pdftotext で日本語を取り出せた
  - 同じイメージの digest で組んだ 4 本は、Windows で組んだ PDF とページ画像が全ページ一致した(tools/compare_build.py 相当、40dpi)
- 最初は 4 本中 3 本で差が出たが、原因はホストではなかった。`texlive-ja:latest` が手元と VM で別のイメージを指していた。FROM を同じ digest にすると差は 0 になった
- draw.io の書き出し(原ノ味を入れた rlespinasse/drawio-export)、Playwright での表紙の書き出し(Google Fonts の Noto Sans JP、縦書きを含む)、Gradle のテスト(JDK 21 は `mise use java@temurin-21`)、python-pptx での PowerPoint の生成も、sudo なしで動いた
- Playwright(1.64.1)は 26.04 を「非公式・24.04 とみなす」扱い。`npx playwright install chromium`(`--with-deps` なし)で取得でき、ホストに Chrome が入っているので足りないライブラリはなかった
- 止まったもの(ホストの側)
  - `python` コマンドがない。`python tools/....py` で `python: not found` になった(#20)
    → 60-devtools.sh で python-is-python3(`/usr/bin/python` へのリンク 1 本。Depends は python3 だけ、`apt-get install -s` で新しく入るのはこれだけで削除は 0)を入れた。版は Ubuntu の更新に任せる
- 止まったもの(本のリポジトリの側の書き方)
  - justfile が `set windows-shell` だけで PowerShell の構文のため、Linux の just(`sh -cu`)では前段で構文エラーになる。justfile を通さず `docker compose run …` を打てば組める
  - git に実行権なし(100644)で記録された gradlew が `./gradlew` で動かない(`sh ./gradlew` なら動く)
- just はアーカイブ(universe)に 1.45.0 があるが、agent が `mise use -g just` で入れられる(1.59.0)ので入れていない。apt と mise の両方に入ると、どちらが動いているか分かりにくい。エージェント向けの説明の mise の例に `mise use -g just` を足した(説明はすでにあれば上書きしないので、入れ済みのホストには届かない)
- 5 本の PDF のイメージで、VM(ルート 37GB)の空きが約 15GB から約 7.6GB に減った

### PDF ビューアー(2026-10-25 追加、#19)

- PDF の既定のアプリを決めていなかったので、Atril(26.04 の universe の 1.28.2。GTK3、desktop ファイルは `atril.desktop`)を入れ、agent の mimeapps.list の `application/pdf` にした。Recommends は dbus のセッションと gvfs だけで、Caja は Suggests(ubuntu:26.04 のコンテナで `apt-cache show` を見た)
- 選ばなかったもの: zathura(メニューがなく vim 風のキー操作が前提)、MuPDF(X11 なので開くたびに Xwayland が起動する)、qpdfview(このホストにない Qt を一式入れることになる)
- 未確認: ubuntu-desktop-minimal で Papers(main に 50.2 がある)や Evince が入るか、Atril のメモリの量、日本語の PDF の表示(VM で確かめる)

## 確認できていないこと

実機でしか確かめられないもの、実際のアカウントやネットワークが要るものは、まだ確かめていない。

- HDMI のダミープラグでの RDP(モニターなし)、BIOS の停電復帰、lan_cidrs の外から 22・3389 に届かないこと(受け入れテスト 7)
- 電源のプロファイル performance(VM にはない)、RDP の extend モード(VM では GNOME Shell が異常終了した)
- 実際の HTTP プロキシ・TLS を検査するプロキシの下での動作、独自の CA の証明書を使う Gitea への接続
- Slack への送信、Claude Code の Remote Control、Orca Mobile でのペアリング(LAN・Relay)、クラウドの CLI のログイン(SSO・ブラウザ)
- IP Messenger の名前での検索を、実機の LAN の既定のブロードキャスト(255.255.255.255)で行うこと
- RDP のクリップボードでのファイルのコピー、Zed での日本語入力
- 実際の UPS での終了、出力の停止、復電での起動(VM では NUT の dummy-ups で、通知と終了と起動しなおしまで確かめた)
- 実機の GPU で RDP の画面を符号化すること(Intel の full 版の VA-API、AMD の Mesa、NVIDIA のドライバーと NVENC。Secure Boot のときの NVIDIA)
- systemd-oomd がメモリ不足のときに Orca ごと止めないか
- UPS の netclient を実際の NUT サーバーにつなぐこと。USB の HID の UPS を GNOME の upower も見て、電池が少ないときに GNOME が別の動作をしないか
- このホストの Orca を Remote Orca Server として公開し、手元の Orca からつなぐこと
- agent-host-restore(root の tar の展開と chown -R)が、細工した書き出しで、agent のホームの外を書き換えられないか(#1 と同じ種類の問題)
- 原因を調べていないもの: インストール中にライブ環境のログイン画面で止まって見えること、first-login の "RDP server certificate is invalid"、`localectl set-x11-keymap` の "Access denied"、RDP での Caps Lock の状態のずれ

## 運用上の注意

- Codex のログインはデバイスコード認証(`codex login --device-auth`)。ChatGPT 側の設定で事前に有効化しておかないと、エラーにならず止まって見える
- Codex の認証情報は `~/.codex/auth.json` に平文で保存される。`agent` のホームの権限を絞る
- Orca は .deb 版なら自分では更新を適用しない(通知は出る)。apt-mark hold で固定している。上げるときは 70-orca.sh の版と SHA256 を直す
- バージョンを上げるときは、版を持つスクリプト(60-devtools.sh、62-agents.sh、63-clouds.sh、65-docker.sh、70-orca.sh、72-editors.sh、76-desktop.sh)の先頭の値を直し、手順書の付録「固定しているバージョン」も直して、`just update <ホスト>` で反映する
- build-usb.sh で作った ISO と、ターゲットの `/opt/agent-host/env.sh`(root のみ読める)には秘密情報が入る
- デスクトップ共有とリモートログインを両方有効にすると、デスクトップ共有が 3390 番に移る。リモートログインは有効にしない
- いちばん崩れやすいのは受け入れテスト4(再起動後、何もせずに RDP がつながるか)。ここを最優先で検証する
