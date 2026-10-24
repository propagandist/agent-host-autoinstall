# CLAUDE.md

## このリポジトリについて

常時稼働の AI エージェントホスト(Ubuntu Desktop 26.04 LTS + Orca + Claude Code + Codex + GNOME デスクトップ共有)を、autoinstall で自動構成するための設定とスクリプト一式。

仕様は `docs/SPEC.md`、調べたこと・確かめたことの記録は `docs/notes.md` を必ず先に読むこと。

## 想定ディレクトリ構成

```
README.md                   # 概要と文書の案内
LICENSE                     # Apache License 2.0(標準の全文のまま。書き足さない)
NOTICE                      # 著作権者の表示(手順書の PDF の発行者もここから入れる)
justfile                    # 手元の PC での作業(ISO の作成、検査、ホストの状態・更新・移行、手順書の PDF、リリース前の確認)。just で一覧
CHANGELOG.md                # 変更の記録(版ごと)
.github/workflows/release.yml # タグの push で手順書の PDF を作り GitHub Release に付ける
autoinstall/
  autoinstall.yaml          # 本体(環境固有値はプレースホルダ)
  env.example.yaml          # 環境固有値のサンプル(コミットする)
  env.yaml                  # 実値(.gitignore 対象)
build/                      # ISO のダウンロード先と build-usb.sh の出力(.gitignore 対象)
scripts/
  build-usb.sh              # env.yaml を埋め込んだ autoinstall.yaml とスクリプトを入れた ISO を作る
  stage.sh                  # env.yaml から設定を作り /opt/agent-host に置くものをそろえる(build-usb.sh と just update が使う)
  local/                    # just から呼ぶ手元用のスクリプト(in-ubuntu.sh: Linux の道具を Docker で、iso.sh: env.yaml の検査と ISO、host.sh: ホストの操作、envs.sh: env.yaml を build/.env に写す・BUILD-INFO、build-guide.sh: 手順書の PDF、gen-cover.py: 表紙の絵を Gemini で作る、rdp-auth.sh: RDP の認証の確認、vm-test.sh: VirtualBox での通しの試験)
  render-autoinstall.py     # stage.sh から呼ぶ。env.yaml を重ねて検査し(知らないキーはエラー)、autoinstall.yaml と env.sh を生成
  setup-provision.sh        # late-commands から呼ぶ。初回起動時の構成サービスを有効にするだけ
  provision.sh              # 構成サービスから呼ぶ。post-install/ を番号順に実行(手で再実行してよい)
  verify.sh                 # ホストが仕様どおりかを読むだけで確かめる(just verify。/opt/agent-host にも置く)
  systemd/                  # agent-host-provision.service
  lib/common.sh             # post-install の共通関数
  post-install/             # 初回起動時に root で実行するスクリプト(番号順)
    05-proxy-ca.sh          # HTTP プロキシと独自の CA 証明書
    10-users.sh
    20-autologin.sh
    30-power.sh
    35-system.sh            # 時刻同期(chrony)、inotify の上限、apport の無効化
    36-minimize.sh          # 要らないサービスを止める、snap・kdump の削除、zram、電源、VA-API、GRUB
    40-ssh-ufw.sh
    50-updates.sh
    60-devtools.sh
    62-agents.sh            # env.yaml の agents で選んだ追加のエージェント
    63-clouds.sh            # env.yaml の clouds で選んだクラウドの CLI(AWS・Google Cloud・Azure)
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
tests/                      # just test(render-autoinstall.py と stage.sh の試験)
examples/
  fleet/                    # 構成リポジトリのひな形(docs/fleet.md)
docs/
  SPEC.md                   # 仕様
  notes.md                  # 技術メモ(検証した環境、設計で決めたこと、調査と検証の記録、確認できていないこと)
  agent-host.rdp.example    # Windows のリモート デスクトップ接続の設定のひな形
  setup-guide.tex           # 詳細な設定手順書(LuaLaTeX。just guide が Docker で PDF を build/setup-guide/ に出す)
  guide.Dockerfile          # 手順書を作る TeX Live のイメージ
  cover.jpg                 # 手順書の表紙の絵(gen-cover.py で作ったもの)
  manual-steps.md           # 手作業手順(BIOS、キーリング、デスクトップ共有、各ログイン)
  acceptance-test.md        # 受け入れテスト手順
  release.md                # リリースの手順(GitFlow の release、版の付け方、成果物)
  fleet.md                  # 実機の構成管理(構成リポジトリ、SOPS と age、ホストの追加・設定の変更・版上げ・移行)
```

構成は実装の都合で変えてよいが、変えたら SPEC.md と整合させること。

## ルール

- **秘密情報をコミットしない。** パスワードハッシュ、SSH 鍵、LAN の IP 範囲などは `env.yaml` に分離し、`.gitignore` に入れる
- **公開される前提で書く。** 会社名・ホスト名・IP・個人のメールアドレスを本文・コメント・コミットメッセージに書かない(LICENSE と NOTICE の著作権者表示、それを入れる手順書の PDF の発行者表示、README の「ライセンス / 位置づけ」で PROPAGANDIST の OSS であることを書く 1 か所は除く)。特定の組織や読者を前提にしない(「社内」「社外」「当社」「作業者」と書かず、「LAN」「組織」「利用者」などと書く。組織の予定や判断の経緯はこのリポジトリに書かない)
- **スクリプトは冪等に。** 再実行しても壊れないこと。`set -euo pipefail` を付ける
- **late-commands は薄く。** 処理はスクリプトに置き、late-commands からは呼ぶだけ(将来 Ansible に移しやすくするため)
- **バージョンは固定。** Node.js、npm パッケージ、Claude Code、Orca、GitHub CLI、Gitea CLI、Docker、uv、mise、VS Code、Zed、クラウドの CLI はバージョンを明示する。例外は、公式リポジトリに最新版しかない Google Chrome(unattended-upgrades で自動更新する)と、版を指定する方法がない Zed の拡張機能、VS Code の拡張機能が依存で入れるもの(どちらも入れたときの最新で、その後は更新しない)
- **確認できていない挙動は推測で埋めない。** SPEC.md §9 の未確定事項は、調べた結果か「未確認」をコメントと docs/notes.md に残す
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
- 受け入れテストは `docs/acceptance-test.md` に沿って行う。機械で確かめられるものは `just test`(env.yaml の検査)、`just verify`(ホスト)、`just verify-rdp`、`just vm-test`(VirtualBox で入れなおしからの通し)
- 確かめる項目を増やしたら(post-install に設定を足したら)、`scripts/verify.sh` にも足す。env.yaml の項目を足したら `tests/test_render.py` にも足す
