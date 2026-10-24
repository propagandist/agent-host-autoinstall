# 手元の PC での作業をまとめたもの。一覧は just(または just --list)
# Windows では Git Bash で動かす(Linux の道具が要るものは Docker の Ubuntu 26.04 で動かす)
set shell := ["bash", "-euo", "pipefail", "-c"]
set windows-shell := ["C:/Program Files/Git/bin/bash.exe", "-euo", "pipefail", "-c"]

env := "autoinstall/env.yaml"
ubuntu := "ubuntu-26.04.1-desktop-amd64.iso"

_default:
    @just --list --unsorted

# Ubuntu の ISO を build/ に取得して SHA256 を照合する
fetch-iso:
    mkdir -p build
    curl -fL -C - -o build/{{ubuntu}} https://releases.ubuntu.com/26.04/{{ubuntu}}
    cd build && curl -fsSL https://releases.ubuntu.com/26.04/SHA256SUMS | grep ' \*{{ubuntu}}$' | sha256sum -c

# env.yaml を検査する(値の形と CHANGE_ME の残り)
check-env env=env:
    rm -rf build/.check-env
    scripts/local/in-ubuntu.sh python3-yaml python3 python3 scripts/render-autoinstall.py autoinstall/autoinstall.yaml {{env}} build/.check-env
    rm -rf build/.check-env
    @echo "{{env}} は問題ない"

# インストール用の ISO を作る(USB には Rufus の DD イメージのモードで書き込む)
iso out="build/agent-host.iso" env=env:
    scripts/local/in-ubuntu.sh "xorriso python3-yaml" "xorriso python3" bash scripts/build-usb.sh build/{{ubuntu}} {{out}} {{env}}

# shellcheck と構文の検査
lint:
    scripts/local/in-ubuntu.sh shellcheck shellcheck bash -c 'shellcheck -x scripts/*.sh scripts/lib/*.sh scripts/post-install/*.sh scripts/first-login/*.sh scripts/local/*.sh scripts/notify/agent-host-diskcheck scripts/migrate/agent-host-* scripts/watchdog/agent-host-*'
    scripts/local/in-ubuntu.sh python3 python3 python3 -c 'import ast; [ast.parse(open(f, encoding="utf-8").read(), f) for f in ("scripts/notify/agent-notify", "scripts/render-autoinstall.py")]'
    @echo "検査は問題ない"

# 詳細な設定手順書の PDF を build/setup-guide/ に作る(Docker の TeX Live で作る。初回はイメージの作成に数分かかる)
guide:
    mkdir -p build/setup-guide
    printf '%s{%s 版(%s)}\n' '\newcommand{\guideversion}' "$(date +%Y-%m-%d)" "$(git describe --always --dirty 2>/dev/null || echo 不明)" > build/setup-guide/guide-version.tex
    docker build -q -t agent-host-guide -f docs/guide.Dockerfile docs > /dev/null
    case "$(uname -s)" in MINGW*|MSYS*) repo="$(pwd -W)"; user=() ;; *) repo="$(pwd)"; user=(--user "$(id -u):$(id -g)") ;; esac; \
    MSYS_NO_PATHCONV=1 docker run --rm "${user[@]}" -v "$repo:/repo" -w /repo -e TEXINPUTS=/repo/build/setup-guide: agent-host-guide \
        latexmk -lualatex -interaction=nonstopmode -halt-on-error -outdir=build/setup-guide docs/setup-guide.tex > build/setup-guide/latexmk.out \
        || { tail -30 build/setup-guide/latexmk.out; exit 1; }
    @echo "作成した: build/setup-guide/setup-guide.pdf"

# ホスト用の RDP の接続ファイルを build/<ホスト>.rdp に作る
rdp host:
    mkdir -p build
    sed -e 's/\r$//' -e 's/^full address:s:.*/full address:s:{{host}}:3389/' -e 's/$/\r/' docs/agent-host.rdp.example > build/{{host}}.rdp
    @echo "作成した: build/{{host}}.rdp(ダブルクリックで接続)"

# sysadmin で SSH する(AGENT_HOST_SSH_OPTS でオプションを足せる)
ssh host:
    ssh ${AGENT_HOST_SSH_OPTS:-} sysadmin@{{host}}

# ホストの状態を見る(構成、RDP、セッション、ディスク、メモリ、失敗した unit)
status host:
    scripts/local/host.sh status {{host}}

# 構成・first-login・セッションの見張りの記録を見る
logs host:
    scripts/local/host.sh logs {{host}}

# スクリプトと env.yaml の変更をホストに反映して構成を再実行する(OS は入れなおさない)
update host env=env:
    scripts/local/host.sh update {{host}} {{env}}

# 移行の書き出し(既定は build/backups/。ログインの情報が入る)
backup host out="":
    scripts/local/host.sh backup {{host}} {{out}}

# 移行の取り込み(構成が終わったホストに)
restore host file:
    scripts/local/host.sh restore {{host}} {{file}}
