#!/usr/bin/env bash
# late-commands から curtin in-target で呼ぶ。初回起動時の構成サービスを有効にするだけ。
set -euo pipefail

ah_root=/opt/agent-host

# first-login は agent が実行するので、スクリプトは誰でも読めるようにする。秘密情報は env.sh だけ
chown -R root:root "$ah_root"
chmod -R u=rwX,go=rX "$ah_root"
chmod 600 "$ah_root/env.sh"

install -m 644 "$ah_root/systemd/agent-host-provision.service" \
    /etc/systemd/system/agent-host-provision.service
systemctl enable agent-host-provision.service
