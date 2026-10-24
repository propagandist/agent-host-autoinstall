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
    # 自動更新とテレメトリを止める(既にある設定には手を入れない)
    vscode_settings="$AGENT_HOME/.config/Code/User/settings.json"
    if [ ! -f "$vscode_settings" ]; then
        write_agent_file 644 "$vscode_settings" <<'EOF'
{
    "update.mode": "none",
    "telemetry.telemetryLevel": "off"
}
EOF
    fi
    log "VS Code $VSCODE_VERSION を入れて hold した"
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
