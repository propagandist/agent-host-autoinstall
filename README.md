# agent-host-autoinstall

社内のオンプレPCを、常時稼働の AI エージェントホスト(Ubuntu Desktop 26.04 LTS + Orca + Claude Code + Codex + GNOME デスクトップ共有)として、autoinstall で自動構成するための設定とスクリプト一式。
USBメモリ1本から同じ構成を再現でき、再起動・停電復帰後も人手を介さず RDP で接続できる状態に戻ることを目指す。

## 現状

一通り実装したが、仮想マシン・実機ではまだ動かしていない。未確認の点は [docs/HANDOVER.md](docs/HANDOVER.md) を参照。

## 前提

- 空パスワードのログインキーリングと自動ログインは、社内LANに限ったホストで、秘密情報を置かない専用ユーザー `agent` が使うことを前提に許している
- SSH(22)と RDP(3389)はインターネットに開けない。社外からは VPN 経由とする

理由は [docs/SPEC.md](docs/SPEC.md) §8 を参照。

## 文書

| ファイル | 内容 |
|---|---|
| [docs/SPEC.md](docs/SPEC.md) | 仕様(目的、対象環境、要件、設計上の決定、未確定事項) |
| [docs/HANDOVER.md](docs/HANDOVER.md) | これまでの経緯と次にやること |
| [docs/manual-steps.md](docs/manual-steps.md) | USB の作り方と、手作業の手順 |
| [docs/acceptance-test.md](docs/acceptance-test.md) | 受け入れテスト |
| [CLAUDE.md](CLAUDE.md) | 作業ルール(ディレクトリ構成、秘密情報の扱い、検証、ブランチ運用) |

## 使い方

1. `autoinstall/env.example.yaml` を `autoinstall/env.yaml` にコピーし、実値を入れる
2. Linux か WSL で `scripts/build-usb.sh <Ubuntu Desktop 26.04 の ISO> <出力ISO>` を実行する
3. 出力 ISO を USB メモリに書き込み、対象の PC をそこから起動する
4. 残りの手作業は [docs/manual-steps.md](docs/manual-steps.md) に沿って行う

## ブランチ運用

GitFlow で運用する。詳しくは [CLAUDE.md](CLAUDE.md) の「ブランチ運用」を参照。

## ライセンス

MIT License。[LICENSE](LICENSE) を参照。
