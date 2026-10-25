#!/usr/bin/env bash
# unattended-upgrades をセキュリティ更新と Google Chrome のみ・自動再起動なしにする。
# apt-mark hold したパッケージ(claude-code、gh、docker-ce ほか、orca-ide、選んだときの code・google-cloud-cli・azure-cli)は更新されない。
# Chrome は Google のリポジトリに最新版しかなく固定できないので、自動で上げる(75-chrome.sh)。
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
    "Google LLC:stable";
};
Unattended-Upgrade::Automatic-Reboot "false";
EOF
log "unattended-upgrades をセキュリティ更新と Chrome のみ・自動再起動なしにした"
