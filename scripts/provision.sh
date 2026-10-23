#!/usr/bin/env bash
# post-install/ のスクリプトを番号順に実行する。初回起動時に agent-host-provision.service から呼ばれる。
# 各スクリプトは冪等なので、構成を変えたあとに手で再実行してよい: sudo /opt/agent-host/provision.sh
set -euo pipefail

ah_root=/opt/agent-host
export DEBIAN_FRONTEND=noninteractive

apt-get update
for script in "$ah_root"/post-install/[0-9]*.sh; do
    echo "[agent-host] 実行: $(basename "$script")"
    bash "$script"
done

mkdir -p /var/lib/agent-host
touch /var/lib/agent-host/provisioned
echo "[agent-host] 構成が完了した"
