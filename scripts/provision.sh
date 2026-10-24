#!/usr/bin/env bash
# post-install/ のスクリプトを番号順に実行する。初回起動時に agent-host-provision.service から呼ばれる。
# 各スクリプトは冪等なので、構成を変えたあとに手で再実行してよい: sudo /opt/agent-host/provision.sh
set -euo pipefail

ah_root=/opt/agent-host
export DEBIAN_FRONTEND=noninteractive

# 社内のプロキシ(env.yaml の proxy)を、以降の apt・curl・npm に効かせる
# shellcheck source=/dev/null
. "$ah_root/env.sh"
if [ -n "${AH_PROXY_URL:-}" ]; then
    export http_proxy="$AH_PROXY_URL" https_proxy="$AH_PROXY_URL" no_proxy="$AH_NO_PROXY"
    export HTTP_PROXY="$AH_PROXY_URL" HTTPS_PROXY="$AH_PROXY_URL" NO_PROXY="$AH_NO_PROXY"
fi

apt-get update
for script in "$ah_root"/post-install/[0-9]*.sh; do
    echo "[agent-host] 実行: $(basename "$script")"
    bash "$script"
done

mkdir -p /var/lib/agent-host
touch /var/lib/agent-host/provisioned
echo "[agent-host] 構成が完了した"
