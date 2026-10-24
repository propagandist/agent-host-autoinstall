#!/usr/bin/env bash
# common.yaml と hosts/<ホスト>.yaml を復号して、この実行だけのディレクトリ build/.dec/<ホスト>.XXXXXX/ に置き、
# <コマンド> の後ろにその 2 つのパスを足して実行する。終わったら(失敗しても)そのディレクトリを消す。
# SOPS で暗号化していないファイルはそのまま写す。実行ごとに分けるので、同じホストへの check・iso・update が
# 重なっても、先に動いているほうの入力を消さない(Issue #9)。
#
# 使い方: scripts/with-env.sh <ホスト> <コマンド> [引数...]
#   例: scripts/with-env.sh agent-host-01 just -f tool/justfile check-env
set -euo pipefail

[ $# -ge 2 ] || { echo "使い方: $0 <ホスト> <コマンド> [引数...]" >&2; exit 2; }
host="$1"
shift
[ -f "hosts/$host.yaml" ] || { echo "hosts/$host.yaml がない" >&2; exit 1; }

mkdir -p build/.dec
dec="$(mktemp -d "build/.dec/$host.XXXXXX")"
chmod 700 "$dec"
trap 'rm -rf "$dec"' EXIT

decrypt() {
    if grep -q '^sops:' "$1"; then
        (umask 077; sops --decrypt "$1" >"$2")
    else
        install -m 600 "$1" "$2"
    fi
}
decrypt common.yaml "$dec/common.yaml"
decrypt "hosts/$host.yaml" "$dec/$host.yaml"

"$@" "$dec/common.yaml" "$dec/$host.yaml"
