#!/usr/bin/env bash
# env.yaml の agents で選んだ追加のエージェント(opencode / copilot / antigravity)を入れる。
# Claude Code と Codex は 60-devtools.sh で必ず入れる。選ばなくなったものは消さない。
# どれも root で /opt か npm の全体に入れるので、agent からは書き換えられない(自己更新もできない)。
# そのうえで、各ツールの設定でも自動更新を止める(environment.d は agent の GNOME セッションと Orca に入る)。
set -euo pipefail
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"
load_env

# --- 固定するバージョン(上げるときはここと HANDOVER.md を直す) ---
OPENCODE_VERSION=1.19.4
COPILOT_VERSION=1.0.103
# Antigravity CLI: リリースの tar を SHA256(GitHub API の digest)で照合する
ANTIGRAVITY_VERSION=1.4.6
ANTIGRAVITY_SHA256=513c74ad3e70323839a65d8dccc6f9977b0903e5facd914cbb06be283c2bb640

selected() { [[ " ${AH_AGENTS:-} " == *" $1 "* ]]; }
env_d="$AGENT_HOME/.config/environment.d"

# --- OpenCode(MIT。モデルは API キーや OAuth で選ぶ) ---
if selected opencode; then
    npm_global opencode-ai "$OPENCODE_VERSION" opencode
    printf 'OPENCODE_DISABLE_AUTOUPDATE=1\n' | write_agent_file 644 "$env_d/62-opencode.conf"
fi

# --- GitHub Copilot CLI(Copilot の契約が要る。ログインは /login のデバイスコード) ---
if selected copilot; then
    npm_global @github/copilot "$COPILOT_VERSION" copilot
    printf 'COPILOT_AUTO_UPDATE=false\n' | write_agent_file 644 "$env_d/62-copilot.conf"
fi

# --- Antigravity CLI(Google。ログインは URL とコード。テレメトリはアカウント側の /config で切り替える) ---
if selected antigravity; then
    agy_dir="/opt/antigravity-$ANTIGRAVITY_VERSION"
    if [ ! -x "$agy_dir/antigravity" ]; then
        tarball="$AH_CACHE/agy_cli-$ANTIGRAVITY_VERSION-linux_x64.tar.gz"
        download_verified \
            "https://github.com/google-antigravity/antigravity-cli/releases/download/$ANTIGRAVITY_VERSION/agy_cli_linux_x64.tar.gz" \
            "$ANTIGRAVITY_SHA256" "$tarball"
        install -d "$agy_dir"
        tar -xzf "$tarball" -C "$agy_dir"
    fi
    # 文書のコマンド名は agy。tar の中の実行ファイル名は antigravity
    ln -sfn "$agy_dir/antigravity" /usr/local/bin/agy
    ln -sfn "$agy_dir/antigravity" /usr/local/bin/antigravity
    printf 'AGY_CLI_DISABLE_AUTO_UPDATE=true\n' | write_agent_file 644 "$env_d/62-antigravity.conf"
    log "Antigravity CLI $ANTIGRAVITY_VERSION を入れた"
fi
