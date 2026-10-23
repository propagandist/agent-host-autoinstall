# agent-host-autoinstall — SPEC

社内のオンプレPCを、AIコーディングエージェント(Claude Code / Codex)を Orca(ADE)で並列稼働させる「常時稼働エージェントホスト」として自動構成するための仕様。

## 1. 目的

- USBメモリ1本から、決まった構成の Ubuntu Desktop を無人に近い形でインストールできること
- 再起動・停電復帰後も、人手を介さず Orca が起動し、RDP で接続できる状態に戻ること
- 構成をコードとして管理し、同じ環境を何台でも再現できること

## 2. 対象環境

| 項目 | 内容 |
|---|---|
| OS | Ubuntu Desktop 26.04 LTS(Wayland のみ。xrdp は使えないため不採用) |
| ハードウェア | x86_64 の物理PC。メモリ 32GB 以上、NVMe SSD 推奨 |
| 画面 | 物理モニターなし運用。HDMI ダミープラグを挿す |
| ネットワーク | 社内LAN。固定IP(または DHCP 予約) |
| 遠隔操作 | GNOME 標準リモートデスクトップの「デスクトップ共有」(RDP) |
| 管理操作 | SSH(鍵認証のみ) |

## 3. 全体の流れ

```
電源投入
  → agent ユーザーで自動ログイン
  → GNOME 起動(ログインキーリングは空パスワードなので自動で開く)
  → デスクトップ共有(RDP :3389)が待ち受け開始
  → Orca が autostart で起動
社内LANの RDP クライアント → :3389 → agent のデスクトップを操作
管理者 → SSH → sysadmin ユーザー
```

## 4. ユーザー

| ユーザー | 用途 | sudo | ログイン |
|---|---|---|---|
| `sysadmin` | OS 管理・更新 | あり | SSH 鍵認証のみ(パスワード認証は無効) |
| `agent` | Orca / Claude Code / Codex の実行 | なし | GDM 自動ログイン |

`agent` に個人の秘密情報は置かない。

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
- GDM 自動ログイン:`/etc/gdm3/custom.conf` に `AutomaticLoginEnable=true` / `AutomaticLogin=agent`
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
- SSH:パスワード認証無効、root ログイン無効
- ufw:SSH(22)と RDP(3389)を社内LANのみ許可、それ以外は拒否
- unattended-upgrades:セキュリティ更新と Google Chrome のみ、自動再起動しない
- 開発ツール:git、Node.js(LTS)、Claude Code、Codex(`@openai/codex`)、GitHub CLI(`gh`)、build-essential、python3-venv、python3-pip、ripgrep、jq、unzip
- Orca:公式 .deb を導入し、`agent` の `~/.config/autostart/orca.desktop` で自動起動
- Google Chrome:公式 apt リポジトリから導入し、`agent` の既定のブラウザにする。最新版しか配布されないので固定せず、unattended-upgrades で自動更新する
- Node.js、npm パッケージ、Claude Code、Orca、GitHub CLI はバージョンを固定する(勝手に上がらないように)

### 5.3 手作業(初回のみ。docs/manual-steps.md に手順化する)
1. BIOS:Restore on AC Power Loss を Power On に
2. `agent` のログインキーリングを空パスワードに変更
3. 設定 → システム → リモートデスクトップ → デスクトップ共有をオン、リモート操作をオン、RDP 用の認証情報を設定
4. Claude Code のログイン
5. Codex のログイン(`codex login --device-auth`。事前に ChatGPT のセキュリティ設定でデバイスコード認証を有効化)
6. Orca 初回起動、`~/.claude` / `~/.codex` 設定の取り込み、自動更新をオフ

2〜3 はスクリプト化した(2 は空パスワードのキーリングを最初から置く、3 は first-login で `grdctl` を実行する)。ただし実機では未確認なので、効かなかったときの手作業を docs/manual-steps.md に残す。

## 6. 非機能要件
- スクリプトは冪等(何度流しても同じ結果)
- リポジトリに秘密情報を含めない(パスワードハッシュ・SSH 公開鍵・IP 範囲などの環境固有値は別ファイルに分離し、サンプルのみコミット)
- 構成変更は OS 再インストールなしで適用できる形を目指す(後で Ansible 化しやすいように、late-commands からは同梱スクリプトを呼ぶだけにする)

## 7. 受け入れテスト
1. USB からインストール → 手作業なしで完了する
2. 手作業(§5.3)を実施
3. 電源ケーブルを抜き差し → 自動で起動する
4. 何も操作せず、手元PCから RDP 接続 → Orca 起動済みの画面が出る
5. Orca から Claude Code / Codex でそれぞれ簡単なタスクを1本ずつ実行できる
6. RDP 切断 → 10分後に再接続 → タスクが継続している
7. 社内LAN外(または許可範囲外)から 22 / 3389 に到達できない

## 8. 設計上の決定と理由

| 決定 | 理由 |
|---|---|
| Ubuntu Desktop 26.04 LTS | 常時稼働でもGUIが必要。Server + デスクトップ追加より手直しが少ない |
| xrdp ではなく GNOME デスクトップ共有 | 26.04 では xrdp が使えない。物理セッション共有なので、自動ログイン + Orca 自動起動と両立し、再起動後も人手不要 |
| 「リモートログイン」モードは使わない | 再起動後にログインするまでOrcaが動かない。併用するとデスクトップ共有が3390番に移り混乱する |
| `agent` のキーリングを空パスワードに | 自動ログインではキーリングが開かず、デスクトップ共有の認証情報が読めないため。`agent` は専用ユーザーで秘密情報を置かない前提で許容 |
| HDMI ダミープラグ | モニターなしだと描画されない機種がある |
| ディスク暗号化はオプション | 使うなら TPM 連動の暗号化(パスフレーズなしで無人再起動できる)。パスフレーズ方式は無人復帰と両立しない |
| 社外からは VPN 経由 | 3389 をインターネットに開けない |

## 9. 未確定事項(実装時に確認)

調べた結果と、まだ確認できていない点は HANDOVER.md「§9 の調査結果」に書く。
- Ubuntu Desktop 26.04 の autoinstall で、上記要件がすべて表現できるか(Server 版との差分)
- 26.04 で「自動ログイン + 空パスワードキーリング + デスクトップ共有」が再起動後に確実に有効になるか
- デスクトップ共有の有効化と RDP 認証情報の設定を `grdctl` でスクリプト化できるか
- Orca .deb の入手 URL とバージョン固定・自動更新停止の方法
- Claude Code の Linux 上での推奨インストール方法(npm かネイティブインストーラーか)
- 社外アクセスの VPN 方式(社内既定の方針に合わせる)

## 10. 対象外
- Orca / Claude Code / Codex の利用ルールやアカウント管理
- 複数台の一括展開(PXE、MAAS 等)
- Ansible 化(将来課題。スクリプト構成はそれを妨げないようにする)
