#!/usr/bin/env bash
# OS 全体の設定: 時刻同期(NTP)、ファイル監視の上限、クラッシュ報告。
set -euo pipefail
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"
load_env

# --- 時刻同期 ---
# 26.04 は chrony(systemd-timesyncd ではない)。同期先は /etc/chrony/sources.d/*.sources から読む(確認済み)。
# env.yaml の ntp_servers を足す。Ubuntu の既定(ntp.ubuntu.com、NTS)と DHCP で配られたサーバーも残る。
# 社内から既定に届かなくても、届かない同期先が使われないだけ
ntp_sources=/etc/chrony/sources.d/agent-host.sources
if [ -n "${AH_NTP_SERVERS:-}" ]; then
    {
        echo "# agent-host-autoinstall が置いた設定(env.yaml の ntp_servers)"
        for server in $AH_NTP_SERVERS; do
            echo "server $server iburst"
        done
    } >"$ntp_sources"
    log "NTP サーバーに $AH_NTP_SERVERS を足した"
else
    rm -f "$ntp_sources"
fi
chronyc reload sources >/dev/null || log "注意: chrony に同期先を読み直させられなかった"

# --- ファイル監視の上限 ---
# worktree を並べて開発サーバーやファイル監視を動かすと、既定(メモリ量で決まる。4GB で 65536)では足りなくなる
cat >/etc/sysctl.d/60-agent-host-inotify.conf <<'EOF'
# agent-host-autoinstall が置いた設定
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 1024
EOF
sysctl -q -p /etc/sysctl.d/60-agent-host-inotify.conf
log "inotify の上限を上げた"

# --- クラッシュ報告 ---
# 何かが落ちると誰も見ていない画面に「問題が検出されました」が出て残るので、apport を止める
if [ -f /etc/default/apport ]; then
    sed -i 's/^enabled=.*/enabled=0/' /etc/default/apport
    systemctl stop apport.service 2>/dev/null || true
    log "apport を無効にした"
fi
