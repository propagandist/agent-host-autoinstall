# agent-host-autoinstall

AI コーディングエージェントを動かし続ける専用の Ubuntu Desktop を、USB メモリ 1本から自動で構成する設定とスクリプト。

## これは何か

物理 PC を、Claude Code や Codex を Orca(複数のエージェントを並べて動かす開発環境)で常時動かす「エージェントのホスト」にするための一式です。
Ubuntu Desktop 26.04 LTS の autoinstall で、USB から確認なしでインストールし、初回の起動で構成まで終えます。
再起動や GNOME のセッションの異常終了のあとも、人手を介さずに RDP(GNOME のデスクトップ共有)で接続できる状態に戻ります。
日本語の環境向けです(ロケール ja_JP.UTF-8、タイムゾーン Asia/Tokyo、日本語入力 Mozc。文書も日本語)。
VirtualBox の仮想マシンで、無人インストールから RDP の接続と受け入れテストまで確かめました。実機ではまだ確かめていない点があり、[docs/notes.md](docs/notes.md) の「確認できていないこと」にまとめています。

## なぜ作ったか

コーディングエージェントは、1 つの作業に数十分から数時間かかり、確認なしで動かすことも多くあります。いくつも並べて任せると、手元の PC では無理が出ます。

- エージェントが動いているあいだ、手元の PC を閉じたり持ち出したりできない
- Orca で、Claude Code や Codex を worktree ごとに並べて見比べたい。その画面を、どの PC やスマホからでも見たい
- 確認なしで動くエージェントに、私的なファイルや個人のログイン情報がある PC を触らせたくない

そこで、Orca を動かし続ける専用の PC を置き、sudo のない専用のユーザーでエージェントを動かします。専用の PC を置くなら、次の 2 つが欲しくなります。

- 1台目を手で作ると、2台目や入れなおしのときに同じものを作れない → **USB メモリ 1本から同じ構成を再現する**
- 再起動やセッションの異常終了のあと、誰かがログインするまで使えないと、離れた場所からは何もできない → **人手なしで RDP に戻る**

そのために選んだもの、選ばなかったものと理由です(詳しくは [docs/SPEC.md](docs/SPEC.md) §8 と [docs/notes.md](docs/notes.md))。

| 選んだもの | 選ばなかったもの | 理由 |
|---|---|---|
| Orca(複数のエージェントを worktree ごとに並べる GUI) | Emdash、Nimbalyst、Superset、Warp、Conductor、Claude Squad などの TUI | Linux の .deb があり、Claude Code と Codex の両方を使え、MIT で、アカウントなしで使え、自分では更新を適用せず版を固定でき、利用統計を止められ、開発がいちばん活発だった。ほかは Mac 専用・Linux が実験的・開発の終了・更新の確認や利用統計を止められない、のどれかに当たった(2026-10-24 の比較。docs/notes.md)。端末だけで使える予備に CCManager も入れる |
| Ubuntu の Desktop 版 | Server 版 | エージェントの作業を並べて見る GUI(Orca)を使うため。autoinstall は Desktop 版でも使える |
| GNOME のデスクトップ共有 | xrdp、GNOME のリモートログイン | Ubuntu 26.04 は Wayland だけで xrdp が使えない。リモートログインは別のセッションを作るので、再起動のあとに自動で起動した Orca が見えない |
| 空パスワードのログインキーリング | 自動ログインのたびに手でキーリングを開く | 自動ログインではキーリングが開かず、デスクトップ共有の認証情報が読めない(upstream で未解決)。安全性と引き換えの妥協で、下の前提があるときだけ許す |
| 1分ごとの見張りで GDM を再起動 | GDM の `TimedLogin` | 自動ログインは起動時の 1回だけ。`TimedLogin` は、エージェント用のユーザーがログイン画面の一覧に出ないため機能しなかった |
| sudo のない専用ユーザーと rootless Docker | `docker` グループ | `docker` グループに入れると実質 root と同じになる |
| ホームはローカルのディスク | ホームを NFS に置く | NFS が見えないと自動ログインが失敗する。rootless Docker の置き場や、各ツールの SQLite が NFS の上では崩れる |

## 使い方

### 必要なもの

