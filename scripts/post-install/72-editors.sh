#!/usr/bin/env bash
# env.yaml の editors で選んだエディターを入れる(vscode / neovim / zed)。
# 選ばなくなったエディターは消さない(消すときは手で apt purge や rm をする)。
set -euo pipefail
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"
load_env

# --- 固定するバージョン(上げるときはここと手順書の付録「固定しているバージョン」を直す) ---
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
# Zed の拡張機能(zed.dev の ID。版は指定できない)。Python(basedpyright と Ruff)・JavaScript・TypeScript・YAML・JSON・Markdown・Go・Rust・Bash、
# ESLint・Prettier・EditorConfig には Zed が最初から対応している。Claude Code と Codex はエージェントの画面から使える
ZED_EXTENSIONS=(toml dockerfile docker-compose html make sql env git-firefly)

selected() { [[ " ${AH_EDITORS:-} " == *" $1 "* ]]; }
cloud_selected() { [[ " ${AH_CLOUDS:-} " == *" $1 "* ]]; }

# agent のエディターの設定(JSON)に、足りない項目だけ足す。値が {} の項目は中の足りないキーだけ足す。
# 人が変えた値は変えない。コメント入りなど JSON として読めないときは触らない
merge_agent_json() {
    local path="$1" wanted="$2"
    if [ ! -f "$path" ]; then
        printf '{}\n' | write_agent_file 644 "$path"
    fi
    agent_run python3 - "$path" "$wanted" <<'EOF'
import json
import sys

path, wanted = sys.argv[1], json.loads(sys.argv[2])
try:
    with open(path, encoding="utf-8") as f:
        settings = json.load(f)
except ValueError:
    print(f"{path} は JSON として読めないので触らない", file=sys.stderr)
    sys.exit(0)
changed = False
for key, value in wanted.items():
    if key not in settings:
        settings[key] = value
        changed = True
    elif isinstance(value, dict) and isinstance(settings[key], dict):
        for sub, v in value.items():
            if sub not in settings[key]:
                settings[key][sub] = v
                changed = True
if changed:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(settings, f, indent=2, ensure_ascii=False)
        f.write("\n")
EOF
}

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
    # 本体と拡張機能の自動更新、テレメトリを止める(redhat.telemetry.enabled は YAML の拡張機能が初回に聞いてくるもの)
    merge_agent_json "$AGENT_HOME/.config/Code/User/settings.json" \
        '{"update.mode": "none", "telemetry.telemetryLevel": "off",
          "extensions.autoUpdate": false, "extensions.autoCheckUpdates": false,
          "redhat.telemetry.enabled": false}'
    log "VS Code $VSCODE_VERSION を入れて hold した"

    # --- VS Code の拡張機能 ---
    # agent のホーム(~/.vscode/extensions)に、版を固定して入れる。選ばなくなったものは消さない
    exts=("${VSCODE_EXTENSIONS[@]}")
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
    # 表示を日本語にする(Language Pack は入れただけでは効かない。「表示言語を構成する」と同じく argv.json に書く)。
    # argv.json はコメント入りなので JSON として書き換えず、locale がないときだけ { の次の行に足す
    argv="$AGENT_HOME/.vscode/argv.json"
    if [ ! -f "$argv" ]; then
        printf '{\n\t"locale": "ja"\n}\n' | write_agent_file 644 "$argv"
    elif ! grep -q '"locale"' "$argv"; then
        agent_run sed -i '0,/{/s//{\n\t"locale": "ja",/' "$argv"
    fi
    # 入っている Language Pack の一覧(~/.config/Code/languagepacks.json)は、VS Code が最初の起動の途中で作る。
    # 表示言語は起動の最初に決まるので、そのままだと最初の起動だけ英語になる(VirtualBox で確認)。
    # VS Code と同じ形で先に作っておく。hash は UUID と版をつなげた MD5(VS Code が作ったものと一致を確認)。
    # 既にあれば触らない(以後は VS Code が保つ)
    lp_json="$AGENT_HOME/.config/Code/languagepacks.json"
    if [ ! -f "$lp_json" ]; then
        runuser -u "$AGENT_USER" -- python3 - "$AGENT_HOME/.vscode/extensions" "$lp_json" <<'EOF'
import glob
import hashlib
import json
import os
import sys

ext_root, out = sys.argv[1], sys.argv[2]
with open(os.path.join(ext_root, "extensions.json"), encoding="utf-8") as f:
    installed = json.load(f)
packs = {}
for entry in installed:
    ident = entry["identifier"]
    if not ident["id"].lower().startswith("ms-ceintl.vscode-language-pack-"):
        continue
    location = entry["location"]["path"]
    with open(os.path.join(location, "package.json"), encoding="utf-8") as f:
        pkg = json.load(f)
    for loc in pkg.get("contributes", {}).get("localizations", []):
        lang = loc["languageId"].lower()
        version = entry["version"]
        packs[lang] = {
            "hash": hashlib.md5((ident.get("uuid", "") + version).encode()).hexdigest(),
            "extensions": [{"extensionIdentifier": {"id": ident["id"].lower(), "uuid": ident.get("uuid")},
                            "version": version}],
            "translations": {t["id"]: os.path.normpath(os.path.join(location, t["path"])) for t in loc.get("translations", [])},
            "label": loc.get("localizedLanguageName") or loc.get("languageName") or lang,
        }
if packs:
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(packs, f, ensure_ascii=False)
EOF
    fi
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
    # 拡張機能: Zed には版を指定して入れる方法がない。auto_install_extensions に書くと、次に Zed を起動したときに
    # そのときの最新が入る。入ったあとは auto_update_extensions で更新を止める
    zed_exts=("${ZED_EXTENSIONS[@]}")
    [ -n "${AH_CLOUDS:-}" ] && zed_exts+=(terraform)
    for ext in ${AH_ZED_EXTENSIONS:-}; do zed_exts+=("$ext"); done
    zed_wanted="$(printf '%s\n' "${zed_exts[@]}" | python3 -c '
import json, sys
names = [n for n in sys.stdin.read().split() if n]
print(json.dumps({
    "auto_update": False,
    "telemetry": {"diagnostics": False, "metrics": False},
    "auto_install_extensions": {n: True for n in names},
    "auto_update_extensions": {n: False for n in names},
}))')"
    # 本体の自動更新とテレメトリも止める
    merge_agent_json "$AGENT_HOME/.config/zed/settings.json" "$zed_wanted"
    log "Zed $ZED_VERSION を入れた(拡張機能 ${#zed_exts[@]} 個は次の起動で入る)"
fi
