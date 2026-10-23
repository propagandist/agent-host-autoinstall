#!/usr/bin/env bash
# unattended-upgrades をセキュリティ更新のみ・自動再起動なしにする。
# apt-mark hold したパッケージ(claude-code, orca-ide)は更新されない。
set -euo pipefail
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"

apt-get install -y unattended-upgrades

cat >/etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

# 50unattended-upgrades の許可元を消してから、セキュリティだけを許可する
cat >/etc/apt/apt.conf.d/52agent-host-unattended-upgrades <<'EOF'
// agent-host-autoinstall が置いた設定
#clear Unattended-Upgrade::Allowed-Origins;
#clear Unattended-Upgrade::Origins-Pattern;
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::Automatic-Reboot "false";
EOF
log "unattended-upgrades をセキュリティ更新のみ・自動再起動なしにした"
