#!/usr/bin/env bash
# env.yaml の editors で選んだエディターを入れる(vscode / neovim / zed)。
# 選ばなくなったエディターは消さない(消すときは手で apt purge や rm をする)。
set -euo pipefail
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"
load_env

# --- 固定するバージョン(上げるときはここと HANDOVER.md を直す) ---
# VS Code: Microsoft の公式 apt リポジトリ(過去の版も残る)から版を指定して入れ、hold する
VSCODE_VERSION=1.143.1-1792691907
MICROSOFT_KEY_FPR=BC528686B50D79E339D3721CEB3E94ADBE1229CF
# VS Code の拡張機能(Marketplace の正式版のうち、VS Code の上の版で使える最新。ID@版)
VSCODE_EXTENSIONS=(
    # 基本
    MS-CEINTL.vscode-language-pack-ja@1.131.2026090407
    anthropic.claude-code@2.1.310
    openai.chatgpt@26.1021.22027
    EditorConfig.EditorConfig@0.18.2
    redhat.vscode-yaml@2.0.0
    tamasfe.even-better-toml@0.21.2
    timonwong.shellcheck@0.48.3
    ms-azuretools.vscode-containers@2.5.3
    mhutchie.git-graph@1.30.0
    GitHub.vscode-pull-request-github@0.172.0
    # Python と JavaScript・TypeScript
    ms-python.python@2026.10.0
    ms-python.vscode-pylance@2026.4.1
    charliermarsh.ruff@2026.90.0
    dbaeumer.vscode-eslint@3.0.34
    esbenp.prettier-vscode@12.4.0
)
# env.yaml の clouds で選んだクラウドに合わせて足す(Terraform はどれかを選んだとき)。
# Google Cloud Code は Gemini Code Assist と Data Cloud を必ず一緒に入れる(合わせて約 610MB。依存の版は入れたときの最新)。
# Azure は、12 個のまとめ(Azure Tools。Windows AI Studio や Jupyter まで入り約 600MB)ではなく、土台の Azure Resources だけにする
VSCODE_EXT_AWS=AmazonWebServices.aws-toolkit-vscode@4.17.0
VSCODE_EXT_GCP=GoogleCloudTools.cloudcode@2.41.0
VSCODE_EXT_AZURE=ms-azuretools.vscode-azureresourcegroups@0.13.2
VSCODE_EXT_TERRAFORM=HashiCorp.terraform@2.40.0
# Zed: リリースの tar を SHA256(GitHub API の digest)で照合して /opt に置く
ZED_VERSION=1.25.3
ZED_SHA256=35f9115acd8b4c3bea6ed20f7c9b6ec8f1d2c2dd5a1cc438d552167b5ed4b342

selected() { [[ " ${AH_EDITORS:-} " == *" $1 "* ]]; }

# --- VS Code ---
if selected vscode; then
    keyring=/etc/apt/keyrings/microsoft.gpg
    if [ ! -f "$keyring" ]; then
        install -d -m 755 /etc/apt/keyrings
        curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor >"$keyring.part"
        fpr="$(gpg --show-keys --with-colons "$keyring.part" | awk -F: '/^fpr/ {print $10; exit}')"
        if [ "$fpr" != "$MICROSOFT_KEY_FPR" ]; then
            rm -f "$keyring.part"
            log "Microsoft の署名鍵の fingerprint が一致しない: $fpr"
            exit 1
        fi
        mv "$keyring.part" "$keyring"
    fi
    echo "deb [arch=amd64 signed-by=$keyring] https://packages.microsoft.com/repos/code stable main" \
        >/etc/apt/sources.list.d/vscode-agent-host.list
    # パッケージが自分でリポジトリ定義を足さないようにする(定義はこのスクリプトが持つ)
    echo "code code/add-microsoft-repo boolean false" | debconf-set-selections
    apt-get update
    if [ "$(dpkg-query -W -f='${Version}' code 2>/dev/null || true)" != "$VSCODE_VERSION" ]; then
        apt-get install -y --allow-downgrades --allow-change-held-packages "code=$VSCODE_VERSION"
    fi
    apt-mark hold code
    # 本体と拡張機能の自動更新、テレメトリを止める。既にある設定は、足りない項目だけ足す
    # (コメント入りなど JSON として読めないときは触らない)
    vscode_settings="$AGENT_HOME/.config/Code/User/settings.json"
    if [ ! -f "$vscode_settings" ]; then
        printf '{}\n' | write_agent_file 644 "$vscode_settings"
    fi
    python3 - "$vscode_settings" <<'EOF'
