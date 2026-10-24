# 手元の PC での作業をまとめたもの。一覧は just(または just --list)
# Windows では Git Bash で動かす(Linux の道具が要るものは Docker の Ubuntu 26.04 で動かす)
set shell := ["bash", "-euo", "pipefail", "-c"]
set windows-shell := ["C:/Program Files/Git/bin/bash.exe", "-euo", "pipefail", "-c"]

env := "autoinstall/env.yaml"
ubuntu := "ubuntu-26.04.1-desktop-amd64.iso"

# 相対パスの引数(env.yaml、出力先、書き出したファイル)を、just を呼んだディレクトリから見るため(scripts/local/envs.sh)。
# 構成リポジトリから just -f tool/justfile ... で呼んでも、構成リポジトリの hosts/ などを渡せる(docs/fleet.md)
export AGENT_HOST_CALLER_DIR := invocation_directory()

_default:
    @just --list --unsorted

# Ubuntu の ISO を build/ に取得して SHA256 を照合する
fetch-iso:
    mkdir -p build
    curl -fL -C - -o build/{{ubuntu}} https://releases.ubuntu.com/26.04/{{ubuntu}}
    cd build && curl -fsSL https://releases.ubuntu.com/26.04/SHA256SUMS | grep ' \*{{ubuntu}}$' | sha256sum -c

# env.yaml を検査する(値の形、CHANGE_ME の残り、知らないキー)。複数渡すと前から順に重ねる(後のファイルの値が勝つ)
check-env +envs=env:
    scripts/local/iso.sh check {{envs}}

# インストール用の ISO を作る(USB には Rufus の DD イメージのモードで書き込む)。env.yaml は複数渡せる
iso out="build/agent-host.iso" +envs=env:
    scripts/local/iso.sh build build/{{ubuntu}} {{out}} {{envs}}

# shellcheck と構文の検査
lint:
    scripts/local/in-ubuntu.sh shellcheck shellcheck bash -c 'shellcheck -x scripts/*.sh scripts/lib/*.sh scripts/post-install/*.sh scripts/first-login/*.sh scripts/local/*.sh scripts/notify/agent-host-diskcheck scripts/migrate/agent-host-* scripts/watchdog/agent-host-* examples/fleet/scripts/*.sh'
    scripts/local/in-ubuntu.sh python3 python3 python3 -c 'import ast; [ast.parse(open(f, encoding="utf-8").read(), f) for f in ("scripts/notify/agent-notify", "scripts/render-autoinstall.py", "scripts/local/gen-cover.py")]'
    @echo "検査は問題ない"

# 詳細な設定手順書の PDF を build/setup-guide/ に作る(Docker の TeX Live で作る。初回はイメージの作成に数分かかる)
guide:
    scripts/local/build-guide.sh

# リリースの前の確認(release か hotfix のブランチで、コミット済みであること、検査と PDF の作成が通ること)。手順は docs/release.md
release-check:
    case "$(git branch --show-current)" in release/*|hotfix/*) ;; *) echo "release/<版> か hotfix/<版> のブランチで実行する" >&2; exit 1 ;; esac
    git diff --quiet && git diff --cached --quiet || { echo "コミットしていない変更がある" >&2; exit 1; }
    v="$(git branch --show-current)"; v="${v#*/}"; grep -q "^## \[$v\]" CHANGELOG.md || { echo "CHANGELOG.md に ## [$v] の節がない" >&2; exit 1; }
    just lint
    just guide
    @echo "リリースの前の確認は問題ない。次は VM での入れなおしと受け入れテスト(docs/release.md)"

# ホスト用の RDP の接続ファイルを build/<ホスト>.rdp に作る
rdp host:
    mkdir -p build
    sed -e 's/\r$//' -e 's/^full address:s:.*/full address:s:{{host}}:3389/' -e 's/$/\r/' docs/agent-host.rdp.example > build/{{host}}.rdp
    @echo "作成した: build/{{host}}.rdp(ダブルクリックで接続)"

# sysadmin で SSH する(AGENT_HOST_SSH_OPTS でオプションを足せる)
ssh host:
    ssh ${AGENT_HOST_SSH_OPTS:-} sysadmin@{{host}}

# ホストの状態を見る(作った版、構成、RDP、セッション、ディスク、メモリ、失敗した unit)
status host:
    scripts/local/host.sh status {{host}}

# 台帳のためにホストの情報を YAML で出す(機種、シリアル、MAC、ディスク、メモリ、OS、作った版、鍵の指紋)
facts host:
    scripts/local/host.sh facts {{host}}

# 構成・first-login・セッションの見張りの記録を見る
logs host:
    scripts/local/host.sh logs {{host}}

# スクリプトと env.yaml の変更をホストに反映して構成を再実行する(OS は入れなおさない)。env.yaml は複数渡せる
update host +envs=env:
    scripts/local/host.sh update {{host}} {{envs}}

# 移行の書き出し(既定は build/backups/。ログインの情報が入る)
backup host out="":
    scripts/local/host.sh backup {{host}} {{out}}

# 移行の取り込み(構成が終わったホストに)
restore host file:
    scripts/local/host.sh restore {{host}} {{file}}
