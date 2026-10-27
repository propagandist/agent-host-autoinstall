# CLAUDE.md

## このリポジトリについて

常時稼働の AI エージェントホスト(Ubuntu Desktop 26.04 LTS + Orca + Claude Code + Codex + 利用者ごとのヘッドレスの GNOME のセッションと RDP)を、autoinstall で自動構成するための設定とスクリプト一式。

仕様は `docs/SPEC.md`、調べたこと・確かめたことの記録は `docs/notes.md` を必ず先に読むこと。

## 想定ディレクトリ構成

```
README.md                   # 概要と文書の案内
AGENTS.md                   # ほかのエージェント向けに CLAUDE.md を参照する
LICENSE                     # Apache License 2.0(標準の全文のまま。書き足さない)
NOTICE                      # 著作権者の表示(手順書の PDF の発行者もここから入れる)
icon.png                    # Orca がプロジェクトを登録するときに拾うアイコン(256×256 の PNG。元は docs/icon.svg)
justfile                    # 手元の PC での作業(ISO の作成、検査、ホストの状態・更新・移行、手順書の PDF、リリース前の確認)。just で一覧
CHANGELOG.md                # 変更の記録(版ごと)
.github/workflows/release.yml # タグの push で手順書の PDF を作り GitHub Release に付ける
autoinstall/
  autoinstall.yaml          # 本体(環境固有値はプレースホルダ)
  env.example.yaml          # 環境固有値のサンプル(コミットする)
  env.yaml                  # 実値(.gitignore 対象)
build/                      # 手元の作業の出力(ISO、一時ファイル build/.run.*、移行の書き出し、試験用の env と VM、手順書の PDF。.gitignore 対象)
scripts/
  build-usb.sh              # env.yaml を埋め込んだ autoinstall.yaml とスクリプトを入れた ISO を作る
  stage.sh                  # env.yaml から設定を作り /opt/agent-host に置くものをそろえる(build-usb.sh と just update が使う)
  local/                    # just から呼ぶ手元用のスクリプト(in-ubuntu.sh: Linux の道具を Docker で、iso.sh: env.yaml の検査と ISO、host.sh: ホストの操作、envs.sh: 実行ごとの build/.run.XXXXXX に env.yaml を写す・BUILD-INFO、build-guide.sh: 手順書の PDF、gen-cover.py: 表紙の絵を Gemini で作る、rdp-auth.sh: RDP の認証の確認、vm-test.sh: VirtualBox での通しの試験)
  render-autoinstall.py     # stage.sh から呼ぶ。env.yaml を重ねて検査し(知らないキーはエラー)、autoinstall.yaml と env.sh を生成
  setup-provision.sh        # late-commands から呼ぶ。初回起動時の構成サービスを有効にするだけ
  provision.sh              # 構成サービスから呼ぶ。post-install/ を番号順に実行(手で再実行してよい)
  verify.sh                 # ホストが仕様どおりかを読むだけで確かめる(just verify。/opt/agent-host にも置く)
  systemd/                  # agent-host-provision.service
  lib/common.sh             # post-install の共通関数
  post-install/             # 初回起動時に root で実行するスクリプト(番号順)
    05-proxy-ca.sh          # HTTP プロキシと独自の CA 証明書
    10-users.sh
    20-sessions.sh          # 利用者ごとのヘッドレスのセッションの drop-in と、headless の RDP(grdctl --headless)
    30-power.sh
    35-system.sh            # 時刻同期(chrony)、inotify の上限、apport の無効化
    36-minimize.sh          # 要らないサービスを止める、snap・kdump の削除、zram、電源、GRUB
    37-gpu.sh               # RDP の画面の符号化を GPU に任せる(Intel の VA-API の full 版、Vulkan、vainfo)
    40-ssh-ufw.sh
    50-updates.sh
    60-devtools.sh
    62-agents.sh            # env.yaml の agents で選んだ追加のエージェント
    63-clouds.sh            # env.yaml の clouds で選んだクラウドの CLI(AWS・Google Cloud・Azure)
    65-docker.sh            # Docker(固定・hold)と利用者ごとの rootless Docker
    70-orca.sh
    72-editors.sh           # env.yaml の editors で選んだエディター
    75-chrome.sh            # Google Chrome を入れ、利用者の既定のブラウザにする
    76-desktop.sh           # 日本語入力(fcitx5 と Mozc。IBus は止める)、Xfce Terminal、Atril(PDF)、Clipboard Indicator、Chrome のポリシー、壁紙の色、ブックマーク
    mozc-keymap.tsv         # Mozc のキーの割り当て(MS-IME から半角/全角を外したもの)。mozc-config.py で config1.db にする(76 が使う)
    80-agent-session.sh     # 利用者ごとのキーリング、フォルダー名、git、プロキシ、mise、エージェントへの説明
    84-notify.sh            # 通知(Slack、IP Messenger)とディスクの残りの監視
    85-ups.sh               # env.yaml の ups で選んだ UPS を NUT で見る(バッテリーが少ないと終了、出力を止めて復電で起動、通知)
    86-migrate.sh           # 移行用のスクリプトを /usr/local/sbin に置く
    88-start-sessions.sh    # first-login を利用者のバスで入れてから、利用者ごとのセッションを立てる
  notify/agent-notify       # 通知を送るスクリプト(/usr/local/bin に置く)
  notify/agent-host-diskcheck # ディスクの残りの監視
  notify/agent-host-ups-notify # NUT の upsmon から呼ぶ、UPS の通知(agent-notify に渡す)
  migrate/                  # 環境を入れ替えるときの書き出し(agent-host-backup)と取り込み(agent-host-restore)
  first-login/              # 利用者ごと: first-login.sh(セッションを立てる前に、88 が利用者のバスで一度だけ。gsettings)、desktop-env.sh(セッションが立つたび。壁紙の色と Dock)
tests/                      # just test(env.yaml の検査と stage.sh、利用者のホームへの書き込み、移行の書き出し、通知、一時ディレクトリ。root が要るものは Docker の中だけ)
examples/
  fleet/                    # 構成リポジトリのひな形(docs/fleet.md)
docs/
  SPEC.md                   # 仕様
  notes.md                  # 技術メモ(検証した環境、設計で決めたこと、調査と検証の記録、確認できていないこと)
  agent-host.rdp.example    # Windows のリモート デスクトップ接続の設定のひな形
  setup-guide.tex           # 詳細な設定手順書(LuaLaTeX。just guide が Docker で PDF を build/setup-guide/ に出す)
  guide.Dockerfile          # 手順書を作る TeX Live のイメージ
  cover.jpg                 # 手順書の表紙の絵(gen-cover.py で作ったもの)
  icon.svg                  # 直下の icon.png の元の絵(ブラウザのヘッドレスで 256×256 に撮って PNG にする)
  manual-steps.md           # 手作業手順(BIOS、利用者を足す・外す、RDP のパスワードの変更、各ログイン)
  acceptance-test.md        # 受け入れテスト手順
  release.md                # リリースの手順(GitFlow の release、版の付け方、成果物)
  fleet.md                  # 実機の構成管理(構成リポジトリ、SOPS と age、ホストの追加・設定の変更・版上げ・移行)
```

