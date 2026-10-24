#!/usr/bin/env bash
# Linux の道具が要るコマンドを、手元にその道具があればそのまま、なければ Docker の Ubuntu 26.04 の中で動かす。
# just のレシピから使う(Windows でも Docker Desktop があれば動く)。
#
# 使い方: scripts/local/in-ubuntu.sh "<apt のパッケージ>" "<要るコマンド>" <コマンド> [引数...]
#   例: scripts/local/in-ubuntu.sh "xorriso python3-yaml" "xorriso python3" bash scripts/build-usb.sh ...
set -euo pipefail

[ $# -ge 3 ] || { echo "使い方: $0 \"<パッケージ>\" \"<要るコマンド>\" <コマンド> [引数...]" >&2; exit 2; }
pkgs="$1"
need="$2"
shift 2

native=yes
for cmd in $need; do
    "$cmd" --version >/dev/null 2>&1 || native=no
done
if [ "$native" = yes ]; then
    exec "$@"
fi

command -v docker >/dev/null || { echo "$need がなく、Docker もない。どちらかを用意する" >&2; exit 1; }
root="$(pwd -W 2>/dev/null || pwd)"  # Git Bash では Windows の形のパスにする
args="$(printf '%q ' "$@")"
MSYS_NO_PATHCONV=1 exec docker run --rm -i -v "$root:/repo" -w /repo ubuntu:26.04 bash -c \
    "apt-get update -qq >/dev/null && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $pkgs >/dev/null && $args"
