#!/usr/bin/env bash
# env.yaml の llm で、エージェントからローカル LLM を使えるようにする。
#   local:  このホストで Ollama を動かし(127.0.0.1:11434 だけで待ち受ける)、llm.models を取得する
#   remote: LAN の Ollama 互換のサーバー(llm.url)につなぐ設定だけを置く(このホストでは推論しない)
#   none:   Ollama を止め、エージェントの設定から外す(入れた Ollama と取得したモデルは消さない)
# エージェントの既定(サブスクリプション)は変えない。使うときだけ選ぶ:
#   Claude Code: claude-local(ANTHROPIC_BASE_URL を差し替えて claude を起動する。Ollama の Anthropic 互換の API)
#   Codex:       codex --profile local(OpenAI 互換の Responses API)
#   OpenCode:    モデル agent-host-llm/<名前>(OpenAI 互換の Chat Completions。agents に opencode を選んだとき)
# 未確認: Intel・AMD の内蔵 GPU での推論(Ollama は既定で内蔵 GPU を使わず CPU で動く)。docs/notes.md
set -euo pipefail
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"
load_env

# --- 固定するバージョン(上げるときはここと手順書の付録「固定しているバージョン」を直す) ---
# Ollama: リリースの tar(CUDA と Vulkan のライブラリを含む)を SHA256(GitHub API の digest)で照合する
OLLAMA_VERSION=0.40.13
OLLAMA_SHA256=c9490e0f520be21271d969e6703f012268b1d39f8b70dd58854e5bfef7a75bb6

mode="${AH_LLM_MODE:-none}"
unit=agent-host-ollama.service
llm_env=/etc/agent-host/llm.env
api=http://127.0.0.1:11434

# --- Ollama(local) ---
if [ "$mode" = local ]; then
    apt-get install -y zstd
    dir="/opt/ollama-$OLLAMA_VERSION"
    if [ ! -x "$dir/bin/ollama" ]; then
        tarball="$AH_CACHE/ollama-linux-amd64-$OLLAMA_VERSION.tar.zst"
        download_verified \
            "https://github.com/ollama/ollama/releases/download/v$OLLAMA_VERSION/ollama-linux-amd64.tar.zst" \
            "$OLLAMA_SHA256" "$tarball"
        # 展開の途中で止まっても半端なものを使わないように、別の名前に展開してから置き換える
        rm -rf "$dir.part"
        install -d "$dir.part"
        tar --zstd -xf "$tarball" -C "$dir.part"
        mv -T "$dir.part" "$dir"
    fi
    # ollama は実行ファイルの実体の場所(../lib/ollama)からライブラリを探す
    ln -sfn "$dir/bin/ollama" /usr/local/bin/ollama

    if ! id ollama >/dev/null 2>&1; then
        useradd --system --user-group --home-dir /var/lib/ollama --shell /usr/sbin/nologin ollama
    fi
    install -d -m 750 -o ollama -g ollama /var/lib/ollama /var/lib/ollama/models
    install -d -m 755 /etc/agent-host
    {
        echo "# agent-host-autoinstall(64-llm.sh)が env.yaml の llm から作った Ollama の設定"
        # エージェントには 64k 以上の文脈が要る(Ollama の既定は GPU のメモリで 4k〜256k に変わる)
        echo "OLLAMA_CONTEXT_LENGTH=$AH_LLM_CONTEXT_LENGTH"
        # 使い終わってからメモリに残す時間。過ぎたら外して利用者のセッションに返す
        echo "OLLAMA_KEEP_ALIVE=10m"
    } >/etc/agent-host/ollama.env
    install -m 644 "$AH_ROOT/systemd/$unit" "/etc/systemd/system/$unit"
    systemctl daemon-reload
    systemctl enable "$unit"
    # 版や設定が変わっていれば読み直させる(載っているモデルは外れる)
    systemctl restart "$unit"
    for _ in $(seq 60); do
        curl -fsS --noproxy '*' "$api/api/version" >/dev/null 2>&1 && break
        sleep 1
    done
    curl -fsS --noproxy '*' "$api/api/version" >/dev/null || { log "Ollama が応えない(journalctl -u $unit)"; exit 1; }
    log "Ollama $OLLAMA_VERSION を動かした(127.0.0.1:11434)"

    # モデルは、まだないものだけを取得する(タグの指す版は動くので、取得した時点の版を使い続ける。
    # 新しくするときは手で ollama pull する)。選ばなくなったものは消さない
    export OLLAMA_HOST=127.0.0.1:11434
    # ollama の CLI は $HOME がないと panic する(構成のサービスには HOME がない。2026-11-14 に VM で確認)
    export HOME="${HOME:-/root}"
    for m in $AH_LLM_MODELS; do
        if ollama show "$m" >/dev/null 2>&1; then
            log "モデル $m はもうある"
        else
            log "モデル $m を取得する(数 GB〜数十 GB)"
            # 進み具合の表示は長いので、失敗したときだけ最後を見せる
            if ! ollama pull "$m" >"$AH_CACHE/ollama-pull.log" 2>&1; then
                # 落ちたとき(panic)は 1 行目に、取得の失敗は最後に理由が出る
                tr '\r' '\n' <"$AH_CACHE/ollama-pull.log" | sed -n '1p'
                tr '\r' '\n' <"$AH_CACHE/ollama-pull.log" | tail -n 2
                log "モデル $m を取得できない(名前・プロキシ・ディスクの残りを確かめる)"
                exit 1
            fi
            log "モデル $m を取得した"
        fi
    done
    while read -r name _; do
        [ -n "$name" ] || continue
        # タグを書かなかったモデルは :latest として並ぶ
        if [[ " $AH_LLM_MODELS " != *" $name "* && " $AH_LLM_MODELS " != *" ${name%:latest} "* ]]; then
            log "注意: モデル $name は env.yaml の llm.models にない(消すなら ollama rm $name)"
        fi
    done < <(ollama list 2>/dev/null | tail -n +2)
