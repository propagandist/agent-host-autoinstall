# agent-host-autoinstall

社内のオンプレPCを、常時稼働の AI エージェントホスト(Ubuntu Desktop 26.04 LTS + Orca + Claude Code + Codex + GNOME デスクトップ共有)として、autoinstall で自動構成するための設定とスクリプト一式。
USBメモリ1本から同じ構成を再現でき、再起動・停電復帰後も人手を介さず RDP で接続できる状態に戻ることを目指す。

## 現状

VirtualBox の仮想マシンで、無人インストールから RDP の接続と受け入れテストまで確かめた。実機ではまだ確かめていない。未確認の点は [docs/HANDOVER.md](docs/HANDOVER.md) を参照。

## 前提

- 空パスワードのログインキーリングと自動ログインは、社内LANに限ったホストで、秘密情報を置かない専用ユーザー `agent` が使うことを前提に許している
- SSH(22)と RDP(3389)はインターネットに開けない。社外からは VPN 経由とする

理由は [docs/SPEC.md](docs/SPEC.md) §8 を参照。

## 文書

| ファイル | 内容 |
|---|---|
| [docs/SPEC.md](docs/SPEC.md) | 仕様(目的、対象環境、要件、設計上の決定、未確定事項) |
| [docs/HANDOVER.md](docs/HANDOVER.md) | これまでの経緯と次にやること |
| [docs/setup-guide.tex](docs/setup-guide.tex) | 詳細な設定手順書(準備から運用まで)。PDF は `just guide`(Docker の TeX Live)で作る |
| [docs/manual-steps.md](docs/manual-steps.md) | USB の作り方と、手作業の手順 |
| [docs/acceptance-test.md](docs/acceptance-test.md) | 受け入れテスト |
| [docs/release.md](docs/release.md) | リリースの手順。手順書の PDF は GitHub の Releases に付く |
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
just status <ホスト>    # 状態を見る
just update <ホスト>    # スクリプトや env.yaml の変更を反映する(OS は入れなおさない)
just backup <ホスト>    # 移行の書き出し / just restore <ホスト> <ファイル> で取り込み
```

手作業の手順は [docs/manual-steps.md](docs/manual-steps.md)、詳しくは [docs/setup-guide.tex](docs/setup-guide.tex)(`just guide` で PDF)。

## ブランチ運用

GitFlow で運用する。詳しくは [CLAUDE.md](CLAUDE.md) の「ブランチ運用」を参照。

## ライセンス

MIT License。[LICENSE](LICENSE) を参照。
