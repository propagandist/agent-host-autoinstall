#!/usr/bin/env bash
# RDP の認証情報をキーリングに入れる(agent のセッションで動く)。
# 80-agent-session.sh(と agent-host-restore)が env.yaml の rdp を ~/.config/agent-host/rdp.env に渡し、
# これがログインのたびの自動起動で、渡されたものがあるときだけ入れて消す。first-login.sh からも呼ぶ。
# just update のときに agent がログイン中なら、80-agent-session.sh がその場でも呼ぶ(Issue #3)
set -euo pipefail

creds="$HOME/.config/agent-host/rdp.env"
[ -f "$creds" ] || exit 0
# shellcheck source=/dev/null
. "$creds"
# 認証情報はログインキーリングに保存される。キーリングがロックされているとここで失敗し、rdp.env は残る(次のログインで再試行)
grdctl rdp set-credentials "$RDP_USER" "$RDP_PASSWORD"
rm -f "$creds"
echo "[agent-host] RDP の認証情報を入れた: $(date -Is)"