elif [ -f "/etc/systemd/system/$unit" ]; then
    # none・remote ではこのホストで推論しない。入れたものとモデル(/var/lib/ollama)は残す
    systemctl disable --now "$unit" 2>/dev/null || true
    log "Ollama を止めた(llm.mode が $mode。モデルは /var/lib/ollama に残っている)"
fi

# --- 接続先(claude-local が読む。api_key を含むので、root と利用者だけが読める) ---
if [ "$mode" = none ]; then
    rm -f "$llm_env" /usr/local/bin/claude-local
else
    install -d -m 755 /etc/agent-host
    umask 027
    {
        echo "# agent-host-autoinstall(64-llm.sh)が env.yaml の llm から作った接続先"
        # 値は render-autoinstall.py が引用符・空白を含まないことを確かめている
        echo "AGENT_HOST_LLM_URL='$AH_LLM_URL'"
        echo "AGENT_HOST_LLM_MODEL='$AH_LLM_DEFAULT_MODEL'"
        echo "AGENT_HOST_LLM_API_KEY='${AH_LLM_API_KEY:-}'"
    } >"$llm_env"
    umask 022
    chown "root:$AH_USERS_GROUP" "$llm_env"
    chmod 640 "$llm_env"

    cat >/usr/local/bin/claude-local <<'EOF'
#!/bin/sh
# Claude Code を env.yaml の llm のサーバー(Ollama の Anthropic 互換の API)で起動する(agent-host-autoinstall の 64-llm.sh)。
# ふだんの claude(サブスクリプション)は変えない。モデルは --model で替えられる(ollama list の名前)
set -eu
. /etc/agent-host/llm.env
export ANTHROPIC_BASE_URL="$AGENT_HOST_LLM_URL"
export ANTHROPIC_AUTH_TOKEN="${AGENT_HOST_LLM_API_KEY:-ollama}"
export ANTHROPIC_API_KEY=""
export ANTHROPIC_MODEL="$AGENT_HOST_LLM_MODEL"
export ANTHROPIC_DEFAULT_OPUS_MODEL="$AGENT_HOST_LLM_MODEL"
export ANTHROPIC_DEFAULT_SONNET_MODEL="$AGENT_HOST_LLM_MODEL"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="$AGENT_HOST_LLM_MODEL"
export CLAUDE_CODE_SUBAGENT_MODEL="$AGENT_HOST_LLM_MODEL"
# Anthropic への利用状況の送信などを止める(ローカルの LLM だけと話す)
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
exec claude "$@"
EOF
    chmod 755 /usr/local/bin/claude-local
    auth=()
    [ -z "${AH_LLM_API_KEY:-}" ] || auth=(-H "Authorization: Bearer $AH_LLM_API_KEY")
    if curl -fsS -m 10 "${auth[@]}" "$AH_LLM_URL/api/version" >/dev/null 2>&1; then
        log "LLM のサーバー $AH_LLM_URL に届く"
    else
        log "注意: LLM のサーバー $AH_LLM_URL に届かない(サーバーが動いているか、ufw・プロキシを確かめる)"
    fi
fi

# --- API キー(remote で要るとき。Codex の env_key と OpenCode の {env:...} が読む) ---
if [ -n "${AH_LLM_API_KEY:-}" ]; then
    printf 'AGENT_HOST_LLM_API_KEY=%s\n' "$AH_LLM_API_KEY" | write_users_file 600 ".config/environment.d/64-llm.conf"
else
    rm_api_key() { agent_run rm -f "$AGENT_HOME/.config/environment.d/64-llm.conf"; }
    for_each_user rm_api_key
fi