構成は実装の都合で変えてよいが、変えたら SPEC.md と整合させること。

## ルール

- **秘密情報をコミットしない。** パスワードハッシュ、SSH 鍵、LAN の IP 範囲などは `env.yaml` に分離し、`.gitignore` に入れる
- **公開される前提で書く。** 会社名・ホスト名・IP・個人のメールアドレスを本文・コメント・コミットメッセージに書かない(LICENSE と NOTICE の著作権者表示、それを入れる手順書の PDF の発行者表示、README の「ライセンス / 位置づけ」で PROPAGANDIST の OSS であることを書く 1 か所、このリポジトリ自身の GitHub の URL(clone や Releases の案内)は除く)。特定の組織や読者を前提にしない(「社内」「社外」「当社」「作業者」と書かず、「LAN」「組織」「利用者」などと書く。組織の予定や判断の経緯はこのリポジトリに書かない)
- **スクリプトは冪等に。** 再実行しても壊れないこと。`set -euo pipefail` を付ける
- **late-commands は薄く。** 処理はスクリプトに置き、late-commands からは呼ぶだけ(将来 Ansible に移しやすくするため)
- **バージョンは固定。** Node.js、npm パッケージ、Claude Code、Orca、GitHub CLI、Gitea CLI、Docker、uv、mise、VS Code、Zed、クラウドの CLI はバージョンを明示する。例外は、公式リポジトリに最新版しかない Google Chrome(unattended-upgrades で自動更新する)と、版を指定する方法がない Zed の拡張機能、VS Code の拡張機能が依存で入れるものと、env.yaml の `vscode_extensions` で版を書かなかったもの(どれも入れたときの最新で、その後は更新しない)
- **確認できていない挙動は推測で埋めない。** SPEC.md §9 の未確定事項は、調べた結果か「未確認」をコメントと docs/notes.md に残す
- **シンプルに保つ。** 過剰な抽象化や汎用化はしない。1台〜数台を確実に作れることが目的
- コメントとドキュメントは日本語
- **手順書を合わせる。** 構成・手順・固定するバージョンを変えたら、docs/manual-steps.md と docs/setup-guide.tex も直す

