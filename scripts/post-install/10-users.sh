#!/usr/bin/env bash
# agent ユーザーを作る(sudo なし)。sysadmin は autoinstall の identity で作られる。
set -euo pipefail
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"

if ! id "$AGENT_USER" >/dev/null 2>&1; then
    # パスワードは設定しない(ロック状態)。GDM の自動ログインで入る
    # パスワードがロックされたユーザーでも GDM 自動ログインは通る(VirtualBox で確認済み)
    useradd --create-home --shell /bin/bash --comment "AI agent" "$AGENT_USER"
    log "$AGENT_USER を作成した"
fi

# sudo グループに入っていたら外す
if id -nG "$AGENT_USER" | tr ' ' '\n' | grep -qx sudo; then
    gpasswd -d "$AGENT_USER" sudo
fi

# Codex の認証情報(~/.codex/auth.json)が平文なので、ホームは本人だけが読めるようにする
chmod 700 "$AGENT_HOME"
