#!/usr/bin/env bash
# env.yaml から設定を作り、ホストの /opt/agent-host に置くもの一式を <出力ディレクトリ> にそろえる。
# build-usb.sh(ISO に入れる)と just update(動いているホストに反映する)が使う。
#
# 使い方: scripts/stage.sh <env.yaml> <出力ディレクトリ>
# 出力: <出力ディレクトリ>/autoinstall.yaml(ISO 用)と <出力ディレクトリ>/agent-host/(/opt/agent-host に置くもの)
# 必要なもの: python3, python3-yaml
set -euo pipefail

[ $# -eq 2 ] || { echo "使い方: $0 <env.yaml> <出力ディレクトリ>" >&2; exit 2; }
repo="$(cd "$(dirname "$0")/.." && pwd)"
env_yaml="$1"
out="$2"
[ -f "$env_yaml" ] || { echo "$env_yaml がない(env.example.yaml をコピーして作る)" >&2; exit 1; }

render="$out/render"
stage="$out/agent-host"
rm -rf "$render" "$stage"
mkdir -p "$stage"

# 1. autoinstall.yaml と env.sh・公開鍵・CA 証明書を生成する
python3 "$repo/scripts/render-autoinstall.py" "$repo/autoinstall/autoinstall.yaml" "$env_yaml" "$render"
cp "$render/autoinstall.yaml" "$out/autoinstall.yaml"
cp "$render/env.sh" "$render/agent_authorized_keys" "$stage/"
cp -a "$render/ca" "$stage/ca"
rm -rf "$render"

# 2. スクリプトをそろえる
cp -a "$repo/scripts/provision.sh" "$repo/scripts/setup-provision.sh" \
    "$repo/scripts/lib" "$repo/scripts/post-install" "$repo/scripts/first-login" \
    "$repo/scripts/systemd" "$repo/scripts/notify" "$repo/scripts/migrate" "$repo/scripts/watchdog" "$stage/"
find "$stage" -name '__pycache__' -prune -exec rm -rf {} +
find "$stage" -type f \( -name '*.sh' -o -path '*/notify/*' -o -path '*/migrate/*' -o -path '*/watchdog/*' \) \
    -exec chmod 755 {} +
chmod 600 "$stage/env.sh" "$stage/agent_authorized_keys"