- 入れる先の PC: x86_64、メモリ 32GB 以上を推奨、有線 LAN、HDMI のダミープラグ(モニターなしで描画させるため)
- 手元の PC: [just](https://just.systems/) と、次のどちらか
  - Docker(Linux の道具を Docker の Ubuntu の中で動かす。Windows では Git Bash と Docker Desktop)
  - Linux なら `xorriso`・`python3-yaml`・`shellcheck`
- 8GB 以上の USB メモリと、ISO をそのまま書き込む道具(Windows なら Rufus の DD イメージのモード、Linux なら `dd` など)

> [!CAUTION]
> この USB から起動すると、**確認なしでディスク全体を消してインストールが始まります**。入れる先以外の PC に挿したまま起動しないでください。作った ISO と USB には、パスワードのハッシュや RDP のパスワードが入ります。使い終わったら消してください。

### 最短の手順

```
git clone https://github.com/propagandist/agent-host-autoinstall.git
cd agent-host-autoinstall
cp autoinstall/env.example.yaml autoinstall/env.yaml   # ホスト名、ネットワーク、公開鍵、RDP の認証情報などを書く
just check-env          # env.yaml を検査する(値の形、書き忘れ、知らないキー)
just fetch-iso          # Ubuntu の ISO を取得して SHA256 を照合する
just iso                # build/agent-host.iso を作る → USB に書き込む
# 入れる先の PC を USB から起動 → 確認なしでインストール → 初回の起動で構成 → 自動ログイン
just status <ホスト>    # 作った版、構成、RDP、セッションの状態を見る
just rdp <ホスト>       # RDP の接続ファイルを作る
```

インストールのあとに手で行うのは、主に各サービスへのログインです(Claude Code、Codex、GitHub など)。設定を変えたときは、OS を入れなおさずに `just update <ホスト>` で反映できます。`just` だけを打つと、レシピの一覧が出ます。

### 利用上の注意

この構成は、利便性と引き換えに安全性を下げている部分があります。次の注意を読み、自分の環境と組織の規程に合うかを判断したうえで使ってください。まずは仮想マシンで試すことを勧めます。

**守る前提**

- **LAN の中だけで使う。** SSH(22)と RDP(3389)は、`env.yaml` の `lan_cidrs` の範囲だけに許可します。インターネットには開けず、LAN の外からは VPN などを通します
- **PC は、関係者だけが触れる場所に置く。** 自動ログインのため、画面のロックとアイドルによるロックを止めています。モニターやキーボードをつなげば、誰でもエージェント用のユーザー `agent` のデスクトップを操作できます
- **`agent` に置く秘密は、各サービスのログインの情報だけにする。** `agent` のログインキーリングは空パスワードで、ディスクも暗号化しません。PC やディスクを持ち出されれば中身を読まれます

**知っておくこと**

- **エージェントは確認なしで動きます。** Orca は確認なしでコマンドを実行するモードが最初からオンです。`agent` に sudo は渡しませんが、作業のディレクトリのファイルの削除、ログイン済みのサービスへの push や送信、API の利用料の発生は起こりえます
- **コードとデータは外部のサービスに送られます。** Claude Code や Codex などは、扱うコードを各社のサービスに送ります。その情報を送ってよいかは、利用者が組織の規程や契約で確かめてください
- **版を固定したソフトには、セキュリティ更新が自動では入りません。** apt で hold したもの(Claude Code、Docker、GitHub CLI、Orca、VS Code、クラウドの CLI)と、Node.js や npm で入れたツールは、利用者が版を上げて反映します(手順は手順書の「運用」)。OS のセキュリティ更新と Google Chrome は自動で入ります
- **ほかのソフトとサービスの規約・ライセンスは、利用者が同意するものです。** このリポジトリはそれらを再配布せず、インストールのときに各社の配布元から取得します(Google Chrome、VS Code とその拡張機能、各エージェント、クラウドの CLI など)。契約が要るものもあります(GitHub Copilot など)
- **止められない通信があります。** 利用状況の送信は止めていますが、すべてではありません。たとえば Orca の更新の確認は止める手段がありません
- **秘密情報が入るファイルがあります。** 作った ISO と USB、`env.yaml`、移行の書き出し、ホストの `/opt/agent-host/env.sh` です。IP Messenger の通知は暗号化されないので、本文に秘密を入れないでください
- **実機ではまだ確かめていない点があります**([docs/notes.md](docs/notes.md) の「確認できていないこと」)

### 文書

| 文書 | 内容 |
|---|---|
| 詳細な設定手順書(PDF) | 準備から運用まで。[Releases](https://github.com/propagandist/agent-host-autoinstall/releases) から取得できる(原稿は [docs/setup-guide.tex](docs/setup-guide.tex)、`just guide` で作れる) |
| [docs/manual-steps.md](docs/manual-steps.md) | USB の作り方と、インストールのあとの手作業 |
| [docs/acceptance-test.md](docs/acceptance-test.md) | 受け入れテスト |
| [docs/fleet.md](docs/fleet.md) | 2台目からの管理(ホストごとの設定を別の非公開リポジトリで持つ。ひな形は [examples/fleet/](examples/fleet/)) |
| [docs/SPEC.md](docs/SPEC.md) | 仕様(目的、要件、設計上の決定) |
| [docs/notes.md](docs/notes.md) | 技術メモ(検証した環境、調査と検証の記録、確認できていないこと) |
| [docs/release.md](docs/release.md)・[CHANGELOG.md](CHANGELOG.md) | リリースの手順と変更の記録 |

## 技術スタック

- Ubuntu Desktop 26.04 LTS の autoinstall(subiquity)と、ISO の作り直しに xorriso
- 構成のスクリプトは Bash、`env.yaml` の検査と変換は Python
- 手元の作業は [just](https://just.systems/)。Linux の道具は Docker の中でも動く
- GDM の自動ログイン、GNOME Remote Desktop(`grdctl`)、systemd のサービスとタイマー、ufw、rootless Docker
- 秘密情報の管理(2台目から)は SOPS と age
- 手順書は LuaLaTeX(Docker の TeX Live)、リリースは GitHub Actions

## ライセンス / 位置づけ

[Apache License 2.0](LICENSE) です。著作権者の表示は [NOTICE](NOTICE) にあります。

**無保証で提供します。利用は自己責任でお願いします。** このリポジトリの設定やスクリプト、文書を使ったことで生じたデータの消失、セキュリティ上の問題、費用その他の損害について、作成者は責任を負いません(Apache License 2.0 の第 7 条・第 8 条)。上の「利用上の注意」を読み、必要なら仮想マシンや検証用の PC で試してから使ってください。

PROPAGANDIST が、自分たちでエージェントのホストを用意するために作り、公開している OSS です。Claude Code と一緒に開発しています(作業のルールは [CLAUDE.md](CLAUDE.md))。

Ubuntu、Canonical、Anthropic、OpenAI、GitHub、Google、Microsoft ほか、このリポジトリで名前を挙げたソフトやサービスの提供元とは関係がなく、承認も受けていません。記載の会社名・製品名は、各社の商標または登録商標です。

Issue / PR は受け付けますが、対応は保証しません。
