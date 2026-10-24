#!/usr/bin/env bash
# post-install/ のスクリプトを番号順に実行する。初回起動時に agent-host-provision.service から呼ばれる。
# 各スクリプトは冪等なので、構成を変えたあとに手で再実行してよい: sudo /opt/agent-host/provision.sh
set -euo pipefail

ah_root=/opt/agent-host
export DEBIAN_FRONTEND=noninteractive

# HTTP プロキシ(env.yaml の proxy)を、以降の apt・curl・npm に効かせる
# shellcheck source=/dev/null
. "$ah_root/env.sh"
if [ -n "${AH_PROXY_URL:-}" ]; then
    export http_proxy="$AH_PROXY_URL" https_proxy="$AH_PROXY_URL" no_proxy="$AH_NO_PROXY"
    export HTTP_PROXY="$AH_PROXY_URL" HTTPS_PROXY="$AH_PROXY_URL" NO_PROXY="$AH_NO_PROXY"
fi

# 今回の構成で使ったダウンロードを見分けるための印(download_verified が使ったファイルの時刻を新しくする)
mkdir -p /var/lib/agent-host /var/cache/agent-host
started=/var/lib/agent-host/provision-started
touch "$started"

# 自動更新(unattended-upgrades)などが dpkg を使っている間は、ロックが空くまで最大 30 分待つ。
# 入れた直後のホストや just update のときに、ロックが取れずに構成が止まった(VirtualBox で確認)
printf '%s\n' '# agent-host-autoinstall が置いた設定: dpkg のロックが空くまで待つ(provision.sh)' \
    'DPkg::Lock::Timeout "1800";' >/etc/apt/apt.conf.d/90-agent-host-lock-timeout

apt-get update
for script in "$ah_root"/post-install/[0-9]*.sh; do
    echo "[agent-host] 実行: $(basename "$script")"
    bash "$script"
done

# ダウンロードの残りを片付ける: apt のキャッシュと、今回使わなかった古い版の構成用のダウンロード
apt-get clean
find /var/cache/agent-host -type f ! -newer "$started" -delete

touch /var/lib/agent-host/provisioned
echo "[agent-host] 構成が完了した"
