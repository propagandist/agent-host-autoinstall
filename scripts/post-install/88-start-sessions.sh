#!/usr/bin/env bash
# 利用者ごとのヘッドレスのセッションを立てる。キーリング(80-agent-session.sh)と RDP(20-sessions.sh)のあとに動く。
# 立てる前に、GNOME の設定(first-login.sh)を利用者のバスで一度だけ入れる。
# 初回の構成のあいだは GDM がまだ動いていない(この構成のあとに起動する)ので、有効にするだけで、起動のときに立つ。
set -euo pipefail
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"
load_env

start_session() {
    if ! agent_run test -f "$AGENT_HOME/.config/agent-host/first-login.done"; then
        if agent_bus_run "$AH_ROOT/first-login/first-login.sh"; then
            log "$AGENT_USER の GNOME の設定を入れた"
        else
            log "$AGENT_USER の GNOME の設定に失敗した(次の構成でもう一度動く。~/.local/state/agent-host/first-login.log)"
        fi
    fi
    # 画面ロックは毎回止める。立てた直後にロックされると、パスワードのない利用者は外せない(#15 の段 0)
    agent_bus_run gsettings set org.gnome.desktop.screensaver lock-enabled false
    agent_bus_run gsettings set org.gnome.desktop.lockdown disable-lock-screen true
    systemctl enable "gnome-headless-session@$AGENT_USER.service" >/dev/null 2>&1
    if systemctl is-active --quiet gdm.service && ! systemctl is-active --quiet "gnome-headless-session@$AGENT_USER.service"; then
        systemctl start --no-block "gnome-headless-session@$AGENT_USER.service"
        log "$AGENT_USER のセッションを立てた"
    fi
}
for_each_user start_session
