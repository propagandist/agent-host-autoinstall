# 変更の記録

版は [Semantic Versioning](https://semver.org/lang/ja/) で付ける。
パッチは固定したバージョンの更新と修正、マイナーは機能や env.yaml の項目の追加、
メジャーは env.yaml の互換性がなくなる変更(既存の env.yaml を直さないと ISO を作れない変更)。
リリースは VM での受け入れテストが通ったら出す(実機での確認は必須にしない)。実機で問題が出たら hotfix(パッチの版)で直す。しばらく運用して問題がないと判断するまでは 0.x とする。手順は [docs/release.md](docs/release.md)。

各版の「env.yaml の変更」には、構成リポジトリ(docs/fleet.md)で道具の版を上げるときに、各ホストの env.yaml で直すことを書く
(項目の追加・名前の変更・使えなくなった値。なければ「なし」)。

## [未リリース]

### env.yaml の変更
- `ups` を足した(UPS を NUT で見る。書かなければ使わない。項目は autoinstall/env.example.yaml)

### 追加
- 機械で確かめる仕組み(docs/acceptance-test.md「機械で確かめる」)
  - `just test`: env.yaml の検査(知らないキー、SOPS のまま、書き忘れ、値の形、組み合わせ)、重ね方、env.sh と /opt/agent-host に置くものの形の試験(tests/)
  - `just verify <ホスト>`: ホストが仕様どおりかを約 100 項目で確かめる(読むだけ)。固定した版は、そのホストの post-install/ の値と比べる。ホストの上では `sudo /opt/agent-host/verify.sh`
  - `just verify-rdp <ホスト>[:ポート]`: env.yaml の rdp で RDP の認証(NLA)が通るか(FreeRDP の +auth-only。画面は開かない)
  - `just vm-test`: VirtualBox の VM に入れなおし、検査、電源を切ったあと、セッションが落ちたあとの戻りを通しで確かめる
- `just release-check` で `just test` も行う
- UPS への対応(env.yaml の ups、85-ups.sh): NUT で UPS を見て、バッテリーが少なくなったら(か NUT サーバーの指示で)正しく終了する。USB でつないだときは終了の最後に UPS の出力を止め、電源が戻ったら BIOS の設定で起動させる。停電・復電・まもなく終了を agent-notify で知らせる。just verify に「UPS」の確認

- RDP の画面の符号化を GPU に任せる(37-gpu.sh): Intel は VA-API の full 版(intel-media-va-driver-non-free)、Vulkan のドライバー、vainfo。NVIDIA は autoinstall の drivers でプロプライエタリ ドライバーをインストールの中で入れる。just verify に「GPU」の確認

### 変更
- リリースのワークフローの actions/checkout を v5 にした(Node.js 20 の廃止の警告への対応)
- Intel の VA-API を free 版から full 版にした(36-minimize.sh から 37-gpu.sh に移した)。動いているホストは just update で入れ替わる。NVIDIA の GPU があるホストでドライバーが無ければ、構成の記録に注意が出る(sudo ubuntu-drivers install のあとに再起動)

## [0.1.0] - 2026-10-24 — 最初の版

### env.yaml の変更
- 最初の版なので、なし(項目は autoinstall/env.example.yaml)

### 追加
- Ubuntu Desktop 26.04 LTS の autoinstall で、USB メモリ 1 本から無人でインストールし、初回起動時に構成する
- GDM の自動ログイン、空パスワードのキーリング、GNOME のデスクトップ共有(RDP)を、再起動のあとも人手なしで戻す。セッションが落ちたら GDM を再起動する見張り
- SSH は鍵認証のみ、agent は SFTP 専用。ufw で LAN だけに許可
- Orca、Claude Code、Codex、CCManager、GitHub CLI、Gitea CLI、Node.js、uv、mise、rootless Docker、Google Chrome。追加のエージェント(OpenCode、Copilot CLI、Antigravity CLI)とエディター(VS Code、Neovim、Zed)は env.yaml で選ぶ
- クラウドの CLI(AWS CLI v2、Google Cloud CLI、Azure CLI)を env.yaml の clouds で選んで入れる
- VS Code の拡張機能を版を固定して入れる(基本、Python・JavaScript、GitHub Pull Requests、clouds に合わせたクラウド)。env.yaml の vscode_extensions で足せる。表示は日本語にする
- Zed の拡張機能を初めて起動したときに入れる(TOML、Docker、HTML、Make、SQL ほか)。env.yaml の zed_extensions で足せる
- env.yaml で、キーボード配列、ネットワーク(DHCP・固定 IP)、プロキシと CA 証明書、NTP、壁紙の色、開発用のポート、Gitea の URL を指定する
- 日本語入力(Mozc、Ctrl+Space)、Xfce Terminal、Clipboard Indicator、スクリーンショットのキー、英語のフォルダー名
- 要らないサービスを止め、snap・snapd・kdump と使わないパッケージ(画面の読み上げ、印刷のドライバー、AD・LDAP、VPN・モデム、Bluetooth、報告など)を消して最小化。zram、電源のプロファイル
- 承認待ち・エラー・完了を Slack と IP Messenger(名前で探す)に通知。ディスクの残りの監視
- 環境を入れ替えるときの書き出しと取り込み(agent-host-backup、agent-host-restore)
- 実機の構成を別のリポジトリで管理するための仕組み(docs/fleet.md、ひな形 examples/fleet/)。env.yaml を重ねて使う(共通 + ホスト)、知らないキーをエラーにする、リポジトリの外の env.yaml を扱う、作った版をホストの BUILD-INFO に残して just status に出す、台帳のための just facts
- ライセンスは Apache License 2.0(著作権者の表示は NOTICE)
- 手元の作業をまとめた justfile(ISO の作成、検査、状態・記録・更新・移行、RDP の接続ファイル、手順書の PDF)
- 技術メモ(docs/notes.md): 検証した環境、設計で決めたこと、調査と検証の記録、確認できていないこと
- 詳細な設定手順書(docs/setup-guide.tex)。表紙、色付きの囲み、図、チェックリスト付きの PDF を Docker の TeX Live で作る
- リリースの手順(docs/release.md)と、タグの push で手順書の PDF を GitHub Release に付けるワークフロー

### 確認した環境
- VirtualBox 7.2 の VM(UEFI、メモリ 4GB。Windows のホストで Hyper-V と共存させたため CPU 1)で、release/0.1.0 の ISO から新しく入れなおし、無人インストールから RDP の接続まで。受け入れテスト 1〜6・8 はこれまでの VM で確かめた(docs/notes.md)
- 実機は未確認(ダミープラグでの RDP、停電復帰、LAN の外から届かないこと、プロキシ、Slack、クラウドへのログイン、Zed での日本語入力)。問題が出たら hotfix で直す
