#!/usr/bin/env bash
# SSH を鍵認証のみにし、利用者は SFTP 専用にする。ufw で SSH(22)・RDP(利用者ごとのポート)・開発用のポートを LAN だけに許可する。
set -euo pipefail
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"
load_env

# --- SSH ---
# 利用者はファイルのやり取り(SFTP)だけに使う。シェルに入れるのは sysadmin だけ(SPEC.md §4)。
# AllowUsers を sysadmin と今の利用者だけにする。env.yaml から外した利用者が Match User から外れて、
# 残った鍵でシェルに入れてしまうのを防ぐ(10-users.sh の期限切れと二重に止める)
users_csv="${AH_USERS// /,}"
cat >/etc/ssh/sshd_config.d/10-agent-host.conf <<CONF
# agent-host-autoinstall が置いた設定
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
AllowUsers sysadmin $AH_USERS

Match User $users_csv
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
log "SSH をパスワード認証なし・root ログインなしにし、$AH_USERS は SFTP 専用にした"

# SFTP で入れる人の公開鍵(env.yaml の users[].ssh_authorized_keys)。空なら入れない
put_keys() {
    local keys="$AH_ROOT/users/$AGENT_USER.authorized_keys"
    if [ -s "$keys" ]; then
        write_agent_file 600 "$AGENT_HOME/.ssh/authorized_keys" <"$keys"
        agent_run chmod 700 "$AGENT_HOME/.ssh"
        log "$AGENT_USER に SFTP 用の公開鍵を置いた"
    else
        agent_run rm -f "$AGENT_HOME/.ssh/authorized_keys"
    fi
}
for_each_user put_keys

# --- ufw ---
# 許可は足すだけなので、lan_cidrs や dev_ports から外したものの規則は手で消す(ufw status numbered → ufw delete)。
# 利用者のポートだけは、外した利用者の分をここで消す(コメントの agent-host-rdp:<利用者> で見分ける)
apt-get install -y ufw
ufw default deny incoming
ufw default allow outgoing
rdp_ports=()
collect_port() { rdp_ports+=("$AGENT_USER:$AH_USER_PORT"); }
for_each_user collect_port
for cidr in $AH_LAN_CIDRS; do
    ufw allow from "$cidr" to any port 22 proto tcp
    for entry in "${rdp_ports[@]}"; do
        ufw allow from "$cidr" to any port "${entry#*:}" proto tcp comment "agent-host-rdp:${entry%%:*}"
    done
    for port in ${AH_DEV_PORTS:-}; do
        ufw allow from "$cidr" to any port "$port" proto tcp
    done
    # IP Messenger の通知先を名前で探すとき、各 PC の応答を UDP 2425 番で受け取る
    if [ -n "${AH_IPMSG_TO:-}" ]; then
        ufw allow from "$cidr" to any port 2425 proto udp
    fi
done
# 外した利用者のポートと、0.2 までの 3389(コメントなし)のうち今は使わないものを消す
want_rules="$(printf '%s\n' "${rdp_ports[@]}")"
ufw status numbered | tac | while read -r line; do
    num="$(sed -n 's/^\[ *\([0-9]*\)\].*/\1/p' <<<"$line")"
    [ -n "$num" ] || continue
    owner="$(sed -n 's/.*# agent-host-rdp:\([a-z0-9-]*\).*/\1/p' <<<"$line")"
    port="$(awk '{print $1}' <<<"${line#*] }" | cut -d/ -f1)"
    if [ -n "$owner" ]; then
        grep -qx "$owner:$port" <<<"$want_rules" && continue
    elif [ "$port" = 3389 ] && ! grep -q ':3389$' <<<"$want_rules"; then
        :
    else
        continue
    fi
    ufw --force delete "$num" >/dev/null
    log "使わなくなった RDP のポートの規則を消した: ${line#*] }"
done
ufw --force enable
log "ufw で 22・RDP(${rdp_ports[*]})${AH_DEV_PORTS:+・$AH_DEV_PORTS} を $AH_LAN_CIDRS だけに許可した"
