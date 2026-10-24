#!/usr/bin/env bash
# RDP の認証が通るかを、FreeRDP の +auth-only で確かめる(画面は開かない)。host.sh verify-rdp が Linux の中で呼ぶ。
# 認証情報は env.yaml の rdp(重ねた結果)を使う。
#
# 使い方: scripts/local/rdp-auth.sh <ホスト> <ポート> <env.yaml>...
# 必要なもの: xfreerdp3(freerdp3-x11)、python3、python3-yaml
set -euo pipefail

host="$1"
shown="$1"
port="$2"
shift 2
# Docker の中からは、手元の PC の 127.0.0.1(試験用の VM のポートの転送先)を host.docker.internal で見る
if [ -f /.dockerenv ] && { [ "$host" = 127.0.0.1 ] || [ "$host" = localhost ]; }; then
    host=host.docker.internal
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
python3 scripts/render-autoinstall.py autoinstall/autoinstall.yaml "$@" "$tmp" >/dev/null
# shellcheck source=/dev/null
. "$tmp/env.sh"

# 成功すると「Authentication only, exit status 1」を出して 0 で終わる。認証の失敗や接続できないときは別の終わり方をする
log="$tmp/freerdp.log"
rc=0
xfreerdp3 "/v:$host:$port" "/u:$AH_RDP_USER" "/p:$AH_RDP_PASSWORD" /cert:ignore +auth-only /timeout:10000 \
    >"$log" 2>&1 || rc=$?
if [ "$rc" = 0 ] && grep -q 'Authentication only, exit status 1' "$log"; then
    echo "✓ RDP の認証が通った($AH_RDP_USER@$shown:$port)"
else
    echo "✗ RDP の認証が通らなかった($AH_RDP_USER@$shown:$port、終了コード $rc)" >&2
    grep -E 'ERRCONNECT|ERROR' "$log" | grep -v -i kerberos | tail -3 >&2 || true
    exit 1
fi
