# CLAUDE.md

## このリポジトリについて

常時稼働の AI エージェントホスト(Ubuntu Desktop 26.04 LTS + Orca + Claude Code + Codex + GNOME デスクトップ共有)を、autoinstall で自動構成するための設定とスクリプト一式。

仕様は `docs/SPEC.md`、経緯と次の作業は `docs/HANDOVER.md` を必ず先に読むこと。

## 想定ディレクトリ構成

```
README.md                   # 概要と文書の案内
autoinstall/
  autoinstall.yaml          # 本体(環境固有値はプレースホルダ)
  env.example.yaml          # 環境固有値のサンプル(コミットする)
  env.yaml                  # 実値(.gitignore 対象)
build/                      # ISO のダウンロード先と build-usb.sh の出力(.gitignore 対象)
scripts/
  build-usb.sh              # env.yaml を埋め込んだ autoinstall.yaml とスクリプトを入れた ISO を作る
  render-autoinstall.py     # build-usb.sh から呼ぶ。autoinstall.yaml と env.sh を生成
  setup-provision.sh        # late-commands から呼ぶ。初回起動時の構成サービスを有効にするだけ
  provision.sh              # 構成サービスから呼ぶ。post-install/ を番号順に実行(手で再実行してよい)
  systemd/                  # agent-host-provision.service
  lib/common.sh             # post-install の共通関数
  post-install/             # 初回起動時に root で実行するスクリプト(番号順)
    05-proxy-ca.sh          # 社内のプロキシと CA 証明書
    10-users.sh
    20-autologin.sh
    30-power.sh
    35-system.sh            # 時刻同期(chrony)、inotify の上限、apport の無効化
    36-minimize.sh          # 要らないサービスを止める、snap・kdump の削除、zram、電源、VA-API、GRUB
    40-ssh-ufw.sh
    50-updates.sh
    60-devtools.sh
    62-agents.sh            # env.yaml の agents で選んだ追加のエージェント
    65-docker.sh            # Docker(固定・hold)と agent 専用の rootless Docker
    70-orca.sh
    72-editors.sh           # env.yaml の editors で選んだエディター
    75-chrome.sh            # Google Chrome を入れ、agent の既定のブラウザにする
    76-desktop.sh           # Xfce Terminal、Clipboard Indicator、Chrome のポリシー、壁紙の色、ブックマーク
    80-agent-session.sh     # キーリング、RDP 認証情報の受け渡し、first-login の自動起動
    84-notify.sh            # 通知(Slack、IP Messenger)とディスクの残りの監視
    86-migrate.sh           # 移行用のスクリプトを /usr/local/sbin に置く
  notify/agent-notify       # 通知を送るスクリプト(/usr/local/bin に置く)
  notify/agent-host-diskcheck # ディスクの残りの監視
  migrate/                  # 環境を入れ替えるときの書き出し(agent-host-backup)と取り込み(agent-host-restore)
  watchdog/                 # agent のセッションが落ちたら GDM を再起動する見張り(20-autologin.sh が置く)
  first-login/              # agent の初回ログイン時に一度だけ実行(gsettings、grdctl)
docs/
  SPEC.md                   # 仕様
  HANDOVER.md               # 経緯と次の作業
  agent-host.rdp.example    # Windows のリモート デスクトップ接続の設定のひな形
  setup-guide.tex           # 詳細な設定手順書(LuaLaTeX。PDF は build/setup-guide/ に出す)
  manual-steps.md           # 手作業手順(BIOS、キーリング、デスクトップ共有、各ログイン)
  acceptance-test.md        # 受け入れテスト手順
```

構成は実装の都合で変えてよいが、変えたら SPEC.md と整合させること。

## ルール

- **秘密情報をコミットしない。** パスワードハッシュ、SSH 鍵、社内IP範囲などは `env.yaml` に分離し、`.gitignore` に入れる
- **公開される前提で書く。** 会社名・ホスト名・IP・個人のメールアドレスを本文・コメント・コミットメッセージに書かない(LICENSE の著作権者表示は除く)
- **スクリプトは冪等に。** 再実行しても壊れないこと。`set -euo pipefail` を付ける
- **late-commands は薄く。** 処理はスクリプトに置き、late-commands からは呼ぶだけ(将来 Ansible に移しやすくするため)
- **バージョンは固定。** Node.js、npm パッケージ、Claude Code、Orca、GitHub CLI、Docker、uv、mise、VS Code、Zed はバージョンを明示する。例外は Google Chrome で、公式リポジトリに最新版しかないため固定せず、unattended-upgrades で自動更新する
- **確認できていない挙動は推測で埋めない。** SPEC.md §9 の未確定事項は、調べた結果か「未確認」をコメントと HANDOVER.md に残す
- **シンプルに保つ。** 過剰な抽象化や汎用化はしない。1台〜数台を確実に作れることが目的
- コメントとドキュメントは日本語
- **手順書を合わせる。** 構成・手順・固定するバージョンを変えたら、docs/manual-steps.md と docs/setup-guide.tex も直す

## ブランチ運用

GitFlow(git-flow AVH)で運用する。

- `main`:リリース済みの状態だけを置く。直接コミットしない
- `develop`:次のリリースに向けた統合先。直接コミットしない
- `feature/<内容>`:作業はここで行い、`git flow feature finish` で develop に戻す
- `release/<版>` / `hotfix/<版>`:main に入れるときだけ使う

## 検証

- autoinstall の動作確認は、まず仮想マシンで行う。KVM/QEMU(virt-manager 等)を基本とし、KVM が使えない Windows では VirtualBox で代える(UEFI で作る)
- デスクトップ共有と自動ログインの組み合わせは、仮想マシンでも確認してから実機で最終確認する
- 受け入れテストは `docs/acceptance-test.md` に沿って行う
