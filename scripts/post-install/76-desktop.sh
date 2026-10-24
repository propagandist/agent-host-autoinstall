#!/usr/bin/env bash
# RDP で入って使うときのデスクトップの使い勝手: 端末(Xfce Terminal)とクリップボードの履歴(Clipboard Indicator)。
# キー割り当てと拡張機能の有効化は、agent のセッションが要るので first-login で行う。
set -euo pipefail
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"
load_env

# --- 固定するバージョン(上げるときはここと手順書の付録「固定しているバージョン」を直す) ---
# Clipboard Indicator: extensions.gnome.org の GNOME 50 向けの版。SHA256 は取得したファイルから計算した値
CLIPBOARD_INDICATOR_UUID=clipboard-indicator@tudmotu.com
CLIPBOARD_INDICATOR_VERSION_TAG=70694   # 拡張機能の版 71
CLIPBOARD_INDICATOR_SHA256=687cb404f9540958ddb0c1de638970572cef73f22f016e5d6c6d6f5d4cd55f97

# --- 端末: Xfce Terminal(Ubuntu の公式パッケージ。OS の更新に任せる) ---
# GPU を使わず軽い(VirtualBox で 1 つあたり約 27MB。Ghostty は約 148MB、Alacritty は約 73MB)。
# 右クリックで貼り付けと選択でコピーは、セッションが要る xfconf で設定するので first-login で行う
apt-get install -y xfce4-terminal
# 既定の端末(xdg-terminal-exec が読む。Files の「端末で開く」など)
printf 'xfce4-terminal.desktop\n' | write_agent_file 644 "$AGENT_HOME/.config/xdg-terminals.list"
log "Xfce Terminal を入れ、agent の既定の端末にした"

# --- クリップボードの履歴: Clipboard Indicator(GNOME の拡張機能) ---
ext_dir="/usr/share/gnome-shell/extensions/$CLIPBOARD_INDICATOR_UUID"
zip="$AH_CACHE/$CLIPBOARD_INDICATOR_UUID-$CLIPBOARD_INDICATOR_VERSION_TAG.zip"
download_verified \
    "https://extensions.gnome.org/download-extension/$CLIPBOARD_INDICATOR_UUID.shell-extension.zip?version_tag=$CLIPBOARD_INDICATOR_VERSION_TAG" \
    "$CLIPBOARD_INDICATOR_SHA256" "$zip"
apt-get install -y unzip
rm -rf "$ext_dir"
install -d -m 755 "$ext_dir"
unzip -q "$zip" -d "$ext_dir"
chmod -R u=rwX,go=rX "$ext_dir"
log "Clipboard Indicator(版 71)を入れた"

# --- Chrome: 利用統計・パスワードの保存・宣伝を止め、初回の案内を出さない ---
# パスワードを保存させないのは、agent に個人の秘密情報を置かない前提(SPEC.md §4)に合わせるため
install -d -m 755 /etc/opt/chrome/policies/managed
cat >/etc/opt/chrome/policies/managed/agent-host.json <<'EOF'
{
  "MetricsReportingEnabled": false,
  "PasswordManagerEnabled": false,
  "PromotionsEnabled": false
}
EOF
: | write_agent_file 644 "$AGENT_HOME/.config/google-chrome/First Run"

# --- first-login に渡す値(壁紙の色) ---
printf 'DESKTOP_COLOR=%s\n' "${AH_DESKTOP_COLOR:-#4a4a4a}" |
    write_agent_file 644 "$AGENT_HOME/.config/agent-host/desktop.env"

# --- Files のサイドバーに ~/work ---
# 新規インストールではまだファイルがない(xdg-user-dirs-gtk-update は 80 で止めている)ので、よく使う場所も一緒に書く
bookmarks="$AGENT_HOME/.config/gtk-3.0/bookmarks"
if [ ! -f "$bookmarks" ]; then
    printf 'file://%s/%s\n' "$AGENT_HOME" Documents "$AGENT_HOME" Downloads "$AGENT_HOME" Pictures |
        write_agent_file 664 "$bookmarks"
fi
if ! grep -q "^file://$AGENT_HOME/work " "$bookmarks"; then
    printf 'file://%s/work work\n' "$AGENT_HOME" >>"$bookmarks"
fi
log "Chrome のポリシー、壁紙の色、~/work のブックマークを設定した"
