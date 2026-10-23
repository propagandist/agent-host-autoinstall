# agent-host-autoinstall

社内のオンプレPCを、常時稼働の AI エージェントホスト(Ubuntu Desktop 26.04 LTS + Orca + Claude Code + Codex + GNOME デスクトップ共有)として、autoinstall で自動構成するための設定とスクリプト一式。
USBメモリ1本から同じ構成を再現でき、再起動・停電復帰後も人手を介さず RDP で接続できる状態に戻ることを目指す。

## 現状

設計段階。仕様と作業ルールのみで、実装は未着手。

## 文書

| ファイル | 内容 |
|---|---|
| [docs/SPEC.md](docs/SPEC.md) | 仕様(目的、対象環境、要件、設計上の決定、未確定事項) |
| [docs/HANDOVER.md](docs/HANDOVER.md) | これまでの経緯と次にやること |
| [CLAUDE.md](CLAUDE.md) | 作業ルール(ディレクトリ構成、秘密情報の扱い、検証、ブランチ運用) |

## 使い方

実装後に書く。

## ブランチ運用

GitFlow で運用する。詳しくは [CLAUDE.md](CLAUDE.md) の「ブランチ運用」を参照。
