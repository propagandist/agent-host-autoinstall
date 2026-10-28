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

# .sops.yaml の encrypted_regex と同じ名前(変えたら両方を直す)。値が空("" や '')なら秘密ではない
secret_line='^[[:space:]-]*(password_hash|password|initial_password|slack_webhook_url):[[:space:]]*([^[:space:]#"'"'"']|"[^"]|'"'"'[^'"'"'])'

decrypt() {
    if grep -q '^sops:' "$1"; then
        command -v sops >/dev/null || { echo "$1 を復号する sops がない(入れ方は tool/docs/fleet.md の 3)" >&2; exit 1; }
        (umask 077; sops --decrypt "$1" >"$2")
    else
        # 暗号化していないのに秘密の値が書いてあれば止める。暗号化に失敗したまま気づかずにコミットしないように(#34)。
        # 値を画面に出さないよう、行の番号だけを出す
        lines="$(grep -n -E "$secret_line" "$1" | cut -d: -f1 | paste -sd, -)" || true
        if [ -n "$lines" ]; then
            echo "$1 の $lines 行目に、暗号化していない秘密の値がある。sops --encrypt --in-place $1 で暗号化する" >&2
            exit 1
        fi
        install -m 600 "$1" "$2"
    fi
}
decrypt common.yaml "$dec/common.yaml"
decrypt "hosts/$host.yaml" "$dec/$host.yaml"

"$@" "$dec/common.yaml" "$dec/$host.yaml"