# --- 利用者ごとのエージェントの設定(none では、ここで足したものだけを外す) ---
llm_agent_config() {
    # Codex: provider は config.toml の末尾に印で囲んで置き(毎回置き換える)、profile は ~/.codex/local.config.toml に置く。
    # Codex 0.134.0 からは --profile が config.toml の [profiles.<名前>] を読まず、<名前>.config.toml を重ねる
    # (config.toml に [profiles.local] があると codex --profile local はエラーで止まる。2026-11-14 に VM で確認)
    local codex_conf="$AGENT_HOME/.codex/config.toml"
    if [ -f "$codex_conf" ] || [ "$mode" != none ]; then
        agent_run mkdir -p "$AGENT_HOME/.codex"
        agent_run python3 - "$codex_conf" "$AGENT_HOME/.codex/local.config.toml" "$mode" "$AH_LLM_URL" "$AH_LLM_DEFAULT_MODEL" "${AH_LLM_API_KEY:-}" <<'PY'
import os
import re
import sys

path, profile, mode, url, model, key = sys.argv[1:]
begin = "# >>> agent-host-autoinstall llm(64-llm.sh が env.yaml の llm から書く。手で直さない)"
end = "# <<< agent-host-autoinstall llm"
mark = "# agent-host-autoinstall(64-llm.sh)が env.yaml の llm から書く。手で直さない(codex --profile local)"


def write(p, text, mode_bits):
    tmp = p + ".agent-host"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
    os.chmod(tmp, mode_bits)
    os.replace(tmp, p)


text = open(path, encoding="utf-8").read() if os.path.exists(path) else ""
text = re.sub(rf"\n*{re.escape(begin)}\n.*?{re.escape(end)}\n?", "\n", text, flags=re.S).rstrip("\n")
if mode != "none":
    block = [begin, "[model_providers.agent-host-llm]", 'name = "agent-host LLM"',
             f'base_url = "{url}/v1"', 'wire_api = "responses"']
    if key:
        block.append('env_key = "AGENT_HOST_LLM_API_KEY"')
    block.append(end)
    text = (text + "\n\n" if text else "") + "\n".join(block)
    if re.search(r"^\s*\[profiles\.local\]", text, flags=re.M):
        print(f"[agent-host] 注意: {path} に古い形の [profiles.local] があるので、codex --profile local はエラーになる"
              f"(中身を {profile} に移して消す)")
write(path, text + "\n" if text else "", 0o600)

ours = os.path.exists(profile) and open(profile, encoding="utf-8").readline().rstrip("\n") == mark
if mode != "none":
    if os.path.exists(profile) and not ours:
        print(f"[agent-host] 注意: {profile} を利用者が置いているので、codex --profile local の設定を書かなかった")
    else:
        write(profile, "\n".join([mark, 'model_provider = "agent-host-llm"', f'model = "{model}"']) + "\n", 0o600)
elif ours:
    os.remove(profile)
PY
    fi

    # OpenCode: opencode.json の provider に agent-host-llm を足す(ほかの設定は残す)
    local oc_conf="$AGENT_HOME/.config/opencode/opencode.json"
    if [ -f "$oc_conf" ] || { [ "$mode" != none ] && [[ " ${AH_AGENTS:-} " == *" opencode "* ]]; }; then
        agent_run mkdir -p "$AGENT_HOME/.config/opencode"
        agent_run python3 - "$oc_conf" "$mode" "$AH_LLM_URL" "${AH_LLM_API_KEY:-}" "$AH_LLM_MODELS" <<'PY'
import json
import os
import sys

path, mode, url, key, models = sys.argv[1:]
models = models.split()
if os.path.exists(path):
    try:
        conf = json.load(open(path, encoding="utf-8"))
    except ValueError:
        # コメント付き(JSONC)などで読めなければ触らない
        print(f"[agent-host] 注意: {path} を JSON として読めないので、OpenCode の LLM の設定を足さなかった")
        sys.exit(0)
else:
    conf = {"$schema": "https://opencode.ai/config.json"}
providers = conf.setdefault("provider", {})
providers.pop("agent-host-llm", None)
if mode != "none":
    options = {"baseURL": f"{url}/v1"}
    if key:
        options["apiKey"] = "{env:AGENT_HOST_LLM_API_KEY}"
    providers["agent-host-llm"] = {
        "npm": "@ai-sdk/openai-compatible",
        "name": "agent-host LLM",
        "options": options,
        "models": {m: {"name": m} for m in models},
    }
if not providers:
    del conf["provider"]
tmp = path + ".agent-host"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(conf, f, ensure_ascii=False, indent=2)
    f.write("\n")
os.chmod(tmp, 0o644)
os.replace(tmp, path)
PY
    fi
}
for_each_user llm_agent_config
log "エージェントの LLM の設定を置いた(llm.mode: $mode)"
