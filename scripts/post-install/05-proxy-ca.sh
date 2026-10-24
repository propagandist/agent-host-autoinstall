#!/usr/bin/env bash
# 社内のプロキシと CA 証明書(env.yaml の proxy / ca_certs)を OS 全体に設定する。どちらも空なら何もしない。
# 未確認: 実際のプロキシ・TLS を検査するプロキシの下での動作(VirtualBox では空の場合だけ確認)
set -euo pipefail
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"
load_env

env_file=/etc/environment
begin="# >>> agent-host-autoinstall"
end="# <<< agent-host-autoinstall"
ca_dir=/usr/local/share/ca-certificates/agent-host
ca_bundle=/etc/ssl/certs/ca-certificates.crt

# --- CA 証明書 ---
# システムの証明書ストアに足す。Node.js・Python などはシステムのストアを見ないので、環境変数で同じ束を渡す
rm -rf "$ca_dir"
if compgen -G "$AH_ROOT/ca/*.crt" >/dev/null; then
    install -d -m 755 "$ca_dir"
    install -m 644 "$AH_ROOT"/ca/*.crt "$ca_dir/"
    log "社内の CA 証明書を足した"
fi
update-ca-certificates --fresh >/dev/null

# --- /etc/environment(ログインしたセッションと SSH に効く) ---
block=""
if [ -n "${AH_PROXY_URL:-}" ]; then
    for v in http_proxy https_proxy HTTP_PROXY HTTPS_PROXY; do
        block+="$v=\"$AH_PROXY_URL\""$'\n'
    done
    block+="no_proxy=\"$AH_NO_PROXY\""$'\n'"NO_PROXY=\"$AH_NO_PROXY\""$'\n'
fi
if compgen -G "$ca_dir/*.crt" >/dev/null; then
    block+="NODE_EXTRA_CA_CERTS=\"$ca_bundle\""$'\n'
    block+="SSL_CERT_FILE=\"$ca_bundle\""$'\n'
    block+="REQUESTS_CA_BUNDLE=\"$ca_bundle\""$'\n'
fi
# 前回の分を消してから足す(冪等)
sed -i "/^$begin\$/,/^$end\$/d" "$env_file"
if [ -n "$block" ]; then
    printf '%s\n%s%s\n' "$begin" "$block" "$end" >>"$env_file"
fi
# agent の environment.d と Chrome の証明書は、agent を作ったあとの 80-agent-session.sh で置く

# --- apt ---
apt_conf=/etc/apt/apt.conf.d/80agent-host-proxy
if [ -n "${AH_PROXY_URL:-}" ]; then
    printf 'Acquire::http::Proxy "%s";\nAcquire::https::Proxy "%s";\n' "$AH_PROXY_URL" "$AH_PROXY_URL" >"$apt_conf"
else
    rm -f "$apt_conf"
fi

# --- Chrome(GNOME の設定ではなくポリシーで固定する。Chrome は 75-chrome.sh で入る) ---
chrome_policy=/etc/opt/chrome/policies/managed/agent-host-proxy.json
if [ -n "${AH_PROXY_URL:-}" ]; then
    install -d -m 755 "$(dirname "$chrome_policy")"
    bypass="$(echo "$AH_NO_PROXY" | tr ',' ';')"
    printf '{\n  "ProxyMode": "fixed_servers",\n  "ProxyServer": "%s",\n  "ProxyBypassList": "%s"\n}\n' \
        "$AH_PROXY_URL" "$bypass" >"$chrome_policy"
    log "プロキシ $AH_PROXY_URL を設定した"
else
    rm -f "$chrome_policy"
fi
