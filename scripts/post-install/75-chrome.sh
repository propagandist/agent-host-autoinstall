#!/usr/bin/env bash
# Google Chrome を公式 apt リポジトリから入れ、agent の既定のブラウザにする。
# Google のリポジトリには最新版しか置かれないので、バージョンは固定しない。
# 更新は unattended-upgrades が自動で行う(50-updates.sh で許可元に足している)。
set -euo pipefail
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"

# Google の署名鍵(Google Inc. Linux Package Signing Authority)の主鍵の fingerprint
GOOGLE_KEY_FPR=EB4C1BFD4F042F6DDDCCEC917721F63BD38B4796

# パッケージは入ると自分用のリポジトリ定義 google-chrome.sources(署名鍵も同梱)を作り、
# 以後の更新はそれで行われる(156 で確認済み)。こちらの定義は最初の導入にだけ使い、導入後に消す。
if ! dpkg-query -W -f='${Status}' google-chrome-stable 2>/dev/null | grep -q 'install ok installed'; then
    keyring=/etc/apt/keyrings/google-chrome-bootstrap.gpg
    bootstrap_list=/etc/apt/sources.list.d/google-chrome-bootstrap.list
    install -d -m 755 /etc/apt/keyrings
    curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor >"$keyring.part"
    fpr="$(gpg --show-keys --with-colons "$keyring.part" | awk -F: '/^fpr/ {print $10; exit}')"
    if [ "$fpr" != "$GOOGLE_KEY_FPR" ]; then
        rm -f "$keyring.part"
        log "Google の署名鍵の fingerprint が一致しない: $fpr"
        exit 1
    fi
    mv "$keyring.part" "$keyring"
    echo "deb [arch=amd64 signed-by=$keyring] https://dl.google.com/linux/chrome/deb/ stable main" \
        >"$bootstrap_list"
    apt-get update
    apt-get install -y google-chrome-stable
    if [ -f /etc/apt/sources.list.d/google-chrome.sources ]; then
        rm -f "$bootstrap_list" "$keyring"
        apt-get update
    else
        log "注意: google-chrome.sources が作られなかったので、導入用の定義 $bootstrap_list を残す"
    fi
fi
log "Google Chrome $(dpkg-query -W -f='${Version}' google-chrome-stable) を使う"

# agent の既定のブラウザにする(~/.config/mimeapps.list)
mimeapps="$AGENT_HOME/.config/mimeapps.list"
if [ ! -f "$mimeapps" ]; then
    printf '[Default Applications]\n' | write_agent_file 644 "$mimeapps"
fi
for mime in text/html application/xhtml+xml \
    x-scheme-handler/http x-scheme-handler/https x-scheme-handler/about x-scheme-handler/unknown; do
    ini_set --as-agent "$mimeapps" "Default Applications" "$mime" google-chrome.desktop
done
log "agent の既定のブラウザを Chrome にした"
