# agent-host-autoinstall

手元に置く物理 PC を、常時稼働の AI エージェントホスト(Ubuntu Desktop 26.04 LTS + Orca + Claude Code + Codex + GNOME デスクトップ共有)として、autoinstall で自動構成するための設定とスクリプト一式。
USBメモリ1本から同じ構成を再現でき、再起動やセッションの異常終了のあとも、人手を介さず RDP で接続できる状態に戻ることを目指す。

日本語の環境向け(ロケール ja_JP.UTF-8、タイムゾーン Asia/Tokyo、日本語入力 Mozc。文書も日本語)。

## できること

- USB メモリ 1 本から無人でインストールし、初回起動時に構成する。env.yaml で、ネットワーク、プロキシと CA 証明書、キーボード配列などを指定する
- GDM の自動ログインと GNOME のデスクトップ共有(RDP)。再起動やセッションの異常終了のあとも、人手なしで RDP に戻る(電源が戻ったときの起動は BIOS の設定で行う)
- AI エージェント: Orca、Claude Code、Codex、CCManager。選んで OpenCode、GitHub Copilot CLI、Antigravity CLI
- 開発の道具: Node.js、uv、mise、rootless Docker、GitHub CLI、Gitea CLI、Google Chrome。選んで VS Code(拡張機能と日本語の表示も)、Neovim、Zed(拡張機能も)、AWS・Google Cloud・Azure の CLI
- 承認待ち・エラー・完了を Slack と IP Messenger に通知する。ディスクの残りを監視する
- 版の固定、要らないサービスの停止、`just update` での設定の反映、`just backup` / `just restore` での移行
- 詳細な設定手順書の PDF を、リリースごとに GitHub の Releases に付ける
- 実機の構成を別のリポジトリで管理できる: env.yaml を重ねて使う(共通 + ホスト)、書き間違いを検出する、作った版をホストに残す、台帳のための情報を出す

## 現状

VirtualBox の仮想マシンで、無人インストールから RDP の接続と受け入れテストまで確かめた。実機ではまだ確かめていない。未確認の点は [docs/notes.md](docs/notes.md) の「確認できていないこと」を参照。実機で問題が見つかったら、修正の版(hotfix)で直す。

## 前提

- 空パスワードのログインキーリングと自動ログインは、LAN に限ったホストで、秘密情報を置かない専用ユーザー `agent` が使うことを前提に許している
- SSH(22)と RDP(3389)はインターネットに開けない。LAN の外からは VPN 経由とする

理由は [docs/SPEC.md](docs/SPEC.md) §8 を参照。

## 文書

| ファイル | 内容 |
|---|---|
| [docs/SPEC.md](docs/SPEC.md) | 仕様(目的、対象環境、要件、設計上の決定、未確定事項) |
| [docs/notes.md](docs/notes.md) | 技術メモ(検証した環境、設計で決めたこと、調査と検証の記録、確認できていないこと) |
| [docs/setup-guide.tex](docs/setup-guide.tex) | 詳細な設定手順書(準備から運用まで)。PDF は `just guide`(Docker の TeX Live)で作る |
| [docs/manual-steps.md](docs/manual-steps.md) | USB の作り方と、手作業の手順 |
| [docs/acceptance-test.md](docs/acceptance-test.md) | 受け入れテスト |
| [docs/release.md](docs/release.md) | リリースの手順。手順書の PDF は GitHub の Releases に付く |
| [docs/fleet.md](docs/fleet.md) | 実機の構成管理(2 台目からは、実機の env.yaml を別の非公開リポジトリで管理する。ひな形は [examples/fleet/](examples/fleet/)) |
| [CHANGELOG.md](CHANGELOG.md) | 変更の記録 |
| [CLAUDE.md](CLAUDE.md) | 作業ルール(ディレクトリ構成、秘密情報の扱い、検証、ブランチ運用) |

## 使い方

手元の PC での作業は [just](https://just.systems/) にまとめてある(Windows は Git Bash と Docker Desktop で動く)。`just` で一覧が出る。

```
cp autoinstall/env.example.yaml autoinstall/env.yaml   # 実値を入れる
just check-env          # env.yaml を検査する
just fetch-iso          # Ubuntu の ISO を取得して照合する
just iso                # build/agent-host.iso を作る → Rufus(DD イメージ)で USB に書き込む
just rdp <ホスト>       # RDP の接続ファイルを作る
just status <ホスト>    # 作った版と状態を見る(just logs <ホスト> で記録、just ssh <ホスト> で入る)
just facts <ホスト>     # 台帳のための情報(機種、シリアル、MAC、鍵の指紋)を YAML で出す
just update <ホスト>    # スクリプトや env.yaml の変更を反映する(OS は入れなおさない)
just backup <ホスト>    # 移行の書き出し / just restore <ホスト> <ファイル> で取り込み
just lint               # shellcheck と構文の検査
just guide              # 手順書の PDF を build/setup-guide/ に作る(Docker の TeX Live)
just release-check      # リリースの前の確認(release か hotfix のブランチで。手順は docs/release.md)
```

手作業の手順は [docs/manual-steps.md](docs/manual-steps.md)、詳しくは [docs/setup-guide.tex](docs/setup-guide.tex)(`just guide` で PDF)。

## ブランチ運用

GitFlow で運用する。詳しくは [CLAUDE.md](CLAUDE.md) の「ブランチ運用」を参照。

## ライセンス

MIT License。[LICENSE](LICENSE) を参照。
