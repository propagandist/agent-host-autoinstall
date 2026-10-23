#!/usr/bin/env bash
# git、Node.js、Codex、Claude Code を固定バージョンで入れる。
set -euo pipefail
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"

# --- 固定するバージョン(上げるときはここと HANDOVER.md を直す) ---
# Node.js: 公式の tar.xz を /opt に展開する(apt を経由しないので勝手に上がらない)
# v24 は 2026-10-20 に Maintenance LTS。v26 は 2026-10-28 に Active LTS になる予定
NODE_VERSION=24.22.1
NODE_SHA256=6c172a9ab6718f7b801fb5a7bd486af2ee5e32758086a04b84fcce2aa77095e6
CODEX_VERSION=0.164.0
# Claude Code: 公式 apt リポジトリから入れ、apt-mark hold で固定する
# (パッケージマネージャー経由の導入では Claude Code は自動更新しない。公式ドキュメントで確認済み)
CLAUDE_CODE_VERSION=2.1.308-1
CLAUDE_CODE_KEY_FPR=31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE

apt-get install -y git curl ca-certificates gnupg xz-utils openssl

# --- Node.js ---
node_dir="/opt/node-v$NODE_VERSION-linux-x64"
if [ ! -x "$node_dir/bin/node" ]; then
    tarball="$AH_CACHE/node-v$NODE_VERSION-linux-x64.tar.xz"
    download_verified \
        "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-linux-x64.tar.xz" \
        "$NODE_SHA256" "$tarball"
    tar -xJf "$tarball" -C /opt
fi
for bin in node npm npx; do
    ln -sfn "$node_dir/bin/$bin" "/usr/local/bin/$bin"
done
log "Node.js $("$node_dir/bin/node" --version) を使う"

# --- Codex ---
if [ "$("$node_dir/bin/npm" ls -g --depth=0 --json @openai/codex 2>/dev/null \
        | python3 -c 'import json,sys; print(json.load(sys.stdin).get("dependencies",{}).get("@openai/codex",{}).get("version",""))')" \
        != "$CODEX_VERSION" ]; then
    "$node_dir/bin/npm" install -g "@openai/codex@$CODEX_VERSION"
fi
ln -sfn "$node_dir/bin/codex" /usr/local/bin/codex
log "Codex $CODEX_VERSION を入れた"

# 起動時の更新確認を止める(既にある config.toml には手を入れない)
codex_conf="$AGENT_HOME/.codex/config.toml"
if [ ! -f "$codex_conf" ]; then
    write_agent_file 600 "$codex_conf" <<'EOF'
# agent-host-autoinstall が置いた設定。バージョンは 60-devtools.sh で固定している
check_for_update_on_startup = false
EOF
elif ! grep -q '^check_for_update_on_startup' "$codex_conf"; then
    log "注意: $codex_conf に check_for_update_on_startup = false を手で足す(先頭のテーブルより前に)"
fi

# --- Claude Code ---
keyring=/etc/apt/keyrings/claude-code.gpg
if [ ! -f "$keyring" ]; then
    install -d -m 755 /etc/apt/keyrings
    curl -fsSL https://downloads.claude.ai/keys/claude-code.asc | gpg --dearmor >"$keyring.part"
    fpr="$(gpg --show-keys --with-colons "$keyring.part" | awk -F: '/^fpr/ {print $10; exit}')"
    if [ "$fpr" != "$CLAUDE_CODE_KEY_FPR" ]; then
        rm -f "$keyring.part"
        log "Claude Code の署名鍵の fingerprint が一致しない: $fpr"
        exit 1
    fi
    mv "$keyring.part" "$keyring"
fi
echo "deb [signed-by=$keyring] https://downloads.claude.ai/claude-code/apt/stable stable main" \
    >/etc/apt/sources.list.d/claude-code.list
apt-get update
if [ "$(dpkg-query -W -f='${Version}' claude-code 2>/dev/null || true)" != "$CLAUDE_CODE_VERSION" ]; then
    apt-get install -y --allow-downgrades --allow-change-held-packages "claude-code=$CLAUDE_CODE_VERSION"
fi
apt-mark hold claude-code
log "Claude Code $CLAUDE_CODE_VERSION を入れて hold した"
