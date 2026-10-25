#!/usr/bin/env bash
# 開発に使う道具を入れる。Node.js・Codex・CCManager・Claude Code・GitHub CLI・uv・mise はバージョンを固定する。
# agent には sudo がないので、エージェントが要るものはここで入れておくか、mise / Docker で済ませる。
set -euo pipefail
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"

# --- 固定するバージョン(上げるときはここと手順書の付録「固定しているバージョン」を直す) ---
# Node.js: 公式の tar.xz を /opt に展開する(apt を経由しないので勝手に上がらない)
# v24 は 2026-10-20 に Maintenance LTS。v26 は 2026-10-28 に Active LTS になる予定
NODE_VERSION=24.22.1
NODE_SHA256=6c172a9ab6718f7b801fb5a7bd486af2ee5e32758086a04b84fcce2aa77095e6
CODEX_VERSION=0.164.0
# CCManager: Orca が使えないときに端末で使う予備の TUI(npm)
CCMANAGER_VERSION=4.4.9
# Claude Code: 公式 apt リポジトリから入れ、apt-mark hold で固定する
# (パッケージマネージャー経由の導入では Claude Code は自動更新しない。公式ドキュメントで確認済み)
CLAUDE_CODE_VERSION=2.1.308-1
CLAUDE_CODE_KEY_FPR=31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE
# GitHub CLI: 公式 apt リポジトリには最新版しかないので、リリースの .deb を SHA256 で照合して入れ、hold する
# (SHA256 はリリースの gh_<ver>_checksums.txt)
GH_VERSION=2.103.2
GH_SHA256=30463d8e1fdce73f178f76b0082b7ab0657b0740b87274890e831def647ca979
# Gitea CLI(tea): dl.gitea.com の単体のバイナリを SHA256 で照合する(SHA256 は同じ場所の .sha256)
TEA_VERSION=0.16.0
TEA_SHA256=9c142c8a0b31485eea2387031c1c404f12b7141075eb4ffbd7ced49441590636
# uv(Python のパッケージ管理)と mise(プロジェクトごとの言語のバージョン)。リリースの tar を SHA256 で照合する
# (SHA256 は GitHub API のアセットの digest)
UV_VERSION=0.13.5
UV_SHA256=f68d291c75783122dad58ab77def0e13f3233f358731db5d6d7e8715603b928f
MISE_VERSION=2026.10.18
MISE_SHA256=0d41b60745a6273a80089c86f80d8729042d2f57f87fda70aecc7d1c3ffbd3be

# エージェントがよく使う道具
#   ビルド: build-essential、python3-dev、pkg-config、libssl-dev(pip / npm のネイティブのモジュール)
#   小物: ripgrep、fd-find、jq、tree、htop、tmux、sqlite3、shellcheck、zip/unzip、wget、rsync
#   その他: python-is-python3(`python` を python3 にする。Windows や setup-python を前提に書かれた手順のため)、
#           git-lfs、wl-clipboard(クリップボード)、dnsutils・netcat-openbsd(ネットワークの調査)、
#           libnss3-tools(Chrome に CA 証明書を登録する certutil)
apt-get install -y git curl ca-certificates gnupg xz-utils openssl \
    build-essential python3-dev python3-venv python3-pip python-is-python3 pkg-config libssl-dev \
    ripgrep fd-find jq tree htop tmux sqlite3 shellcheck zip unzip wget rsync \
    git-lfs wl-clipboard dnsutils netcat-openbsd libnss3-tools

# --- GitHub CLI ---
if [ "$(dpkg-query -W -f='${Version}' gh 2>/dev/null || true)" != "$GH_VERSION" ]; then
    deb="$AH_CACHE/gh_${GH_VERSION}_linux_amd64.deb"
    download_verified \
        "https://github.com/cli/cli/releases/download/v$GH_VERSION/gh_${GH_VERSION}_linux_amd64.deb" \
        "$GH_SHA256" "$deb"
    apt-get install -y --allow-downgrades --allow-change-held-packages "$deb"
fi
apt-mark hold gh
log "GitHub CLI $GH_VERSION を入れて hold した"

# --- Gitea CLI(tea) ---
tea_bin="/opt/tea-$TEA_VERSION/tea"
if [ ! -x "$tea_bin" ]; then
    download_verified \
        "https://dl.gitea.com/tea/$TEA_VERSION/tea-$TEA_VERSION-linux-amd64" \
        "$TEA_SHA256" "$AH_CACHE/tea-$TEA_VERSION-linux-amd64"
    install -D -m 755 "$AH_CACHE/tea-$TEA_VERSION-linux-amd64" "$tea_bin"
fi
ln -sfn "$tea_bin" /usr/local/bin/tea
log "Gitea CLI $TEA_VERSION を入れた"

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

# pnpm / yarn(Node.js 同梱の corepack。プロジェクトの packageManager の版を使う)
"$node_dir/bin/corepack" enable --install-directory /usr/local/bin

# --- npm で入れる CLI(版を固定。npm_global は lib/common.sh) ---
npm_global @openai/codex "$CODEX_VERSION" codex
npm_global ccmanager "$CCMANAGER_VERSION" ccmanager

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

# --- uv ---
uv_dir="/opt/uv-$UV_VERSION"
if [ ! -x "$uv_dir/uv" ]; then
    tarball="$AH_CACHE/uv-$UV_VERSION-x86_64-unknown-linux-gnu.tar.gz"
    download_verified \
        "https://github.com/astral-sh/uv/releases/download/$UV_VERSION/uv-x86_64-unknown-linux-gnu.tar.gz" \
        "$UV_SHA256" "$tarball"
    install -d "$uv_dir"
    tar -xzf "$tarball" -C "$uv_dir" --strip-components=1
fi
for bin in uv uvx; do
    ln -sfn "$uv_dir/$bin" "/usr/local/bin/$bin"
done
log "uv $UV_VERSION を入れた"

# --- mise ---
# 言語の実体は agent が自分のホーム(~/.local/share/mise)に入れる。有効化は 80-agent-session.sh
mise_dir="/opt/mise-$MISE_VERSION"
if [ ! -x "$mise_dir/bin/mise" ]; then
    tarball="$AH_CACHE/mise-v$MISE_VERSION-linux-x64.tar.gz"
    download_verified \
        "https://github.com/jdx/mise/releases/download/v$MISE_VERSION/mise-v$MISE_VERSION-linux-x64.tar.gz" \
        "$MISE_SHA256" "$tarball"
    install -d "$mise_dir"
    tar -xzf "$tarball" -C "$mise_dir" --strip-components=1
fi
ln -sfn "$mise_dir/bin/mise" /usr/local/bin/mise
log "mise $MISE_VERSION を入れた"
