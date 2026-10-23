#!/usr/bin/env bash
# GDM で agent を自動ログインさせる。
# 26.04 の gdm3 50.x でも設定ファイルは /etc/gdm3/custom.conf の [daemon](ソースで確認済み)
set -euo pipefail
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"

conf=/etc/gdm3/custom.conf
ini_set "$conf" daemon AutomaticLoginEnable true
ini_set "$conf" daemon AutomaticLogin "$AGENT_USER"
log "$conf に自動ログインを設定した"
