#!/usr/bin/env bash
# エージェントの通知(承認待ち・エラー・完了)を Slack と IP Messenger に送る仕組みを置く。
# 送り先は env.yaml の notify。空なら送らない(hook は置いたままでよい。何もせずに終わる)。
set -euo pipefail
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"
load_env

install -m 755 "$AH_ROOT/notify/agent-notify" /usr/local/bin/agent-notify

# 送り先(Slack の Webhook の URL は秘密情報。hook は利用者で動くので、利用者のグループだけが読めるようにする)
install -d -m 755 /etc/agent-host
umask 027
{
    echo "# agent-host-autoinstall が env.yaml の notify から作った設定"
    echo "SLACK_WEBHOOK_URL=${AH_SLACK_WEBHOOK_URL:-}"
    echo "IPMSG_TO=${AH_IPMSG_TO:-}"
    echo "IPMSG_BROADCAST=${AH_IPMSG_BROADCAST:-}"
} >/etc/agent-host/notify.env
umask 022
chown "root:$AH_USERS_GROUP" /etc/agent-host/notify.env
chmod 640 /etc/agent-host/notify.env

# --- Claude Code の hooks(~/.claude/settings.json に足す。ほかの設定と hooks は残す) ---
#   Notification: 承認待ち(permission_prompt など)と、応答を終えて入力を待っているとき(idle_prompt)
#   StopFailure: API のエラーで止まったとき
notify_hooks() {
    local claude_settings codex_conf
    claude_settings="$AGENT_HOME/.claude/settings.json"
    [ -f "$claude_settings" ] || printf '{}\n' | write_agent_file 644 "$claude_settings"
    agent_run python3 - "$claude_settings" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    settings = json.load(f)
command = {"type": "command", "command": "/usr/local/bin/agent-notify --claude"}
ours = {
    "Notification": {
        "matcher": "permission_prompt|idle_prompt|elicitation_dialog|elicitation_url_dialog",
        "hooks": [command],
    },
    "StopFailure": {"hooks": [command]},
}
hooks = settings.setdefault("hooks", {})
for event, entry in ours.items():
    # 前回足した分を除いてから足す(冪等)
    kept = [e for e in hooks.get(event, [])
            if not any("agent-notify" in h.get("command", "") for h in e.get("hooks", []))]
    hooks[event] = kept + [entry]
with open(path, "w", encoding="utf-8") as f:
    json.dump(settings, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY

    # --- Codex の notify(config.toml の最上位。最初のテーブルより前に置く) ---
    codex_conf="$AGENT_HOME/.codex/config.toml"
    if [ -f "$codex_conf" ] && ! grep -q '^notify *=' "$codex_conf"; then
        agent_run python3 - "$codex_conf" <<'PY'
import sys
path = sys.argv[1]
lines = open(path, encoding="utf-8").read().splitlines()
first_table = next((i for i, l in enumerate(lines) if l.lstrip().startswith("[")), len(lines))
lines.insert(first_table, 'notify = ["/usr/local/bin/agent-notify", "--codex"]')
open(path, "w", encoding="utf-8").write("\n".join(lines) + "\n")
PY
    fi
}
for_each_user notify_hooks
log "通知(Slack${AH_SLACK_WEBHOOK_URL:+ あり}、IP Messenger${AH_IPMSG_TO:+ $AH_IPMSG_TO})を設定した"

# --- ディスクの残りの監視(1 時間ごとに見て、85% を超えたら 1 日 1 回知らせる) ---
install -m 755 "$AH_ROOT/notify/agent-host-diskcheck" /usr/local/bin/agent-host-diskcheck
cat >/etc/systemd/system/agent-host-diskcheck.service <<'EOF'
[Unit]
Description=ディスクの残りが少なければ知らせる(agent-host-autoinstall)
[Service]
Type=oneshot
ExecStart=/usr/local/bin/agent-host-diskcheck 85
EOF
cat >/etc/systemd/system/agent-host-diskcheck.timer <<'EOF'
[Unit]
Description=1 時間ごとにディスクの残りを見る(agent-host-autoinstall)
[Timer]
OnCalendar=hourly
Persistent=true
[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now agent-host-diskcheck.timer
log "ディスクの残りの監視を設定した"
