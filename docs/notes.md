# 技術メモ

このリポジトリを作るときに調べたこと・確かめたことの記録。仕様は [SPEC.md](SPEC.md)、手順は [manual-steps.md](manual-steps.md) と手順書(setup-guide.tex)にある。
版を上げるときや、挙動が想定と違うときに、ここで理由と確かめた範囲を見る。

## 検証した環境

- VirtualBox 7.2.6 の VM(UEFI、メモリ 4GB)。ホストは Windows 10 で、Hyper-V(Docker Desktop)と共存させたため VirtualBox は NEM モードで動き、CPU 2 つ以上ではゲストのカーネルが止まった。そのため CPU 1 で試した
- ISO は ubuntu-26.04.1-desktop-amd64.iso から build-usb.sh で作った。USB からの起動から構成の完了まで約 47〜67 分、再起動から RDP の待ち受けまで約 80 秒
- RDP は Windows のリモート デスクトップ接続(mstsc)と FreeRDP で確かめた。キーボードは 101(英字配列)
- shellcheck は 0.11.0(Docker の ubuntu:26.04)で指摘なし
- v0.2.0 から、`just test`(Docker の中の試験)、`just verify`(ホストの項目。v0.3.0 で 190 項目あまり)、`just verify-rdp`、`just vm-test`(VM に入れなおしからの通し。VirtualBox か QEMU/KVM)で機械的に確かめている
- v0.3.0 から、`just vm-test` は利用者 2 人の env で通す(1 人目のセッションを落とし、2 人目が続くことも確かめる)
- 2026-10-28 から、エージェントのホスト(env.yaml の `vm`)の QEMU/KVM(qemu-system-x86 10.2.1、OVMF 2025.11、q35、virtio のディスク、CPU 2、メモリ 4GB)でも `just vm-test` を回す
- 実機ではまだ確かめていない(下の「確認できていないこと」)

## 設計で決めたこと

1. 物理 PC への Ubuntu の自動構成は、公式の autoinstall を使う。Server 専用ではなく Desktop でも使える
2. 常時稼働させたいが、AI エージェントを動かすためにデスクトップが必要 → Desktop 版に常時稼働の設定を足す
3. エージェントの作業環境は Orca(stablyai/orca。Claude Code や Codex を git worktree ごとに並列実行する ADE)。Codex も併用する
4. 遠隔操作は xrdp ではなく、GNOME のリモートデスクトップ(gnome-remote-desktop)の RDP にする。0.3 から、利用者ごとのヘッドレスのセッションで動かす(下の 7)
   - (0.2 まで)xrdp やリモートログインは別セッションを作るため、再起動後に誰かがログインするまで Orca が起動しない、として seat0 のデスクトップ共有を使っていた。0.3 からは systemd がヘッドレスのセッションを起動のときに立てるので、この理由は当たらない
   - Ubuntu の GNOME のセッションは 25.10 から Wayland だけ(上流の mutter が 49 で X11 を既定で無効にし、50 で削除)。xrdp は Xorg のセッションを作るので、GNOME を動かせない。xrdp・xorgxrdp と、Xfce などの X11 のセッションは 26.04 にもある(Ubuntu 26.04 のリリースノート「Other desktop sessions, such as KDE on X11, Xfce, ... can still be launched using an X.org session」。2026-10-25 に確認)
   - (0.2 まで)デスクトップ共有は物理セッションを共有するので、自動ログイン + Orca 自動起動と両立した
