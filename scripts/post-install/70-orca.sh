#!/usr/bin/env bash
# Orca を公式 .deb の固定バージョンで入れ、利用者ごとのセッションで自動起動させる。
set -euo pipefail
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"
load_env

# --- 固定するバージョン(上げるときはここと手順書の付録「固定しているバージョン」を直す) ---
# SHA256 は GitHub API のアセットの digest(公式の SHA256SUMS ファイルはない)
ORCA_VERSION=1.4.237
ORCA_SHA256=296ffd14345612be70ca09e9ab40f7ffbb7f842fb5794e1e6c1ebc324360cb5c
# タグは基本 v 付き(1.4.230 は v なしだった)。上げるときはタグ名を確かめる
ORCA_URL="https://github.com/stablyai/orca/releases/download/v$ORCA_VERSION/orca-ide_${ORCA_VERSION}_amd64.deb"

if [ "$(dpkg-query -W -f='${Version}' orca-ide 2>/dev/null || true)" != "$ORCA_VERSION" ]; then
    deb="$AH_CACHE/orca-ide_${ORCA_VERSION}_amd64.deb"
    download_verified "$ORCA_URL" "$ORCA_SHA256" "$deb"
    apt-get install -y --allow-downgrades --allow-change-held-packages "$deb"
fi
# .deb 版の Orca は自分では更新を適用しない(更新の通知は出る。止める設定は見つからなかった)
apt-mark hold orca-ide
log "Orca $ORCA_VERSION を入れて hold した"

# 自動起動。/usr/bin/orca-ide は CLI 用のシムなので、GUI 本体の /opt/Orca/orca-ide を書く
# /opt/Orca/orca-ide で GUI が Wayland ネイティブで起動する(VirtualBox で確認済み)
setup_orca() {
    write_agent_file 644 "$AGENT_HOME/.config/autostart/orca.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Orca
Exec=/opt/Orca/orca-ide
X-GNOME-Autostart-enabled=true
EOF
    log "$AGENT_USER の Orca の自動起動を設定した"

    # 匿名の利用統計(PostHog)を送らない。既定はオン(Orca の公式文書)。設定画面でもオフにする(docs/manual-steps.md)
    # environment.d は利用者の GNOME セッションに入り、autostart の Orca に引き継がれる
    printf 'ORCA_TELEMETRY_DISABLED=1\n' |
        write_agent_file 644 "$AGENT_HOME/.config/environment.d/60-orca.conf"
    # 更新の確認の通信(1 日 1 回と、30 分ごとの nudge.json)は止める設定がない(v1.4.237 のソースで確認)。
    # .deb 版は自分では更新しないので、出るのは通知だけ
}
for_each_user setup_orca
