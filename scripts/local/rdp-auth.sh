#!/usr/bin/env bash
# 利用者ごとに RDP の認証が通るかを、FreeRDP の +auth-only で確かめる(画面は開かない)。host.sh verify-rdp が Linux の中で呼ぶ。
# 認証情報は env.yaml の users(重ねた結果)の rdp と port を使う。仮のパスワード(initial_password)は本人が最初の RDP で
# 変えるので、仮の値で通らなかったときは失敗にせず「未検証」と出す。今のパスワードは --ask で渡す(パスワードのファイル)。
# つながらない、TLS のエラーなど、認証の前で止まったものは失敗にする。
#
# 使い方: scripts/local/rdp-auth.sh <ホスト> <パスワードのファイル | -> <env.yaml>...
#   パスワードのファイル: 「利用者名<タブ>今のパスワード」の行。書いた利用者はその値で確かめ、通らなければ失敗にする
#   環境変数 AGENT_HOST_RDP_PORT_OFFSET: ポートに足す数(試験用の VM は 3389 を 13389 に転送している。既定 0)
# 必要なもの: xfreerdp3(freerdp3-x11)、python3、python3-yaml
set -euo pipefail

host="$1"
shown="$1"
pw_file="$2"
shift 2
offset="${AGENT_HOST_RDP_PORT_OFFSET:-0}"
# Docker Desktop の中からは、手元の PC の 127.0.0.1(試験用の VM のポートの転送先)を host.docker.internal で見る。
# Linux の Docker にはこの名前がなく、in-ubuntu.sh が手元のネットワーク(--network host)で動かすので、そのまま 127.0.0.1
if [ -f /.dockerenv ] && { [ "$host" = 127.0.0.1 ] || [ "$host" = localhost ]; } && getent hosts host.docker.internal >/dev/null; then
    host=host.docker.internal
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
python3 scripts/render-autoinstall.py autoinstall/autoinstall.yaml "$@" "$tmp" >/dev/null
# shellcheck source=/dev/null
. "$tmp/env.sh"

failed=0
for user in $AH_USERS; do
    # shellcheck source=/dev/null
    . "$tmp/users/$user.env"
    port=$((AH_USER_PORT + offset))
    password="$AH_RDP_INITIAL_PASSWORD"
    asked=no
    if [ "$pw_file" != - ] && grep -q "^$user	" "$pw_file"; then
        password="$(sed -n "s/^$user	//p" "$pw_file" | head -1)"
        asked=yes
    fi
    # 成功すると「Authentication only, exit status 1」を出して 0 で終わる。認証の失敗は ERRCONNECT_LOGON_FAILURE
    log="$tmp/freerdp-$user.log"
    rc=0
    xfreerdp3 "/v:$host:$port" "/u:$AH_RDP_USER" "/p:$password" /cert:ignore +auth-only /timeout:10000 \
        >"$log" 2>&1 || rc=$?
    where="$user($AH_RDP_USER@$shown:$port)"
    if [ "$rc" = 0 ] && grep -q 'Authentication only, exit status 1' "$log"; then
        if [ "$asked" = yes ]; then
            echo "✓ RDP の認証が通った: $where。渡したパスワードで確かめた"
        else
            echo "✓ RDP の認証が通った: $where。仮のパスワードで確かめた(まだ変えていない)"
        fi
    elif grep -q 'ERRCONNECT_LOGON_FAILURE' "$log" && [ "$asked" = no ]; then
        echo "? RDP の認証は未検証: $where。仮のパスワードでは通らなかった(本人が変えていれば正常)。" \
            "今のパスワードで確かめるなら just verify-rdp <ホスト> --ask $user <env.yaml>..."
    else
        echo "✗ RDP の認証が通らなかった: $where(終了コード $rc)" >&2
        grep -E 'ERRCONNECT|ERROR' "$log" | grep -v -i kerberos | tail -3 >&2 || true
        failed=1
    fi
done
exit "$failed"