5. パスワードなしで立てるセッションではキーリングが開かない → 利用者のキーリングを空パスワードにする(中身はホームの 700 だけで守られる)
6. post-install は late-commands の中ではなく、初回起動時の `agent-host-provision.service` が実行する(インストール中の chroot では ufw などが動かないため)
7. 1 台を複数の人で使えるように、利用者ごとに Linux のユーザー、ヘッドレスのセッション、RDP のポートを分ける(0.3、#15)。0.2 までの「1 台は 1 人」では、複数の人が同じセッション(agent)に入ると Claude Code・Codex のログインが 1 つになり、ひとりのサブスクリプションを共有することになった。比べた方式は「利用者ごとのヘッドレスのセッション: 方式の比較」

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
- キーボード配列は env.yaml の `keyboard_layout` で決める(検証は 101 キーボードで行った)。first-login が入力ソースを `[('xkb', <配列>), ('ibus', 'mozc-on')]` にし、切り替えに Ctrl+Space を足す(0.3 のあとで日本語入力を fcitx5 に替え、入力ソースは配列だけにした。下の「半角/全角の押しっぱなしで gnome-shell が漏れて固まる」)。Mozc の ibus エンジンの配列は `default`(システムの配列に従う)
- インストーラーが入れる `mozc-jp` は、切り替えた直後が直接入力で、ひらがなにするには半角/全角キーが要る。101 キーボードでは切り替えはできても日本語を打てなかった。`mozc-on`(切り替えた時点でひらがな)にして打てた(確認済み)
- 入力ソースに Mozc が 2 つ並んでいた(`[('xkb', 'us'), ('ibus', 'mozc-on'), ('ibus', 'mozc-jp')]`。v0.3.0 の release ブランチの VM で、Ctrl+Space の切り替えに Mozc が 2 つ出た)。Ubuntu の gnome-settings-daemon(50.0-1ubuntu1)のパッチ keyboard-Use-ibus-sources-from-locale は、gsd-keyboard が利用者ごとに初めて動くとき(`~/.local/share/gnome-settings-daemon/input-sources-converted` がないとき)、ロケールの入力メソッド(ja_JP なら `mozc-jp`)を、入っているものを見ずに末尾に足す。first-login.sh がセッションの前にこの目印を置き、desktop-env.sh がすでに足された `mozc-jp` を外すようにした(bob で確認。新しく入れたときの確認は release の vm-test)。0.2 までの agent でも同じことが起きていたはず(未確認)
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
- systemd-oomd がメモリ不足のときに Orca ごと止めるかは、2026-10-25 に VM で確かめた(下の「メモリ不足のときの systemd-oomd」。端末 1 つだけが止まる)
- SPEC.md §10 の対象外だが気付いた点: Orca の初回の案内で「Yolo モード」(確認なしでコマンド実行)が最初からオン。agent でログインしたアカウントのスキルが `~/.claude/skills/synced/` に同期される。どのアカウントでログインするかは決めておく

### Docker(2026-10-24 追加)
- 公式 apt リポジトリ(26.04 resolute 対応、過去の版も残る)から docker-ce 29.9.2 ほか 5 つ(合わせて 6 つ)を版指定で入れて hold する。署名鍵の fingerprint は 9DC858229FC7DD38854AE2D88D81803C0EBFCD88
- agent は rootless Docker。docker グループは実質 root になるので使わない。root のデーモンは止め、agent に linger を付けて `dockerd-rootless-setuptool.sh install` を agent で実行する。`DOCKER_HOST` は `~/.config/environment.d/60-docker.conf`
- Ubuntu 24.04 以降は特権のないユーザー名前空間を AppArmor で制限しているが、deb で入れた rootlesskit のプロファイルは apparmor パッケージに含まれる(Docker の公式文書)
- 26.04 で上の手順が通り、hello-world が動くことを VirtualBox の新規インストールで確認済み。1024 未満のポートを待ち受けられないなど rootless の制限がある
- subuid/subgid は useradd が割り当てる。Ubuntu 26.04 の `/etc/login.defs` は `SUB_UID_COUNT 65536`(SUB_GID_COUNT も同じ)で、useradd は既存の行と重ならない範囲を取る。65-docker.sh は行がなければ止まるだけで、自動では足さない(2026-10-27、#29)
- verify は利用者ごとに、pasta の設定(`systemctl --user show docker.service -p Environment`)と `hello-world` の実行を見る。hello-world は手元になければ取得し、終わったら消す(verify は読むだけという原則の例外)。取得できないとき(Docker Hub の回数の制限、プロキシ)は ✗ ではなく未検証にする。デーモンの取得も rootlesskit の名前空間から pasta を通るので、取得できればデーモン側の通信も確かめたことになる。コンテナからの通信(`wget`)は見ない。ほかに、passt が入っていること、`/etc/subuid`・`/etc/subgid` の範囲どうしが重ならず利用者ごとに 65536 個以上あること、外した利用者の dockerd・rootlesskit・containerd が動いていないこと(10-users.sh が user@ を止める)を見る(2026-10-27、#29。静的に書いたもので、VM ではまだ流していない)

### 専用の PC を置く理由(2026-10-25 の調査)

エージェントをどこで動かすかを比べた。各社の文書は 2026-10-25 に読んだもの。

- **手元の PC**: エージェントの CLI は手元で動くので、閉じる・スリープ・再起動で止まる。確認なしで動かすと、私的なファイルや個人のログイン情報(SSH の鍵、ブラウザのログイン、パスワードの管理ソフトなど)と同じ環境で動くことになる
- **Claude Code の cloud sessions**(code.claude.com/docs/en/claude-code-on-the-web): Anthropic が管理する隔離された VM で動き、手元を閉じても続く。Pro・Max・Team と一部の Enterprise で使え、利用の上限はほかの Claude の利用と共有。リポジトリの clone と PR の作成は GitHub が要る(Team・Enterprise は GitHub Enterprise Server も)。GitLab などは手元から送れるが、そのリモートには push で戻せない。ネットワークは既定で制限され、許可した先にだけ届く。組織が自前の実行環境(self-hosted environment)を用意すれば、そちらで動かせる。使わない時間が続くと VM が片付けられ、動いていたコマンドは戻らない。組織が IP の許可リストを使っていると失敗する
- **Codex cloud**(learn.chatgpt.com/docs/cloud): 作業ごとに作業場所があり、手元が眠っていても続く。手順は GitHub のリポジトリを選ぶところから始まる。インターネットへの接続は環境ごとに設定する。どのプランで使えるか、時間の上限、LAN の中に届くかは、読んだ範囲では書かれていなかった
- **クラウドの VM**: Orca は SSH の先や VPS でも動く(Orca の文書の Ways to run)。費用は比べていない。LAN の資源には VPN が要る。このリポジトリの autoinstall は物理の PC に USB から入れる前提で、クラウドの VM のイメージでは試していない
- **Orca の想定**(Orca の文書の Remote Orca Servers、v1.4.237 のソースの docs): Remote Orca Server では、作業する側がプロジェクト・worktree・端末・タブ・エージェントのアカウントとセッションを持ち、クライアントは画面になる。クライアントのノート PC が眠っても、つながりが切れても、エージェントは動き続ける。ログインは作業する側で行い、ノート PC のログインは引き継がれない。Remote Orca Servers はベータで、Tailscale か信頼できる LAN の中で使うことを勧めている。画面のない Linux では `orca-ide serve` で同じことができる
- この構成は、その「作業する側」を、OS の自動ログイン・キーリング・RDP・セッションの見張り・UPS まで含めて人手なしで保つもの。画面のない `orca serve` ではなくデスクトップと RDP にしたのは、ログインにブラウザが要るため(Claude Code は Chrome でログインした。受け入れテスト 2)、手元に何も入れずに Windows のリモート デスクトップ接続でつなげるため、人が同じデスクトップで手を入れられるため
- 未確認: このホストの Orca を Remote Orca Server として公開し、手元の Orca からつなぐこと(LAN なら env.yaml の dev_ports に 6768 を足すことになるはず)。公式の文書から手順を手順書に書き、LAN の IP で 6768 を足してつながることを確かめた(下の「Remote Orca Server」)

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
  - 2026-10-25 にソースで見直した(#17): gnome-remote-desktop 50.2 は、クライアントがグラフィックス パイプラインかコーデックに対応していると、色の深さを 32 にする(`grd-session-rdp.c`「Client prefers colour depth %u, invalidated by support of codecs or graphics pipeline」)。ホストの側では 24 にしても軽くならない。mstsc の側で 24 と 32 で何かが変わるか(#333 の遅さの原因)は未確認なので、値は 24 のまま残し、実機で比べてから決める
  - 同じときに、ひな形の `networkautodetect` を 0 から 1 にした。自動検出がないと RTT が 0 のままで、確認の返らないフレームが 2 つで送る量を絞る(`grd-rdp-gfx-frame-controller.c` の `activate_throttling_th = MAX (2, MIN (delayed_frames + 2, refresh_rate))`。grd も「High latency connections will suffer!」と出す)。60Hz・RTT 1ms の LAN では 1 にしても同じ 2 だが、RTT 50ms(VPN 越しなど)では 5 になる(静的な確認。実機の VPN 越しでは未確認)
  - #17 のもう 1 つの案(4K のダミープラグのとき、env.yaml で解像度を固定する)は入れなかった。#15 で seat0 の自動ログインとダミープラグをやめ、ヘッドレスのセッションにする予定のため
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

### Remote Orca Server(2026-10-28 調査、公式の文書)

- 読んだもの: Orca の文書の Remote Orca Servers(onorca.dev/docs/remote-servers)と SSH worktrees(onorca.dev/docs/ssh)
- 確かめたこと(2026-10-28): Connection address に LAN の IP を選び、env.yaml の dev_ports に 6768 を足した状態で、手元の Orca からホストの Orca につながった。リンクは `orca://pair?code=<base64 の JSON>` で、JSON は `v: 2`、`endpoint: ws://<LAN の IP>:6768`、`deviceToken`、`publicKeyB64`、`pairedDeviceId`、`scope: runtime`、`hostDescriptor` を持つ。Orca Mobile と同じ 6768 の待ち受けを使っている。`deviceToken` が秘密の値なので、リンクは人に見せない。VM か実機か、手元の Orca の版、何人目の利用者かは記録していない
- 手元の Orca が画面になり、プロジェクト・worktree・端末・エージェントのログインはホストに残る。手元が眠っても、切れても作業は続く。Orca ではベータ
- ホスト側: Settings → Remote Orca Servers → Advertise this app as a server → New Link → Connection address(LAN の IP か Tailscale のアドレス。127.0.0.1 は選ばない)→ Generate Access Link → Pair another Orca client の下のリンクをコピー。手元側: Settings → Remote Orca Servers → Add Server → 名前とリンク → Add Server →(Disconnected なら)Connect。全部ホストで動かすなら Advanced → Active Server
- ログインはホストのものを使い、手元のログインは引き継がれない
- リンクを持つ人はエージェントを丸ごと操作できる。許可は手元の PC ごとで、Shared Server Access で取り消す。新しいリンクを作ると、まだ使っていないリンクは無効になる。ポートをインターネットに直接開けないよう書かれている
- 版が違うと、非互換のプロトコルとして切れることがある(文書の記述)。ホストは 1.4.237 に固定・hold しているので、手元をそろえるか、ホストを上げる。実際に版が違うとつながらないかは未確認
- 待ち受けるポート: 6768(リンクの endpoint で確かめた)。LAN からなら dev_ports に足す。2 人目以降でずれるかは Orca Mobile と同じく未確認(段 0 の 9)
- 使わないもの: `orca serve` はデスクトップアプリが公開しているときに同じ構成で重ねて起動しない(文書の注意)。SSH worktrees は、利用者の SSH が SFTP 専用でポート転送も止めているので使えない(40-ssh-ufw.sh の `ForceCommand internal-sftp`、`AllowTcpForwarding no`)
- このリポジトリでは設定を足さない(手順書に手順を書いただけ。verify.sh も変えない)

### レビューの指摘への対応(2026-10-25、VirtualBox で確認)

- #1: agent のホームの中は、すべて agent の権限(`agent_run` = runuser)で書く。write_agent_file は同じディレクトリの一時ファイルから `mv -T` で置き換える(末端のリンクは置き換わるだけで、途中のディレクトリのリンクは agent の権限で止まる)。tests/test_agent_home.py で、末端と途中のディレクトリのリンクでホームの外が変わらないことを確かめる(Docker の中)。動いている VM に just update して verify が通った
- #2: sysadmin の鍵(`/opt/agent-host/sysadmin_authorized_keys` → `~sysadmin/.ssh/authorized_keys`。インストーラーもここに書いていた)とパスワード(`usermod -p`)を just update のたびに env.yaml に合わせる。VM で、鍵を 1 本足すと入れ、外すと `Permission denied (publickey)` になること、パスワードのハッシュを替えると新しいパスワードで sudo でき、古いものでは通らないことを確かめた
- #3: RDP の認証情報は、渡したもののハッシュを `/var/lib/agent-host/rdp-credentials.sha256`(root だけ)に置き、env.yaml と違えば `rdp.env` を置きなおす。キーリングに入れるのは `first-login/rdp-credentials.sh`(ログインのたびの自動起動)。agent がログイン中なら just update がその場でセッションのバスを通して呼ぶ。VM で、パスワードを替えると新しいもので verify-rdp が通り、古いものでは通らない(終了コード 134)ことを確かめた。動いている gnome-remote-desktop は、再起動なしで新しい認証情報を使った
- agent-host-restore(root の tar の展開と chown -R)の件は、2026-10-25 に #23 で確かめて直した(下の「移行の書き出しと取り込みを利用者の権限で」)
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

### 利用者ごとのヘッドレスのセッション: 段 0(2026-10-25、VirtualBox で確認、#15)

v0.2.0 を入れた VM(UEFI、メモリ 4GB、CPU 1)で、agent の自動ログインと見張りを止め、試験用のユーザー alice・bob(パスワードはロック、sudo なし、linger)を作って手で確かめた。

1. **ユニットはある。** gdm3 50.1 に `gnome-headless-session@.service`(system。`ExecStart=/usr/libexec/gdm-new-session %i --headless`、`Restart=on-failure`)、gnome-remote-desktop 50.2 に `gnome-remote-desktop-headless.service`(user)がある
   - **そのままでは立たない。** ユニットの `DynamicUser=true` のままだと `gdm-new-session` が `Failed: The connection is closed`(終了コード 70)で止まる。root で直に実行すると立つ。`User=gdm` の一時のユニットでは polkit の `manage-user-displays` で拒まれた(gdm の polkit の規則 `20-gdm.rules` は、gdm グループで、ユニット名が `gnome-headless-session@<user>.service` のときだけ許す)。ドロップインで `DynamicUser=no`・`User=gdm` にすると立った。DynamicUser で切れる原因は調べていない
2. **2 人が同時に RDP できた。** alice は 3389、bob は 3390 で、それぞれの画面で操作できた(mstsc)。FreeRDP の +auth-only で、それぞれの認証情報が通り、誤ったパスワードと、相手のポートに自分の認証情報では `ERRCONNECT_LOGON_FAILURE` になった
   - 同じ Windows から 127.0.0.1 に 2 つつなぐと、2 つ目が mstsc で「既に進行中のコンソール セッションがあるため…」と止まった。2 つ目を 127.0.0.2 にすると通った(VirtualBox の転送を 127.0.0.2 にも足した)。実機は IP で、別の PC からつなぐので当たらない見込み
   - **立てた直後のセッションはロックされていた**(`LockedHint=yes`)。パスワードがロックされているので本人は解除できない。画面ロックを無効にし(`lock-enabled false`、`idle-delay 0`、`disable-lock-screen true`)、`loginctl unlock-session` で外した。再起動のあとはロックされずに立った。画面ロックの設定は、セッションを立てる前(post-install)に入れる
   - 入力ソース(`[('xkb', 'jp'), ('ibus', 'mozc-on')]`)と切り替えの Ctrl+Space は、first-login と同じ設定を入れると効いた。半角/全角キーは mstsc から `Henkan_Mode` の押しっぱなしで届き、切り替えに使えなかった(#21。今の作りでも同じはず)
3. **root から設定できた。** `runuser -u <user> -- env XDG_RUNTIME_DIR=/run/user/<uid> DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/<uid>/bus grdctl --headless rdp …`(linger で user のバスがある)で、set-port・TLS・set-credentials・disable-view-only・disable-port-negotiation・enable と `systemctl --user enable gnome-remote-desktop-headless.service` ができた。セッションがなくてよいので post-install で済む
   - 認証情報は、TPM がないので `~/.local/share/gnome-remote-desktop/credentials.ini`(600)に GKeyFile で入る(「Init TPM credentials failed because No TPM device found, using GKeyFile as fallback」)。パスワードは平文。実機で TPM があるとどうなるかは未確認
   - grdctl は今の作りと同じく「RDP server certificate is invalid」を出すが、待ち受けと認証は正常
4. **再起動から戻った。** 誰も触らずに、起動から約 25 秒で 2 人のセッションが立ち、約 60 秒で RDP が待ち受けた(CPU 1 で負荷が 7 前後)。その前につなぐと mstsc は「内部エラーが発生しました」を出した(推定。待ち受けの前だったことからの推定で、確かめていない)
5. **異常終了から戻るには `Restart=always` が要る。** alice の gnome-shell に SIGSEGV を送ると、`gdm-new-session` は「Session finished」で正常に終わり(終了コード 0)、`Restart=on-failure` では戻らなかった。ドロップインに `Restart=always`・`RestartSec=5` を足すと、約 15 秒で新しいセッションが立ち、RDP の認証も通った。bob は gnome-shell の PID もセッションも変わらなかった。本人がログアウトしても立ちなおす
6. **切断しても続いた。** alice の端末で 5 秒おきに書くループを動かし、RDP を切って 3 分待つと、書き続けていた。セッションは残り、ロックされなかった
7. 一部だけ確かめた: gsettings は user のバスから入れられ、ヘッドレスのセッションで効いた。Mozc は動いた。ログイン キーリングがないと、VS Code が「Choose password for new keyring」を出した(空のまま続行)。キーリング・Clipboard Indicator・rootless Docker は、post-install を利用者ごとに回してから確かめる
8. GPU による符号化: VM に GPU がないので確かめられない(実機で未確認)
9. Orca Mobile の 6768 番: 確かめきれていない。alice と bob で Orca(1.4.237)を起動したが、初めての起動で、どちらも 6768 を待ち受けなかった(初回の案内の途中で止まっていたと見ている)。Orca の CLI の `serve` の説明には「--port がなければ 6768 を使い、使われていれば別のポートに移る。--port を付けると、使われているときはエラー」とある(`out/cli/specs/serve.js`)。デスクトップの Orca も同じなら、2 人目は別のポートにずれる(推定)。利用者ごとに post-install を回したあと、ペアリングして確かめる
10. メモリ: 何もしていない bob のセッションで PSS 約 460MB(gnome-shell 約 390MB。gnome-initial-setup が 145MB 動いていた)、RDP で使って VS Code と端末を開いた alice で約 880MB(PSS の合計。cgroup の memory.current はキャッシュを含め約 1.5GB)。エージェントやビルドを除いて、1 人あたり 0.5〜1GB を見込む

- ほかに分かったこと: `useradd -m` のホームは 750 だった(700 にする)。ヘッドレスのセッションの PAM のサービスは `gdm-autologin`、`Remote=yes`

### 利用者ごとのヘッドレスのセッション: 実装のあとの確認(2026-10-25、VirtualBox で確認、#15)

2 人(alice 3389、bob 3390)の試験用の env.yaml で `just vm-test` を流した。

- 入れなおしの初回の構成で、不具合が 2 つ見つかった(直した): まだいない利用者を `getent passwd` で引くと終了コード 2 で、set -e で構成が止まった。認証情報がないと `grdctl --headless status --show-credentials` は `Username: (null)` と出し、仮のパスワードが入らなかった。VM に直したものを当てて構成をやりなおしたため、vm-test の待ち時間(120 分)を過ぎ、入れなおしからの通しは ✗ になった。入れなおしから人手なしで通ることは、リリースのときの vm-test で確かめる
- `just update` で直したものを反映し、`AGENT_HOST_VM_REUSE=1` の vm-test で、verify(193 項目)、verify-rdp(2 人)、電源を切ったあとの戻り、1 人目の gnome-shell を落としてその人だけが戻り、2 人目の gnome-shell が続くことが通った
- `ss -tln` の一覧に、待ち受けている 3389 が出ないことがあった(`/dev/tcp` でつなぐと開いている。原因は調べていない)。vm-test と verify は、実際につないで確かめる形にした
- v0.3.0 の release ブランチで入れなおしから通すと、初回の構成は終わったのに、利用者のセッションが立たず RDP も待ち受けなかった。88-start-sessions.sh は GDM が動いていなければセッションを有効にするだけだったが、初回の構成は起動の途中(GDM の前)で動き、起動で立てるものはその前に決まっているので、有効にしてもその起動では立たない(次の再起動までつながらない)。上の確認は `just update` と `AGENT_HOST_VM_REUSE=1` で、GDM が動いている道しか通っていなかった。同じ VM でセッションを `systemctl start --no-block` で立てると、2 人とも RDP が待ち受けた。GDM の起動が控えているとき(`systemctl list-jobs gdm.service`)も立てる指示を積むようにした
- v0.3.0 の release ブランチの VM(`keyboard_layout: jp`、入れなおしたもの)で、#15 の残りを確かめた。(1)alice が RDP のパスワードを変えたあと書き出し、alice の認証情報を仮のパスワードに戻して(新しいホストに入れた直後と同じ状態)、取り込んで再起動した。認証情報のファイルは書き出す前と同じ中身に戻り、仮のパスワードでは通らなかった(`just verify-rdp` は未検証)。(2)env.yaml の `users` から alice を外して `just update` すると、alice の鍵では SFTP もシェルも `Permission denied (publickey)` になった(sshd は「AllowUsers にない」。アカウントは期限切れ、セッションは止まり、3389 は閉じ、ufw の規則も消えた。ホームは残る)。外す前は、同じ鍵で SFTP に入れた(シェルは sftp だけで断られる)
- 空パスワードのログインキーリングは、ヘッドレスのセッションでも効いた(2026-10-25、v0.3.0 を入れた VM の bob)。誰も開いていないあいだは `Locked=true` だが、`org.freedesktop.Secret.Service.Unlock` はプロンプトなし(返りが `/`)で通り、`Locked=false` になった。キーリングの中に Chrome の項目(Chrome Safe Storage など)が、パスワードを聞かれずに保存されていた
- `grdctl --headless status` は View-only を出さない。操作できることは RDP で確かめた
- 画面で: 2 人が同時に mstsc でつながり、それぞれロックされていないデスクトップが出た。bob の端末から `ls /home/alice` は Permission denied。alice が RDP のパスワードを変え、デーモンを再起動したあと新しい値で入れた

### 利用者ごとのヘッドレスのセッション: 方式の比較(2026-10-25、#15)

| 方式 | 選ばなかった理由 / 選んだ理由 |
|---|---|
| 全員ヘッドレス(選んだ) | systemd が起動のときに全員のセッションを立て、落ちたら立てなおす(Restart=always)ので、人手なしで戻る目的を保てる。1 人の台も同じ作りにでき、seat0 の自動ログイン・見張り・HDMI ダミープラグが要らなくなる。利用者ごとに Linux のユーザーが分かれるので、ホーム(サブスクリプションのログイン)も分かれる |
| 1 人目だけ seat0 の自動ログイン + デスクトップ共有、2 人目からヘッドレス | 作りが 2 通りになり、検査と手順も 2 通りになる。1 人目だけダミープラグと見張りが要る |
| GDM のリモートログイン(RDP でつないだときにログインする) | つなぐまでセッションと Orca が立たないので、再起動のあとに誰かがログインするまでエージェントが動かない |
| 1 つのセッションで CLAUDE_CONFIG_DIR などを分ける | 同じセッションに入れる人は、誰の認証情報でも使えるので、分けたことにならない |

- RDP のパスワードは、env.yaml の値を初回だけの仮のものにし、本人が `grdctl --headless rdp set-credentials` で変える。動いている RDP のデーモンは起動したときの認証情報を使い続け、変えたあとも古いパスワードで通り、新しいものは拒まれた。`systemctl --user restart gnome-remote-desktop-headless.service` で新しいものに替わった(2026-10-25、VirtualBox で確認。just update のあとも変えた値が残り、verify-rdp はその人を「未検証」、`--ask` の経路で今のパスワードを渡すと通った)。構成は認証情報がまだないときだけ仮の値を入れる。利用者どうしを隔てる実質の境界なので、管理者(env.yaml と ISO を見られる人)が知らない値にする
- RDP のポートは利用者に固定する(env.yaml で必須)。並び順で割り当てると、外したり並べ替えたりしたときに残った人の接続先が変わる(計画のレビューの指摘)
- 外した利用者は、ユーザーとホームを残して期限切れにする(`usermod --expiredate 1`)。パスワードのロックだけでは鍵の SSH は止まらない。`AllowUsers` からも外す(`Match User` から外れた人が鍵でシェルに入れるのを防ぐ)
- `just verify-rdp` は、仮のパスワードで通らなかったときに成功にも失敗にもせず「未検証」と出す。変えたのか、設定の誤りや障害かを区別できないので、`--ask` で今のパスワードを確かめる経路を足した

### zram のスワップの sysctl(2026-10-25 追加、#18)

- `vm.swappiness = 180`、`vm.page-cluster = 0` を `/etc/sysctl.d/60-agent-host-zram.conf` に置いた(36-minimize.sh)
- 根拠: カーネルの文書(admin-guide/sysctl/vm.rst)は、swappiness は 0〜200 で既定 60、「zram や zswap のようなメモリ上のスワップでは 100 を超える値も考えられる」とする(180 を勧めてはいない)。page-cluster は「0 で先読みを完全に止める」。Pop!_OS は zram のとき swappiness 180、zstd なら page-cluster 0 にしている(pop-os/default-settings)。systemd-zram-generator は sysctl を設定しない
- ファイルのスワップは優先度の低い予備として残した。swappiness が高いので、zram が満ちたあとはディスクにも積極的に送る(推定)
- 未確認: 26.04 の既定の値(推定 60)、エージェントを並べたときの応答・圧縮率・systemd-oomd の挙動への効き目(32GB 以上の実機で確かめる)。最近のカーネルでは zram の読み込みが先読みを通らない場合があり、page-cluster 0 の効き目は小さいかもしれない

### メモリ不足のときの systemd-oomd(2026-10-25、VirtualBox で確認、#16)

v0.2.0 の VM(メモリ 4GB、CPU 1、zram あり)、Orca 1.4.237 で確かめた。**設定は変えていない。**

- 既定: systemd-oomd は動いている。user@.service に Ubuntu の drop-in(`10-oomd-user-service-defaults.conf`)で `ManagedOOMMemoryPressure=kill`・`ManagedOOMMemoryPressureLimit=50%`、圧迫の時間は 20 秒(`oomctl dump`)。agent の user のマネージャーの `DefaultOOMPolicy` は stop
- Orca は端末ごとに cgroup を分けている。画面は `app.slice/app-orca-<pid>.scope`、端末の daemon は `app.slice/orca-daemon-<uuid>.scope`、端末は 1 つずつ `orca_ptys_<daemon>.slice/orca_pty_<daemon>_<n>.scope`(daemon が `systemd-run --user --scope` で作る。`OOMPolicy=continue`、daemon のスコープに `BindsTo`。`out/main/daemon-entry.js`)
- 試したこと: `orca terminal create` で端末を 3 つ作り、2 つで 2 秒ごとに時刻を書くループ、1 つで 64MB ずつ確保し続ける Python を動かした。約 50 秒で 2.7GB に達し、oomd が「memory pressure for …/user@1001.service being 81.58% > 50.00% for > 20s」で、**確保していた端末のスコープだけ**を止めた。ほかの 2 つの端末は書き続け(圧迫の間は間隔が最大 6 秒に延びた)、Orca の画面と daemon も動き続けた。カーネルの OOM killer は動かなかった
- つまり、エージェントの 1 つ(とそこから動かしたビルド)が暴走しても、止まるのはその端末だけ。Orca が端末を分けているおかげなので、Orca の版を上げたら同じかを確かめる(`/sys/fs/cgroup/user.slice/user-<uid>.slice/user@<uid>.service/orca_ptys_*.slice/` に端末ごとのスコープがあるか)
- 推定(確かめていない): rootless Docker のコンテナはすべて `app.slice/docker.service` に入るので、コンテナの中の暴走では、ほかのコンテナも一緒に止まる。Orca の画面そのものが膨らんだときは、画面のスコープが止まる(端末は daemon のスコープにつながっていて残るはず)
- 実機(32GB 以上)で、エージェントを並べたときに圧迫の 50%・20 秒に届くかは未確認
- **利用者が 2 人のとき(2026-10-25、#15 の作り、VirtualBox で確認)。** oomd は利用者ごとの user@ を別々に見る(`oomctl dump` に user@1001 と user@1002 が 50%・20s で並ぶ)。alice の user のサービス(Orca の端末と同じく app.slice の葉)で 64MB ずつ確保し続けると、約 45 秒で 2.4GB に達し、oomd は「memory pressure for …/user@1001.service being 54.61% > 50.00% for > 20s」で **alice のその単位だけ**を止めた。bob の user@1002 は oomd の記録に出ず、bob の 2 秒ごとのループ、2 人の gnome-shell・ヘッドレスのセッション・RDP のデーモン・Orca は動き続けた(ループの間隔は圧迫の間に最大 alice 7 秒、bob 5 秒)
- 推定(確かめていない): 圧迫はホスト全体のメモリの取り合いなので、bob の user@ にもかかる(full の累計は bob 37 秒、alice 31 秒)。今回は bob の側が 50%・20 秒に届かなかったが、長く強い圧迫で bob の側が先に閾値を超えると、oomd は bob の中のいちばん大きい単位を止めうる。1 台を何人で使うかは、メモリに余裕を持って決める(SPEC §2)

### 移行の書き出しと取り込みを利用者の権限で(2026-10-25、#23・#24)

Zenn の記事(#1 を題材にしたもの)の推敲で、事実の照合を頼んだエージェントが見つけ、主担当も Docker(ubuntu:26.04、GNU tar 1.35)で再現した。

- 書き出し: root の `tar -c -C / home/<利用者>/...` は、引数のパスの途中のリンクをたどる。利用者が `~/.config` を root だけが読めるディレクトリ(700)へのリンクにすると、その中の 600 のファイルが書庫に入った(利用者が直接読むと Permission denied)。末端のリンクは、リンクとして書庫に入る(たどらない)
- 取り込み: root の `tar -x -C /` は、展開先に元からある相対パスのリンク(`~/.config` → `../../srv/...`)をたどって、ホームの外に書いた。書庫に項目のあるディレクトリ(`~/.config/tea/` など)は、元のリンクを本物のディレクトリに置き換えた。推敲のエージェントの試験では、書庫の中のリンクを経由する書き込みと、展開先に元からある絶対パスのリンクは tar が拒んだ(仕組みは確かめていない)。`chown -R` は、ツリーの中のリンクも、引数がリンクの場合もたどらなかった(GNU coreutils 9.4、uutils 0.10.0)
- 直し方: 書き出しは、root の tar(記録とホストの身元)のあとに、利用者ごとに `runuser` の tar を同じ出力に続ける(tar の連結。読むときは `-i`)。あるものの確認と ~/work の中の探索も利用者の権限で行い、一覧は引数と標準入力で渡す(root だけが読める一時ディレクトリにあるため)。取り込みは、ホームの外を root で、ホームの分を利用者ごとに `runuser` の tar(書庫は root が開いて標準入力で渡す)で展開する。所有者は展開した利用者になるので `chown -R` をやめた。v0.2.0 の書き出し(記録は `agent_uid=` だけ)は、`uid.agent=`・`home.agent=home/agent` として読む
- 利用者に読めないもの: 書き出しの対象のパス自体が見えない(途中が 700 の root など)ものは、ないものとして飛ばす。見えるが読めないもの(rootless Docker のコンテナが subuid の持ち物で作った 700 のディレクトリ、711 の先の 600 のファイルなど)は、利用者の権限の `find ! -readable` で先に見つけて除き、記録に `unreadable=` として残し、書き出しと取り込みの最後に出す(止めると、ほかの全員の分を移せなくなるため)。リンクはリンクとして書庫に入るので見ない
- 1 人の tar が失敗しても(読んでいる間に変わったファイルがあると 1、読めないものが途中で増えると 2)、ほかの人の分は書き、最後にいちばん大きい終了コードで終わる。取り込みも、1 人が失敗してもほかの人の分とホストの身元は取り込み、失敗した利用者を出して 1 で終わる。取り込み先のホームにホームの外を指すリンクがあると、その利用者の tar は失敗する(試験では「Cannot mkdir: Invalid cross-device link」。EXDEV になる仕組みは確かめていない)
- 除くものの一覧は、`--exclude-from=-` で標準入力から渡す(`/dev/stdin` は利用者の権限で開きなおすので、root の umask が 077 だと読めなかった)
- 独立のレビュー(別のエージェント)で、失敗のしかたの回帰(~/work に読めないディレクトリがあると何も出さずに止まる、1 人の失敗で後の人の分が入らない、umask 077)と、試験の取りこぼし(711 の先の 600 のファイル)を指摘され、直した。tar を root に戻す変異は、先に除く仕組みがあるため試験では捕まえられない(二重の守り)
- tests/test_backup.py: 途中のリンクの先の root のファイルが書庫に入らない、元からある相対パスのリンクをたどらない、取り込んだものが利用者の持ち物になる、v0.2.0 の形も取り込める。直す前のコードでは前の 3 つが失敗することを確かめた
- #24: 80-agent-session.sh の `rm -f "$agent_env"` を `agent_run rm -f` にした。#1 のときに見落とした。パスを変数で受けていたので、ホームのパスを探す grep に当たらなかった
- VM での書き出しから取り込みまで(同じ VM に戻す形)は、2026-10-25 に v0.3.0 の release ブランチで確かめた(上の「実装のあとの確認」)。別の VM へ入れなおしての通しは未確認(just vm-test は取り込みを試さない)

### 構成リポジトリのひな形の暗号化の漏れ(2026-10-25、#27)

- `examples/fleet/.sops.yaml` の `encrypted_regex` が `initial_password`(v0.3.0 で `rdp.password` から名前を変えた)に一致せず、ひな形どおりに暗号化しても RDP の仮のパスワードが平文で残った。#15 で名前を変えたときの取りこぼし。正規表現に足し、ひな形の秘密の値のキーが一致することを tests/test_render.py で確かめる。確かめたのは正規表現とキーの突き合わせまでで、sops は実行していない

### Mermaid CLI(2026-10-27 追加、#28)

- `@mermaid-js/mermaid-cli`(`mmdc`)12.0.0 を既定で入れる。engines は `node >=22.13.0`(Node.js 24.22.1 で足りる)。puppeteer は dependencies ではなく peerDependencies(`^25.0.0`)なので、`npm_global`(`npm install -g`)では入れたときの最新の 25.x になる。puppeteer 25.16.0 も書いて、`/opt/mermaid-cli-<版>` に `npm install --prefix` で入れる(npm レジストリ、2026-10-26)。mermaid などの推移的な依存は、ほかの npm の道具と同じく入れたときの範囲内の最新になる
- ブラウザは 75-chrome.sh の Google Chrome を使い、puppeteer の chrome-headless-shell は取らない(`PUPPETEER_SKIP_DOWNLOAD=1`)。構成のときの取得が要らず、Chrome は SUID の sandbox(`/opt/google/chrome/chrome-sandbox`)を同梱するので、Ubuntu の非特権 user namespace の制限(`kernel.apparmor_restrict_unprivileged_userns=1`)の下でも `--no-sandbox` が要らない
- `PUPPETEER_EXECUTABLE_PATH` は全体の環境変数にせず、`/usr/local/bin/mmdc` のラッパーの中だけで、未設定なら `/usr/bin/google-chrome-stable` にする(エージェントのほかの puppeteer のプロジェクトに効かせない)
- npm 11.19.1 は puppeteer の postinstall について「install scripts not yet covered by allowScripts」と警告を出す。`PUPPETEER_SKIP_DOWNLOAD=1` なので、走っても何も取りに行かない
- 確かめたこと(2026-10-27、このリポジトリの v0.3.1 で構成したホストの利用者で。root の構成の経路ではなく、同じコマンドを利用者の一時ディレクトリに入れた): 上の `npm install` で入り、ラッパーで日本語のラベルを含む図を SVG・PNG・PDF に描き出せた。PNG の日本語は文字化けせず、sandbox のエラーも出なかった。Chrome のポリシー(`/etc/opt/chrome/policies/managed/agent-host.json`)の下でも headless で起動した。2 回目は入れなおさない(`.bin/mmdc` と puppeteer の版で判断)。Chrome は 156.0.8078.47 で、puppeteer 25.16.0 が想定する版(`PUPPETEER_REVISIONS.chrome`)と同じだった
- Chrome は自動更新されるので、puppeteer が想定する版とずれていく。mmdc が使うのはページの描画と PDF・スクリーンショットだけで、CDP の互換は広いが、ずれたときに動くかは未確認。動かなくなったら、puppeteer をそのときの Chrome に合う版に上げる(MERMAID_CLI_VERSION と同じく 60-devtools.sh の先頭)
- 2026-10-28、QEMU/KVM の VM(下の「エージェントのホストで vm-test を回す」)で: 構成の経路で入り、`just verify` の Mermaid CLI 12.0.0・puppeteer 25.16.0 が通った。利用者 2 人(alice・bob)で日本語のラベルを含む図を SVG・PNG・PDF に描き出せ、sandbox のエラーはなかった。PNG は目で見て文字化けなし。VM に 2 回目の just update をしても、`/opt/mermaid-cli-12.0.0` の inode と更新時刻は変わらなかった(構成の記録の「入れた」は毎回出る)
- 未確認: PDF の日本語の目視、プロキシ・独自の CA の下での `npm install`、Chrome と puppeteer の版がずれたときの動作

### git-flow(2026-10-27 追加、#33)

- このリポジトリは GitFlow(git-flow AVH)で運用するが、構成したホストに `git flow` がなく、#28 の feature finish を手の merge で代えた。利用者には sudo がないので、構成で入れる
- Ubuntu 26.04 の universe の `git-flow` 1.12.3-3build1(AVH 版。Homepage は petervanderdoes/gitflow)を 60-devtools.sh の apt で入れる。依存は `git | git-core` だけで、`apt-get install -s git-flow` で新しく入るのは git-flow だけ(2026-10-27、このホストの apt で確認)。上流の開発は止まっているので、ほかの apt の小物と同じく版は固定しない
- 確かめたこと(2026-10-27、sudo なしで `apt-get download` した .deb を利用者の一時ディレクトリに展開して): `git flow version` は「1.12.3 (AVH Edition)」。試しのリポジトリで `git flow init -d`、`feature start`、`feature finish` が通った。コミットが 1 つだけの feature は、既定では fast-forward で develop に入る(merge コミットを残すなら `git flow feature finish --no-ff`)。git flow の設定(`gitflow.*`)はリポジトリごとなので、clone や worktree のあとに一度 `git flow init -d` が要る
- 2026-10-28、QEMU/KVM の VM で: 構成の apt の経路で入り、`just verify` の「git-flow が入っている」が通った。利用者 2 人で `git flow version` が 1.12.3 (AVH Edition)、試しのリポジトリで `git flow init -d`・`feature start`・`feature finish` が通った

### エージェントのホストで vm-test を回す(2026-10-28、#35)

- 発端: #28(Mermaid CLI)と #33(git-flow)の VM での確認をエージェントに任せようとしたが、v0.3.1 で構成したホストでは VM を動かせなかった。VirtualBox も QEMU もなく、`/dev/kvm`(`root:kvm` の 660)の ACL は画面のセッションの持ち主(sysadmin)にしか付かず、利用者は kvm に入っていない。vm-test.sh は VBoxManage だけを使っていた
- 決めたこと: env.yaml に `vm`(真偽値。既定は false)を足し、選んだホストで 66-vm.sh が QEMU/KVM を入れ、利用者全員を kvm に入れる。VM 1 台でメモリを 4GB ほど使うので、既定で全ホストには入れない。rootless Docker の中で QEMU を動かす案は、dockerd(利用者の systemd)が kvm のグループを持たないので採らなかった。KVM なしの QEMU(TCG)は、インストールだけで数時間かかる見込みなので採らなかった
- パッケージ(Ubuntu 26.04 の apt。2026-10-28 に .deb の中身で確認): `ovmf` 2025.11-3ubuntu7.3 は `ovmf-generic`・`ovmf-amdsev`・`ovmf-inteltdx`・`ubuntu-virt` に依存するだけの移行用のパッケージで、ファイルを持たない。`/usr/share/OVMF/OVMF_CODE_4M.fd`・`OVMF_VARS_4M.fd` は `ovmf-generic` にあるので、それを入れる。`qemu-system-x86` 1:10.2.1+ds-1ubuntu3.3 の推奨には GUI・SPICE・OpenGL などがあるが、画面を出さないので `--no-install-recommends` にする(`apt-get install -s` で新しく入るのは QEMU と依存のライブラリ、seabios、ipxe-qemu、ubuntu-virt など 20 個)
- vm-test.sh の QEMU の版: `-enable-kvm -machine q35 -cpu host`、UEFI は OVMF の 4M(VARS は VM ごとに写す)、ディスクは virtio(qcow2、40G)、ネットワークは user モードの hostfwd を 127.0.0.1 だけに。VirtualBox の boot1 disk・boot2 dvd と同じく、ディスクを `bootindex=1`、ISO を `bootindex=2` にし、空のディスクからは ISO に落ちて入り、入れたあとはディスクから起動させる(インストーラーが再起動しても、ISO の autoinstall を繰り返さない)。電源断は pid に SIGKILL
- 確かめたこと(sudo なしで `apt-get download` した qemu-system-x86・ovmf-generic などを利用者の一時ディレクトリに展開して。KVM が使えないので TCG で): 上の引数で QEMU が `-daemonize` して pid を書き、SSH と RDP の転送を 127.0.0.1 で待ち受けた。OVMF は virtio のディスク(Boot0003 "UEFI Misc Device")を先に、DVD(Boot0002)を後に試した。プロセスの名前(`/proc/<pid>/comm`)は `qemu-system-x86`
- 2026-10-28、core に `vm: true` で just update したあと: 利用者は kvm に入ったが(`/etc/group`)、動いているセッションには効かず、`sg` がなかった。26.04 では `sg`・`newgrp` が `util-linux-extra`(2.41.3。util-linux の newgrp で、`sg <グループ> [[-c] <コマンド>]` の形も受け付ける)に分かれていて、Desktop の既定では入っていない(`login` は 1:4.16.0-2+really2.41.3)。66-vm.sh で一緒に入れる
- QEMU の user モードのネットワークも 10.0.2.0/24 なので、試験用の env.yaml の `lan_cidrs` は VirtualBox と同じでよい
- 1 回目の vm-test では、入れた直後の verify-rdp だけが接続で止まった。FreeRDP は Docker(in-ubuntu.sh)の中で動き、手元の 127.0.0.1 を `host.docker.internal` で見ていたが、Linux の rootless Docker(29.9.2)にはこの名前がない(`--add-host host.docker.internal:host-gateway` でも手元の 127.0.0.1 の転送には届かなかった)。`--network host` では届いたので、手元が Linux なら in-ubuntu.sh が `--network host` で動かし、rdp-auth.sh は名前が引けるときだけ置き換える。`vm-test.sh` には実行の権限がなく(Windows の Git Bash では要らない)、Linux の just からは 126 で止まったので付けた
- 2026-10-28、core(QEMU/KVM。CPU 2、メモリ 4GB、利用者 2 人の env)で `just vm-test`(道具 ae54f66)が 9 項目すべて通った。ISO から起動して利用者 2 人の RDP が待ち受け、`just verify` が終わるまで約 26 分(VirtualBox の CPU 1 では 47〜67 分)。`just verify` は入れた直後・電源を切ったあとともに 210 項目、verify-rdp は 2 人とも 3 回、alice の gnome-shell を落とすと alice だけ新しいセッション(4 → 17)になり bob の gnome-shell は続いた。UEFI は空の virtio のディスクを飛ばして DVD から起動し、インストーラーの再起動のあとはディスクから起動した。動いている利用者のセッションでは `sg kvm` で実行しなおして動いた(環境変数も引き継いだ)
- 未確認: 関数に寄せた VirtualBox の版(Windows で回しなおすまで)

### 構成リポジトリの鍵をなくしたときの回復(2026-10-28、Windows の構成リポジトリで確認、#34)

- 構成リポジトリで、`.sops.yaml` の受け手の age の鍵が 1 つだけで、その秘密鍵がどこにもなく、誰も復号できなくなった。sysadmin の SSH の鍵も 1 つだけで、その秘密鍵が手元になく、`just update` が `Permission denied (publickey)` で止まった。どちらも 1 本だけにしていたことが原因なので、docs/fleet.md の 3 で回復用の鍵を足すことにし、戻し方を 10 に書いた
- 戻したこと: 暗号化した値を `CHANGE_ME` にして(`sops:` の節を消し、`ENC[...]` を置き換える)新しい鍵で暗号化しなおし、`sops edit` で値を入れ直した。暗号化していない値とコメントは残った。SSH は、利用者として RDP で入り、`su - sysadmin` で `~/.ssh/authorized_keys` に鍵を足してから `just update` した
- sops 3.13.3(Windows、Scoop)は、`SOPS_AGE_KEY_FILE` を渡しても、既定の置き場所(`%AppData%\sops\age\keys.txt`)の鍵も読む。関係のない鍵だけを `SOPS_AGE_KEY_FILE` に渡しても、手元の鍵で復号できてしまった。`APPDATA` と `XDG_CONFIG_HOME` を空のディレクトリに向けると、渡した鍵だけを使った(関係のない鍵では失敗し、受け手の鍵では通った)。これを `just check-age-key`(ひな形の justfile)にした。macOS の既定の置き場所(`~/Library/Application Support`)でも効くかは未確認
- sops の MAC は、暗号化していない値も含めたファイル全体にかかる。暗号化したファイルの、暗号化していない値(`git_user_name`)をエディターで直接書き換えると、`MAC mismatch` で復号できなくなった
- Windows の sops は、規則と照らすパスを `\` で区切る。ひな形の `path_regex` が `/` だけを見ていたので、`hosts/<ホスト>.yaml` が `no matching creation rules found` で暗号化できなかった(#34)。`[/\\]` にすると暗号化と復号が通った(同じ PC で確認)。Linux・macOS では `/` だけなので、今までどおり当たる見込み(試験で `/` と `\` の両方の形を確かめる)
- `with-env.sh` は、暗号化していないファイルをそのまま写していたので、暗号化に失敗したことに `just check` で気づけなかった。`encrypted_regex` と同じ名前の値が空でなければ止め、行の番号だけを出す(値は出さない)ようにした。sops がないときも、`sops: command not found` ではなく、入れ方の案内を出す
- 道具のレシピは `tool/` で動くので、`AGENT_HOST_SSH_OPTS` の `-i` に相対パスを渡すと `tool/` から探す。絶対パスにすると、`build/` に書き出した回復用の鍵で `just status` が通った(Windows の PowerShell から、区切りを `/` にして)
- Windows で: age は Scoop の main バケットになく、winget の `FiloSottile.age`(1.3.2)で入れた。winget が足した PATH は、開いていたターミナルには効かない。`sops edit` は `EDITOR` がなく vim・nano・vi も見つからないと `no editor available` で止まり、`code --wait` で開けた
- 確かめていないこと: Linux・macOS での `check-age-key` と、sops の `path_regex` の照らし方

### 半角/全角の押しっぱなしで gnome-shell が漏れて固まる(2026-10-27、実機で確認、#36・#21)

実機(AMD Renoir、RAM 約 15GB、v0.3.1。gnome-shell 50.1、mutter 50.1、gnome-remote-desktop 50.2、ibus 1.5.34~rc2-1、ibus-mozc 2.29.5160.102)で、Orca でエージェントを動かしていると画面が操作できなくなった。

- 起きたこと: 利用者の `org.gnome.Shell@ubuntu.service` が、起動から 3 時間 6 分のあいだに最大 10.8GB(swap 7.3GB)になり、応答しなくなって(at-spi の「unresponsive」)、カーネルの OOM killer に落とされた。同じ日に 2 回(2 回目は最大 11.6GB、swap 8.2GB)。応答しなくなってから落ちるまで、1 回目は約 40 分、2 回目は約 20 分。2 回目の gnome-shell では、膨らんだのは `[heap]`(malloc)で、Xwayland などほかのプロセスではなかった(1 回目は記録がない)
- systemd-oomd は止めなかった。user@ の設定は、圧迫が 50% を 20 秒続いたら止める(`ManagedOOMMemoryPressure=kill`)で、swap の量では見ない(`oomctl` の Swap Monitored CGroups が空)。18:44 の `oomctl` では、この利用者の user@ は Memory Pressure Monitored CGroups に入っていたが、21 時台には外れていた(ユニットの設定は変わらない)。いつ・なぜ外れたのか、落ちた 2 回の時点で見られていたのかは分からない(調べていない)
- 原因: RDP(Windows の mstsc、日本語キーボード)の半角/全角キーが、IBus に「離す → 押す」の順で届く(keyval 0xFF2A `Zenkaku_Hankaku`、keycode 41。dbus-monitor で IBus のバスを盗み聞きして確認)。ホストは押されたままと受け取り、キーリピート(既定の delay 500ms、interval 30ms)で 1 秒に 22〜34 回押し続ける。ほかのキー(Shift など)を押すまで止まらない。そのたびに IBus の Mozc が入力モードを切り替え、入力モードの表示の更新(`UpdateProperty`)が gnome-shell に流れ、流れているあいだに gnome-shell が漏れた。同じくらい流れても、漏れの速さは時間帯で 1 桁以上違った(約 8900 回/分で +430MB/分のときと、約 8300 回/分で 25 秒に +6MB のとき。理由は調べていない)。1 回の更新は IBus のバスに 3 通(engine の signal と panel への 2 つ)流れるので、バスの通の数(1 分に UpdateProperty 26670、PropertyUpdated 17767)の約 3 分の 1 が更新の回数。ibus-daemon の CPU は 40〜50%
- 確かめたこと: ibus を止める(`systemctl --user stop org.freedesktop.IBus.session.GNOME.service`)と、漏れが止まった(止める直前の gnome-shell の CPU は 118%。止めたあとの CPU は記録がない)。ibus を起動しなおした直後は、半角/全角を押すまで漏れない
- 漏れたあとの症状: 漏れた gnome-shell(約 2.8GB)は、本体のスレッドが 11 秒ごとに約 0.6 秒止まった(D-Bus でシェルのプロパティを 50ms ごとに読んで測った。`org.freedesktop.DBus.Peer.Ping` は GDBus が裏のスレッドで答えるので、これでは測れない)。止まっているあいだに届いた「離した」が待たされ、mutter の入力のスレッドがリピートを出すので、押していないのに長押しの扱いになった(4 分半で、「離した」が約 0.6〜1.0 秒遅れてまとめて届いたのが 6 回で、どれも 11 秒の倍数の時刻。押していない文字が増えたのは、そのうちの 4 回)。セッションを立てなおした gnome-shell(88MB、RDP 接続中)では、60 秒のあいだ 0.16 秒を超える止まりはなかった(その場で見ただけで、記録は残していない)。漏れと止まり、止まりと長押しは、周期が合うことから見た相関で、同じ時間に測って突き合わせてはいない。「離した」がどこで待たされるかと、止まりの中身(ゴミ集めか)は調べていない
- 根: RDP の入力のキーのリピートは、ホストの mutter が自分のタイマーで作る(mutter 50.1 の `meta_seat_impl_notify_key_in_impl` は、仮想の入力機器からの繰り返しの押下を捨てる。ホストのリピートを切ると、押し続けても 1 文字しか入らなかった)。そのため「離した」が遅れたり来なかったりすると、押していない文字が増える。ホストに届く半角/全角は「離す → 押す」の順で、物理的に離したときには何も届かない(Windows がそう送るのか、途中で変わるのかは区別していない。walbrix の記事は、Windows の RDP では「release-only → press → release」で届くと書き、gnome-remote-desktop にパッチを当てて回避している。GNOME/gnome-remote-desktop#234。ブラウザの Apache Guacamole にも、半角/全角の keyup と keydown がそろわない報告がある。GUACAMOLE-1004)。そこに gnome-shell の漏れ(IBus の表示の更新のたび)が重なって固まった
- 取り違えたこと: はじめは「Orca の端末の出力で漏れる」「日本語を入力すると漏れる」と見たが、どちらも、そのとき利用者が半角/全角を押していたのと重なっていた
- 効かなかったこと:
  - RDP の解像度の変更(RHEL-148314 に似た報告がある)は当てはまらなかった。このクライアントでは窓の大きさを変えても仮想モニターの解像度が変わらず、メモリも増えなかった
  - ホストのキーリピートを全部切る(`org.gnome.desktop.peripherals.keyboard repeat false`)と、半角/全角は 1 組だけになった。ただ、RDP のクライアントは自分でリピートを送らないので、キーを押し続けても 1 文字しか入らない
  - 半角/全角キーだけリピートさせない XKB の定義(`~/.config/xkb` に `key <HZTG> { repeat = False };` と、それを足す rules と xkb-options)は、libxkbcommon では効いた(`xkb_keymap_key_repeats` が 0)。gnome-shell もそのファイルを読んだが、リピートは止まらなかった。mutter 50.1 の `meta_seat_impl_notify_key_in_impl` はこの関数を見てからリピートを始めるので、効かない理由は分からない(調べていない)
  - 始まったリピートは、キーリピートの設定を切っても止まらない
- 替えたもの: fcitx5 5.1.19 と fcitx5-mozc 2.29(Ubuntu の公式パッケージ)を、sudo なしで `apt-get download` と `dpkg -x` で利用者の一時ディレクトリに展開して動かした(ibus を止め、`FCITX_ADDON_DIRS`・`LD_LIBRARY_PATH`・`XDG_DATA_DIRS` を向けた)。fcitx5 の ibusfrontend は、IBus の口をセッションのバスに出し、`~/.config/ibus/bus/` のアドレスを書き換える。gnome-shell はそこにつなぎなおし、Orca(Electron の Wayland)で Mozc の変換ができた。同じ半角/全角のリピート(1 秒に約 34 回、約 20 秒)で、流れるのはキーの入力(ProcessKeyEvent)だけで、gnome-shell は +2MB だった
- 作り(76-desktop.sh、first-login.sh、desktop-env.sh): ibus-mozc を消し、fcitx5・fcitx5-mozc・GTK3/GTK4 の口を `--no-install-recommends` で入れる(Recommends は Qt6・KDE のライブラリ・中国語の辞書まで約 60 個。入れなければ 13 個)。IBus のユニットは `systemctl --global mask` で全員止め、ibus と同じ並びの `agent-host-fcitx5.service`(user)でセッションごとに fcitx5 を起動する。GNOME の Wayland では im-config が入力メソッドを起動しない(`/etc/profile.d/im-config_wayland.sh` が `if false` で止めている)。GNOME の入力ソースは配列だけにし、Ctrl+Space を GNOME の切り替えから外して fcitx5 に渡す。fcitx5 の profile(配列と Mozc)は、ないときだけ置く
- 残ること: 半角/全角のリピートそのものは mutter と RDP の側なので残る。fcitx5 では漏れないが、既定の割り当て(TriggerKeys に半角/全角)では押しっぱなしのあいだ日本語と英字を行き来し続けた(fcitx5 の表示が ja と あ を繰り返した)
- キーの割り当て(実機で確認): fcitx5 の `~/.config/fcitx5/config` で、TriggerKeys を Ctrl+Space だけにし、半角/全角を ActivateKeys(日本語にするだけ)、無変換を DeactivateKeys(英字にするだけ)にした。リピート(2 秒に 55〜70 回)のあいだ fcitx5 の状態は日本語のまま変わらなかった(fcitx5-remote で 0.2 秒ごとに読んだ)。ただ、日本語になったあとのリピートは Mozc に届き、Mozc の割り当て(MS-IME)の半角/全角(IMEOff / IMEOn)で「全角かな」と「直接入力」を行き来した。Mozc の設定(`~/.config/mozc/config1.db`。Config を protobuf にしたもの。`session_keymap` = 41 を CUSTOM、`custom_keymap_table` = 42 に表)に、MS-IME の表(google/mozc 2.29.5160.102 の `src/data/keymap/ms-ime.tsv`)から半角/全角の 4 行を外した表を入れると、繰り返さなくなった。表は `post-install/mozc-keymap.tsv`(Mozc の BSD-3 条項ライセンスを注釈に入れた。Mozc は 1 行目と `#` の行を読み飛ばす)、組み立ては `post-install/mozc-config.py`
- 守り(20-sessions.sh): user の `org.gnome.Shell@.service` に `MemoryMax=30%`・`MemorySwapMax=512M` の drop-in を置き、膨らんだら固まる前に落として立ちなおらせる。ユニットの `OnFailure` の `org.gnome.Shell-disable-extensions.service` は、起動の途中の印(`$XDG_RUNTIME_DIR/gnome-shell-disable-extensions`)があるときだけ拡張機能を止めるので、OOM の 2 回(18:40、19:49)とログアウトで立てなおしたとき(21:16)には動かなかった(journal の「unmet condition」)。OOM のあと、ヘッドレスのセッションは数秒で立ちなおり、Orca の端末(エージェント)は残った。上限で落ちるとき(memory.max の OOM)の動きは確かめていない
- 2026-10-28、hotfix/0.3.2 で、Windows の VirtualBox の VM(メモリ 4GB、2 人の env)で `just vm-test` を流した。入れなおしから RDP の待ち受けまでと電源を切ったあとの戻りは人手なしで通ったが、sudo のパスワードを入れ違えて verify とセッションを落とす試験が動かなかった。同じ VM で `AGENT_HOST_VM_REUSE=1` でやりなおし、すべて通った(verify 213 項目、2 回とも)。gnome-shell のメモリの上限は 1167MB(4GB の 30%)で効いていた。verify で、新しく入れたときに利用者ごとの agent-host-fcitx5.service が動き、ibus-daemon が動いていないこと、入力ソースと fcitx5・Mozc の設定を確かめた
- 同じ VM に RDP で入って打つと、押していない文字が重複して入った。gnome-shell は漏れておらず(1 分で 819MB から 791MB。ピーク 941MB で上限に当たっていない。`memory.events` の max・oom は 0。PSS 584MB のうち anon 356MB、shmem 196MB)、起動しなおしもなかった。VM は CPU 1 つで load average が 2〜3 あり、「離した」が遅れて mutter がリピートを足したと見ているが、VM の中で遅れを測ってはいない(推測)。同じときの実機(CPU 6 つ、load average 0.5)では、gnome-shell の止まりは 60 秒で最大 31ms(784 回のうち 200ms を超えたのは 0)で、利用者も重複は起きていないと確かめた。入力の確かめは実機を基準にする
- Xwayland のアプリの入力: `XMODIFIERS=@im=ibus` は gnome-session が自分で入れている(`/usr/bin/gnome-session` に文字列がある)。ibus のパッケージの `/etc/xdg/Xwayland-session.d/10-ibus-x11` が Xwayland が立つたびに ibus-x11 を起動し、fcitx5 は「Failed to open xim, retrying」を出す。Orca は Wayland で動くので当たらない。X11 のアプリで入力できるかは確かめていない
- 未確認: 新しく入れたときに gnome-shell が fcitx5 につなぐこと(RDP の画面での入力)、just update で動いているセッションがその場で fcitx5 に替わること、候補の窓の位置、Xwayland のアプリでの入力(上)、fcitx5 がつなぐので Xwayland が常に起動しておくこと、gsd-keyboard が IBus の mozc-jp を足さないこと(ibus-mozc を消したあと)、上流(mutter・gnome-remote-desktop・gnome-shell)への報告

### mstsc の資格情報の画面の PIN と指紋(2026-10-27)

- 実際のホストに Windows のリモート デスクトップ接続(mstsc)でつないだとき、資格情報の画面で PIN を求められ、指紋認証も聞かれた。ホストの RDP は NLA(CredSSP)で認証し、PIN も指紋も設定していない。指紋も出たので、手元の Windows Hello のサインインが並んだものと判断した(Hello の PIN と生体認証は手元の PC のサインインで、ホストには送れない)
- 調べたこと(Microsoft Q&A の利用者どうしのやりとり。公式の文書ではない): NLA のとき mstsc は手元の資格情報の画面(CredUI)を出し、CredSSP が手元の資格情報プロバイダーを全部並べるので、Windows Hello for Business の PIN が先に出る。組織の Entra ID に参加した PC で多い。相手が Windows でない、または PIN を受け付けない RDP サーバーでは、「その他」(More choices)から別のアカウントとパスワードを選ぶしかない、というのが採用された回答
- mstsc の側で PIN を出さないようにする方法は、決め手がなかった。上のやりとりでは、次のどれも効いた人と効かなかった人がいる:「ローカル デバイスとリソース」の「スマート カードまたは Windows Hello for Business」と「WebAuthn」を外す、ユーザー名の前に `.\` を付ける、`DisableSmartCardNode`(PassportForWork のポリシー)。`ExcludeCredentialProviders` で Hello のプロバイダーを外すと、PC 自体にサインインできなくなる
- 接続ファイルに `enablecredsspsupport:i:0` を書くと NLA を使わなくなるが、gnome-remote-desktop は NLA しか受け付けないという報告がある(Red Hat Bugzilla 2189376)ので、手順書には書かない(試していない)
- 手順書には「その他」→「別のアカウントを使用する」で `rdp.username` とパスワードを入れる対処を書いた。このホストでこの対処で入れるかは未確認。日本語の Windows の表示の文言も未確認(英語は More choices / Use a different account)
- 「このアカウントを記憶する」を選んでも、次の接続でまた聞かれた。原因は未確認
  - Credential Guard(有効だと CredSSP は保存した資格情報を使えない。Microsoft の文書 Considerations and known issues)を疑ったが、手元の PC で `Win32_DeviceGuard` の `SecurityServicesRunning` が 0 で、動いていなかった。これは原因ではない
  - 次の候補(未確認): ホストの NLA は NTLM で、Kerberos でホストの身元を確かめられないため、Windows は既定では保存したパスワードを送らない。そのときは「資格情報が機能しませんでした」「リモート コンピューターの ID が完全には確認されていないため、保存された資格情報の使用を許可していません」という趣旨の表示が出るという報告がある。手元の PC のグループ ポリシー「NTLM のみのサーバー認証で保存された資格情報の委任を許可する」に `TERMSRV/<ホスト>` を足すと使えるという(管理者の権限が要り、組織の PC では組織のポリシーが優先される)
  - ただし、手元の PC では 2 回目の接続でこの表示は出ず、資格情報の画面がそのまま出た。この候補にも当てはまらない
  - 手元の PC の `cmdkey /list` に TERMSRV の項目がなかった。チェックを入れて接続しても、資格情報が保存されていない
  - 保存を止める設定ではなかった: `HKLM\SYSTEM\CurrentControlSet\Control\Lsa` の `DisableDomainCreds` が 0、リモート デスクトップの `DisablePasswordSaving` のポリシー(HKLM・HKCU)はなし
  - 手で保存すると使われた: 手元の PowerShell で `cmdkey /add:TERMSRV/<ホスト> /user:<ユーザー名> /pass` で保存してからつなぐと、資格情報の画面が出ずにつながった(接続ファイルは使わず、mstsc に接続先を打ち込んだ)。止まっているのはチェック欄からの保存のほう。チェック欄で保存されない理由は未確認。手順書にはこの `cmdkey` を回避策として書いた
- 別に見つけたこと: `just rdp` は `docs/agent-host.rdp.example` の `username:s:agent` をそのまま写していたので、`rdp.username` が agent でない利用者には、違うユーザー名が初めから入った。3 つ目の引数でユーザー名を渡すようにした(省くとユーザー名の行を消す)。PIN の件とは関係がない(試験は接続ファイルを使わずに行った)

## 確認できていないこと

実機でしか確かめられないもの、実際のアカウントやネットワークが要るものは、まだ確かめていない。

- 実機でのヘッドレスのセッション(モニターなし。RDP の解像度がつなぐ側に合うか)、BIOS の停電復帰、lan_cidrs の外から 22・利用者の RDP のポートに届かないこと(受け入れテスト 7)
- 電源のプロファイル performance(VM にはない)
- 実際の HTTP プロキシ・TLS を検査するプロキシの下での動作、独自の CA の証明書を使う Gitea への接続
- Slack への送信、Claude Code の Remote Control、Orca Mobile でのペアリング(LAN・Relay)、クラウドの CLI のログイン(SSO・ブラウザ)
- IP Messenger の名前での検索を、実機の LAN の既定のブロードキャスト(255.255.255.255)で行うこと
- RDP のクリップボードでのファイルのコピー、Zed での日本語入力
- 実際の UPS での終了、出力の停止、復電での起動(VM では NUT の dummy-ups で、通知と終了と起動しなおしまで確かめた)
- 実機の GPU で RDP の画面を符号化すること(Intel の full 版の VA-API、AMD の Mesa、NVIDIA のドライバーと NVENC。Secure Boot のときの NVIDIA)
- 利用者ごとのヘッドレスのセッションで: TPM のある機械で RDP の認証情報がどこに入るか(TPM に入るとホームの credentials.ini がなく、移行で移らない)、ヘッドレスでも GPU で符号化されるか、Clipboard Indicator が効くか(段 0 の 7)、2 人目以降の Orca Mobile のポート(段 0 の 9)、0.2 のホストから just update で上げたときの移り変わり(seat0 のセッションを終わらせてヘッドレスに移る)
- 利用者 2 人の VM で、それぞれの rootless Docker で `docker run --rm hello-world` と `docker run --rm alpine:3 wget -qO- http://example.com` が通ること、env.yaml から外した利用者の Docker が止まること、#29 で足した verify の項目が `just vm-test` で通ること(#29)
- rootless Docker のコンテナの中でメモリが詰まったとき、systemd-oomd がほかのコンテナも一緒に止めるか(Orca の端末は 1 つずつ止まることを VM で確かめた)
- 利用者が複数のとき、長く強いメモリの圧迫で、メモリを使っていない側の利用者の単位を systemd-oomd が止めることがあるか(VM の 2 人では、使った側だけが止まった)
- UPS の netclient を実際の NUT サーバーにつなぐこと。USB の HID の UPS を GNOME の upower も見て、電池が少ないときに GNOME が別の動作をしないか
- このホストの Orca を Remote Orca Server として公開し、手元の Orca からつなぐことの残り(LAN の IP で 6768 を足してつながることは確かめた。2 人目以降でポートがずれるか、手元とホストで Orca の版が違うときにつながるか、Tailscale でつなぐこと)
- Mermaid CLI: プロキシ・独自の CA の下での `npm install`、自動更新された Chrome と固定した puppeteer の版がずれたときの動作(#28)
- vm-test: 関数に寄せた VirtualBox の版の回しなおし(#35)
- 日本語入力の fcitx5: 新しく入れたときと just update のときに gnome-shell が fcitx5 につなぐこと、Xwayland のアプリでの入力、systemd-oomd がこの利用者の user@ を見なくなっていた理由(#36・#21。上の「半角/全角の押しっぱなしで gnome-shell が漏れて固まる」)
- 原因を調べていないもの: インストール中にライブ環境のログイン画面で止まって見えること、first-login の "RDP server certificate is invalid"、`localectl set-x11-keymap` の "Access denied"、RDP での Caps Lock の状態のずれ

## 運用上の注意

- Codex のログインはデバイスコード認証(`codex login --device-auth`)。ChatGPT 側の設定で事前に有効化しておかないと、エラーにならず止まって見える
- Codex の認証情報は `~/.codex/auth.json` に平文で保存される。利用者のホームは 700 にしている(sysadmin は読める)
- Orca は .deb 版なら自分では更新を適用しない(通知は出る)。apt-mark hold で固定している。上げるときは 70-orca.sh の版と SHA256 を直す
- バージョンを上げるときは、版を持つスクリプト(60-devtools.sh、62-agents.sh、63-clouds.sh、65-docker.sh、70-orca.sh、72-editors.sh、76-desktop.sh)の先頭の値を直し、手順書の付録「固定しているバージョン」も直して、`just update <ホスト>` で反映する
- build-usb.sh で作った ISO と、ターゲットの `/opt/agent-host/env.sh` と `/opt/agent-host/users/`(RDP の仮のパスワード。更新の前の一式の `/opt/agent-host.prev/` の同じものも。どれも root のみ読める)には秘密情報が入る。ほかに秘密情報が入るファイルは README の「利用上の注意」にまとめている
- デスクトップ共有とリモートログインを両方有効にすると、デスクトップ共有が 3390 番に移る。リモートログインは有効にしない
- いちばん崩れやすいのは受け入れテスト4(再起動後、何もせずに RDP がつながるか)。ここを最優先で検証する
