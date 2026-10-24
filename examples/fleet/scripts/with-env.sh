#!/usr/bin/env bash
# common.yaml と hosts/<ホスト>.yaml を復号して build/.dec/<ホスト>/ に置き、<コマンド> の後ろにその 2 つのパスを足して
# 実行する。終わったら(失敗しても)復号したファイルを消す。SOPS で暗号化していないファイルはそのまま写す。
#
# 使い方: scripts/with-env.sh <ホスト> <コマンド> [引数...]
#   例: scripts/with-env.sh agent-host-01 just -f tool/justfile check-env
set -euo pipefail

[ $# -ge 2 ] || { echo "使い方: $0 <ホスト> <コマンド> [引数...]" >&2; exit 2; }
host="$1"
shift
[ -f "hosts/$host.yaml" ] || { echo "hosts/$host.yaml がない" >&2; exit 1; }

dec="build/.dec/$host"
rm -rf "$dec"
mkdir -p "$dec"
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