import json
import sys

path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as f:
        settings = json.load(f)
except ValueError:
    sys.exit(0)
wanted = {
    "update.mode": "none",
    "telemetry.telemetryLevel": "off",
    "extensions.autoUpdate": False,
    "extensions.autoCheckUpdates": False,
    "redhat.telemetry.enabled": False,  # YAML の拡張機能が初回に聞いてくるのを止める
}
missing = {k: v for k, v in wanted.items() if k not in settings}
if missing:
    settings.update(missing)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(settings, f, indent=4, ensure_ascii=False)
        f.write("\n")
EOF
    log "VS Code $VSCODE_VERSION を入れて hold した"

    # --- VS Code の拡張機能 ---
    # agent のホーム(~/.vscode/extensions)に、版を固定して入れる。選ばなくなったものは消さない
    exts=("${VSCODE_EXTENSIONS[@]}")
    cloud_selected() { [[ " ${AH_CLOUDS:-} " == *" $1 "* ]]; }
    cloud_selected aws && exts+=("$VSCODE_EXT_AWS")
    cloud_selected gcp && exts+=("$VSCODE_EXT_GCP")
    cloud_selected azure && exts+=("$VSCODE_EXT_AZURE")
    [ -n "${AH_CLOUDS:-}" ] && exts+=("$VSCODE_EXT_TERRAFORM")
    # env.yaml の vscode_extensions(ID か ID@版。版を書かなければ、初めて入れたときの最新)
    for ext in ${AH_VSCODE_EXTENSIONS:-}; do exts+=("$ext"); done
    agent_code() { runuser -u "$AGENT_USER" -- env HOME="$AGENT_HOME" code "$@"; }
    installed="$(agent_code --list-extensions --show-versions 2>/dev/null | tr '[:upper:]' '[:lower:]')"
    for ext in "${exts[@]}"; do
        lower="$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')"
        if [[ "$ext" == *@* ]]; then
            grep -qxF "$lower" <<<"$installed" && continue
        else
            grep -q "^${lower}@" <<<"$installed" && continue
        fi
        agent_code --install-extension "$ext" --force >/dev/null
    done
    log "VS Code の拡張機能を入れた(${#exts[@]} 個)"
fi

# --- Neovim(Ubuntu の公式パッケージ。OS の更新に任せる) ---
if selected neovim; then
    apt-get install -y neovim
    log "Neovim を入れた"
fi

# --- Zed ---
# GPU(Vulkan)が要る。GPU のない環境ではソフトウェア描画で遅くなる(未確認)
if selected zed; then
    zed_dir="/opt/zed-$ZED_VERSION"
    if [ ! -x "$zed_dir/zed.app/bin/zed" ]; then
        tarball="$AH_CACHE/zed-$ZED_VERSION-linux-x86_64.tar.gz"
        download_verified \
            "https://github.com/zed-industries/zed/releases/download/v$ZED_VERSION/zed-linux-x86_64.tar.gz" \
            "$ZED_SHA256" "$tarball"
        install -d "$zed_dir"
        tar -xzf "$tarball" -C "$zed_dir"
    fi
    ln -sfn "$zed_dir/zed.app/bin/zed" /usr/local/bin/zed
    # デスクトップファイルは Exec=zed(PATH から探す)なので、そのまま置ける
    install -m 644 "$zed_dir/zed.app/share/applications/dev.zed.Zed.desktop" /usr/share/applications/
    install -D -m 644 "$zed_dir/zed.app/share/icons/hicolor/512x512/apps/zed.png" \
        /usr/share/icons/hicolor/512x512/apps/zed.png
    # 自動更新とテレメトリを止める(既にある設定には手を入れない)
    zed_settings="$AGENT_HOME/.config/zed/settings.json"
    if [ ! -f "$zed_settings" ]; then
        write_agent_file 644 "$zed_settings" <<'EOF'
{
  "auto_update": false,
  "telemetry": { "diagnostics": false, "metrics": false }
}
EOF
    fi
    log "Zed $ZED_VERSION を入れた"
fi
