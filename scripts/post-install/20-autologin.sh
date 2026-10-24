#!/usr/bin/env bash
# GDM で agent を自動ログインさせる。
# 26.04 の gdm3 50.x でも設定ファイルは /etc/gdm3/custom.conf の [daemon](ソースで確認済み)
set -euo pipefail
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"

conf=/etc/gdm3/custom.conf
ini_set "$conf" daemon AutomaticLoginEnable true
ini_set "$conf" daemon AutomaticLogin "$AGENT_USER"
log "$conf に自動ログインを設定した"

# 自動ログインは起動時の 1 回だけ。GNOME のセッションが落ちるとログイン画面に戻り、再起動まで RDP に戻れない
# (VirtualBox で RDP の extend モードを試したとき、GNOME Shell が異常終了してそうなった)。
# TimedLogin は agent がログイン画面の一覧に出ないので効かなかった。見張りのタイマーで GDM を再起動する
sed -i '/^TimedLogin/d' "$conf"
install -m 755 "$AH_ROOT/watchdog/agent-host-session-watchdog" /usr/local/sbin/agent-host-session-watchdog
cat >/etc/systemd/system/agent-host-session-watchdog.service <<'EOF'
[Unit]
Description=agent のセッションが落ちていたら GDM を再起動する(agent-host-autoinstall)
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/agent-host-session-watchdog
EOF
cat >/etc/systemd/system/agent-host-session-watchdog.timer <<'EOF'
[Unit]
Description=1 分ごとに agent のセッションを見る(agent-host-autoinstall)
[Timer]
OnBootSec=3min
OnUnitActiveSec=1min
[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
# 構成の途中(GDM がまだ動いていない)は、見張りは何もせずに終わる
systemctl enable --now agent-host-session-watchdog.timer
log "セッションの見張り(落ちたら GDM を再起動)を設定した"
