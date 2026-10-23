#!/usr/bin/env bash
# SSH を鍵認証のみにし、ufw で SSH(22)と RDP(3389)を社内LANだけに許可する。
set -euo pipefail
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"
load_env

# --- SSH ---
cat >/etc/ssh/sshd_config.d/10-agent-host.conf <<'EOF'
# agent-host-autoinstall が置いた設定
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
EOF
sshd -t
if systemctl is-active --quiet ssh; then
    systemctl reload ssh
fi
log "SSH をパスワード認証なし・root ログインなしにした"

# --- ufw ---
# 許可は足すだけなので、lan_cidrs から外した範囲の規則は手で消す(ufw status numbered → ufw delete)
apt-get install -y ufw
ufw default deny incoming
ufw default allow outgoing
for cidr in $AH_LAN_CIDRS; do
    ufw allow from "$cidr" to any port 22 proto tcp
    ufw allow from "$cidr" to any port 3389 proto tcp
done
ufw --force enable
log "ufw で 22/3389 を $AH_LAN_CIDRS だけに許可した"
