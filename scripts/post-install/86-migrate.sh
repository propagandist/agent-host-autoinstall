#!/usr/bin/env bash
# 環境を入れ替えるときの書き出しと取り込みのスクリプトを置く(使い方は docs/manual-steps.md)。
set -euo pipefail
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"

apt-get install -y zstd
install -m 755 "$AH_ROOT/migrate/agent-host-backup" /usr/local/sbin/agent-host-backup
install -m 755 "$AH_ROOT/migrate/agent-host-restore" /usr/local/sbin/agent-host-restore
log "移行用の agent-host-backup と agent-host-restore を置いた"
