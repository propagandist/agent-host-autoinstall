#!/usr/bin/env bash
# スリープ・休止を無効にする。agent の GNOME 側の設定は first-login で行う。
set -euo pipefail
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"

systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
log "スリープ関連の target を mask した"