## マルチエージェントでのレビューと起票

- リポジトリのレビューは複数のエージェントで行う。主担当が対象を分担し、指摘ごとに別のエージェントが根拠・再現条件・影響・既知の制約との関係を独立に検証する。
- 主担当は検証結果を確認し、誤りや過大な断定を直してから起票する。静的な確認と、実行して再現した確認を区別し、未確認の点を明記する。検証担当は同じ Issue を重複して起票しない。
- エージェントが作成する Issue の本文末尾には、空行を挟んで次のトレーラーを付ける。担当には調査・起票をまとめたエージェント、検証担当には独立に検証したエージェントを記録する。

  ```text
  Co-Authored-By: Codex (review-lead; 調査・起票)
  Co-Authored-By: Claude Code (review-check; 静的検証)
  ```

- 上の名前は形式の例。実際に利用した製品名と、作業内で区別できる担当名・役割・検証方法を記録する。同じ製品の別エージェントでもよい。参加したエージェントごとに `Co-Authored-By:` を並べる。参加していないエージェントや、独立検証していない担当を記載しない。
- 既存 Issue を後から独立検証したときは、必要な本文の訂正とトレーラーの更新を行い、ほかの人の記述は保持する。

## ブランチ運用

GitFlow(git-flow AVH)で運用する。

- `main`:リリース済みの状態だけを置く。直接コミットしない
- `develop`:次のリリースに向けた統合先。直接コミットしない
- `feature/<内容>`:作業はここで行い、`git flow feature finish` で develop に戻す
- `release/<版>` / `hotfix/<版>`:main に入れるときだけ使う

## 作業の型

後片付けなどの作業の道具が読む、このリポジトリの値。決めたものだけを置く。

- 既定ブランチ:`develop`
- 常設ブランチ:`main`(既定ブランチ以外で消さないもの)

## 検証

- autoinstall の動作確認は、まず仮想マシンで行う。KVM/QEMU(virt-manager 等)を基本とし、KVM が使えない Windows では VirtualBox で代える(UEFI で作る)
- 利用者ごとのヘッドレスのセッションと RDP は、仮想マシン(2 人以上の env)でも確認してから実機で最終確認する
- 受け入れテストは `docs/acceptance-test.md` に沿って行う。機械で確かめられるものは `just test`(env.yaml の検査)、`just verify`(ホスト)、`just verify-rdp`、`just vm-test`(VirtualBox で入れなおしからの通し)
- 確かめる項目を増やしたら(post-install に設定を足したら)、`scripts/verify.sh` にも足す。env.yaml の項目を足したら `tests/test_render.py` と、render-autoinstall.py の `UPDATE_SCOPE`(just update で反映されるか)と文書の表にも足す
- 利用者のホームの中は root で書かない(`write_agent_file`・`ini_set --as-agent`・`agent_run` を使う。利用者ごとに回すのは `for_each_user`・`run_per_user`・`write_users_file`)。利用者が置いたリンクを root がたどると、ホームの外を書き換えられる
