# 変更の記録

版は [Semantic Versioning](https://semver.org/lang/ja/) で付ける。
パッチは固定したバージョンの更新と修正、マイナーは機能や env.yaml の項目の追加、
メジャーは env.yaml の互換性がなくなる変更(既存の env.yaml を直さないと ISO を作れない変更)。
リリースは実機での受け入れテストが通ってから出す。しばらく運用して問題がないと判断するまでは 0.x とする。手順は [docs/release.md](docs/release.md)。

## [未リリース]

### 追加
- Ubuntu Desktop 26.04 LTS の autoinstall で、USB メモリ 1 本から無人でインストールし、初回起動時に構成する
- GDM の自動ログイン、空パスワードのキーリング、GNOME のデスクトップ共有(RDP)を、再起動・停電のあとも人手なしで戻す。セッションが落ちたら GDM を再起動する見張り
- SSH は鍵認証のみ、agent は SFTP 専用。ufw で社内 LAN だけに許可
- Orca、Claude Code、Codex、CCManager、GitHub CLI、Gitea CLI、Node.js、uv、mise、rootless Docker、Google Chrome。追加のエージェント(OpenCode、Copilot CLI、Antigravity CLI)とエディター(VS Code、Neovim、Zed)は env.yaml で選ぶ
- env.yaml で、キーボード配列、ネットワーク(DHCP・固定 IP)、プロキシと CA 証明書、NTP、壁紙の色、開発用のポート、社内の Gitea の URL を指定する
- 日本語入力(Mozc、Ctrl+Space)、Xfce Terminal、Clipboard Indicator、スクリーンショットのキー、英語のフォルダー名
- 要らないサービス・snap・kdump を止めて最小化。zram、電源のプロファイル
- 承認待ち・エラー・完了を Slack と IP Messenger(名前で探す)に通知。ディスクの残りの監視
- 環境を入れ替えるときの書き出しと取り込み(agent-host-backup、agent-host-restore)
- 手元の作業をまとめた justfile(ISO の作成、検査、状態・記録・更新・移行、RDP の接続ファイル、手順書の PDF)
- 詳細な設定手順書(docs/setup-guide.tex)。表紙、色付きの囲み、図、チェックリスト付きの PDF を Docker の TeX Live で作る
- リリースの手順(docs/release.md)と、タグの push で手順書の PDF を GitHub Release に付けるワークフロー

### 確認した環境
- VirtualBox 7.2(Windows 10、UEFI、CPU 1、メモリ 4GB)で、無人インストールから RDP の接続、受け入れテスト 1〜6・8
- 実機は未確認(ダミープラグでの RDP、停電復帰、社内 LAN の外から届かないこと、プロキシ、Slack、Zed)
