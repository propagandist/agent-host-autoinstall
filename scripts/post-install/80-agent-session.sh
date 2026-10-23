#!/usr/bin/env bash
# agent のセッションの準備: 空パスワードのログインキーリング、RDP 認証情報の受け渡し、first-login の自動起動。
# デスクトップ共有の設定(grdctl)は agent のセッションの中でしか動かないので、first-login で行う。
set -euo pipefail
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"
load_env

state_dir="$AGENT_HOME/.config/agent-host"
done_mark="$state_dir/first-login.done"

# --- ログインキーリング(空パスワード = 平文) ---
# 自動ログインではキーリングが開かず、RDP の認証情報が読めない(SPEC.md §8)。
# マスターパスワードが空のキーリングは平文の形式で保存される(gnome-keyring のソースで確認済み)ので、
# その形式のファイルを最初から置いておく。既にキーリングがあるときは触らない。
# このファイルを置くだけで、自動ログイン後に grdctl set-credentials が通る(VirtualBox で確認済み)。
# 効かない環境では docs/manual-steps.md の手順でパスワードを空にする
keyrings="$AGENT_HOME/.local/share/keyrings"
if [ ! -f "$keyrings/login.keyring" ]; then
    write_agent_file 600 "$keyrings/login.keyring" <<'EOF'
[keyring]
display-name=Login
ctime=0
mtime=0
lock-on-idle=false
lock-after=false
EOF
    log "空パスワードのログインキーリングを置いた"
fi
if [ ! -f "$keyrings/default" ]; then
    printf 'login' | write_agent_file 600 "$keyrings/default"
fi

# --- 初回の案内(gnome-initial-setup)を出さない ---
# 出ると画面の前面に残り、RDP で入ったときに邪魔になる(VirtualBox で確認済み)。
# systemd user unit の条件(26.04 で確認済み):
#   --existing-user は ~/.config/gnome-initial-setup-done が無いと動く
#   --upgrade-user は ~/.config/gnome-initial-setup/upgrade-<版>-done が無いと動く
# shellcheck source=/dev/null disable=SC2153  # VERSION_ID は /etc/os-release で定義される
version_id="$(. /etc/os-release && echo "$VERSION_ID")"
for mark in gnome-initial-setup-done "gnome-initial-setup/upgrade-$version_id-done"; do
    if [ ! -f "$AGENT_HOME/.config/$mark" ]; then
        printf 'yes' | write_agent_file 644 "$AGENT_HOME/.config/$mark"
    fi
done

# --- first-login ---
if [ ! -f "$done_mark" ]; then
    # RDP の認証情報を first-login に渡す(first-login がキーリングへ移したあと消す)
    {
        printf 'RDP_USER=%q\n' "$AH_RDP_USER"
        printf 'RDP_PASSWORD=%q\n' "$AH_RDP_PASSWORD"
    } | write_agent_file 600 "$state_dir/rdp.env"

    write_agent_file 644 "$AGENT_HOME/.config/autostart/agent-host-first-login.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=agent-host first login
Exec=$AH_ROOT/first-login/first-login.sh
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF
    log "first-login の自動起動を設定した"
fi
