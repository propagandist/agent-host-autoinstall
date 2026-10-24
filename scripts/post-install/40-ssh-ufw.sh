#!/usr/bin/env bash
# SSH を鍵認証のみにし、agent は SFTP 専用にする。ufw で SSH(22)・RDP(3389)・開発用のポートを社内LANだけに許可する。
set -euo pipefail
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"
load_env

# --- SSH ---
# agent はファイルのやり取り(SFTP)だけに使う。シェルに入れるのは sysadmin だけ(SPEC.md §4)
cat >/etc/ssh/sshd_config.d/10-agent-host.conf <<CONF
# agent-host-autoinstall が置いた設定
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no

Match User $AGENT_USER
    ForceCommand internal-sftp
    PermitTTY no
    AllowTcpForwarding no
    AllowAgentForwarding no
    X11Forwarding no
CONF
sshd -t
if systemctl is-active --quiet ssh; then
    systemctl reload ssh
fi
log "SSH をパスワード認証なし・root ログインなしにし、$AGENT_USER は SFTP 専用にした"

# agent に SFTP で入れる人の公開鍵(env.yaml の agent_ssh_authorized_keys)。空なら agent には入れない
if [ -s "$AH_ROOT/agent_authorized_keys" ]; then
    write_agent_file 600 "$AGENT_HOME/.ssh/authorized_keys" <"$AH_ROOT/agent_authorized_keys"
    chmod 700 "$AGENT_HOME/.ssh"
    log "$AGENT_USER に SFTP 用の公開鍵を置いた"
else
    rm -f "$AGENT_HOME/.ssh/authorized_keys"
fi

# --- ufw ---
# 許可は足すだけなので、lan_cidrs や dev_ports から外したものの規則は手で消す(ufw status numbered → ufw delete)
apt-get install -y ufw
ufw default deny incoming
ufw default allow outgoing
for cidr in $AH_LAN_CIDRS; do
    ufw allow from "$cidr" to any port 22 proto tcp
    ufw allow from "$cidr" to any port 3389 proto tcp
    for port in ${AH_DEV_PORTS:-}; do
        ufw allow from "$cidr" to any port "$port" proto tcp
    done
done
ufw --force enable
log "ufw で 22/3389${AH_DEV_PORTS:+ と $AH_DEV_PORTS} を $AH_LAN_CIDRS だけに許可した"
