#!/usr/bin/env bash
# post-install/ のスクリプトを番号順に実行する。初回起動時に agent-host-provision.service から、just update のときに SSH から呼ばれる。
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
# 独自の CA 証明書(env.yaml の ca_certs)を、構成の途中の取得(npm・Node.js・Python)にも使わせる。
# 05-proxy-ca.sh が書く /etc/environment は、このサービスと子のシェルには効かない。Node.js はシステムの証明書ストアを
# 見ないので、TLS を検査するプロキシの下では npm での取得が止まった(Docker で再現。Issue #6)。
# 束(ca-certificates.crt)には、05-proxy-ca.sh が update-ca-certificates で独自の CA を足す(npm はそのあとに動く)
if compgen -G "$ah_root/ca/*.crt" >/dev/null; then
    ca_bundle=/etc/ssl/certs/ca-certificates.crt
    export NODE_EXTRA_CA_CERTS="$ca_bundle" SSL_CERT_FILE="$ca_bundle" REQUESTS_CA_BUNDLE="$ca_bundle"
fi

# 今回の構成で使ったダウンロードを見分けるための印(download_verified が使ったファイルの時刻を新しくする)
mkdir -p /var/lib/agent-host /var/cache/agent-host
started=/var/lib/agent-host/provision-started
touch "$started"
# 実行中の印。最後まで成功したら消す。失敗・中断すると残り、just status と verify が「前回の実行が終わっていない」と出す
# (provisioned は「初回の構成が済んだ」の意味のまま。just update の失敗で消すと、起動のたびに構成が走り GDM が遅れる。Issue #10)
incomplete=/var/lib/agent-host/provision-incomplete
touch "$incomplete"

# 自動更新(unattended-upgrades)などが dpkg を使っている間は、ロックが空くまで最大 30 分待つ。
# 入れた直後のホストや just update のときに、ロックが取れずに構成が止まった(VirtualBox で確認)
printf '%s\n' '# agent-host-autoinstall が置いた設定: dpkg のロックが空くまで待つ(provision.sh)' \
    'DPkg::Lock::Timeout "1800";' >/etc/apt/apt.conf.d/90-agent-host-lock-timeout

for script in "$ah_root"/post-install/[0-9]*.sh; do
    echo "[agent-host] 実行: $(basename "$script")"
    bash "$script"
    # 取得元の更新は、プロキシと独自の CA を設定したあとに行う(CA を替えたあとの https の取得元のため。Issue #6)
    if [ "$(basename "$script")" = 05-proxy-ca.sh ]; then
        apt-get update
    fi
done

# ダウンロードの残りを片付ける: apt のキャッシュと、今回使わなかった古い版の構成用のダウンロード
apt-get clean
find /var/cache/agent-host -type f ! -newer "$started" -delete

touch /var/lib/agent-host/provisioned
# 最後まで成功した版を残す(BUILD-INFO は置いた版、BUILD-INFO.ok は適用に成功した版)
if [ -f "$ah_root/BUILD-INFO" ]; then
    install -m 644 "$ah_root/BUILD-INFO" /var/lib/agent-host/BUILD-INFO.ok
fi
rm -f "$incomplete"
echo "[agent-host] 構成が完了した"
