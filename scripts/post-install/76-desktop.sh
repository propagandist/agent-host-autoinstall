#!/usr/bin/env bash
# RDP で入って使うときのデスクトップ: 日本語入力と言語パック、端末(Xfce Terminal)、PDF ビューアー(Atril)、クリップボードの履歴(Clipboard Indicator)、
# Chrome のポリシー、壁紙の色と Dock(desktop-env.sh に渡し、ログイン中ならその場で入れる)、Files のブックマーク。
# キー割り当てと拡張機能の有効化は first-login で行う。
set -euo pipefail
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"
load_env

# --- 固定するバージョン(上げるときはここと手順書の付録「固定しているバージョン」を直す) ---
# Clipboard Indicator: extensions.gnome.org の GNOME 50 向けの版。SHA256 は取得したファイルから計算した値
CLIPBOARD_INDICATOR_UUID=clipboard-indicator@tudmotu.com
CLIPBOARD_INDICATOR_VERSION_TAG=70694   # 拡張機能の版 71
CLIPBOARD_INDICATOR_SHA256=687cb404f9540958ddb0c1de638970572cef73f22f016e5d6c6d6f5d4cd55f97

# --- 日本語の言語サポート: 日本語入力(Mozc)と言語パック(Ubuntu の公式パッケージ。OS の更新に任せる) ---
# インストーラーはロケールに合わせて入れることがあるが、入らなかったこともある(VirtualBox の入れなおしで
# fonts-noto-cjk だけが入り、ibus-mozc と language-pack-ja が無く、日本語を打てなかった)。当てにせず入れる。
# 入力ソース(mozc-on)の設定は first-login で行う
apt-get install -y ibus-mozc mozc-utils-gui language-pack-ja language-pack-gnome-ja fonts-noto-cjk
log "日本語入力(Mozc)と日本語の言語パックを入れた"

# --- 端末: Xfce Terminal(Ubuntu の公式パッケージ。OS の更新に任せる) ---
# GPU を使わず軽い(VirtualBox で 1 つあたり約 27MB。Ghostty は約 148MB、Alacritty は約 73MB)。
# 右クリックで貼り付けと選択でコピーは、セッションが要る xfconf で設定するので first-login で行う
apt-get install -y xfce4-terminal
terminal_default() {
    # 既定の端末(xdg-terminal-exec が読む。Files の「端末で開く」など)
    printf 'xfce4-terminal.desktop\n' | write_agent_file 644 "$AGENT_HOME/.config/xdg-terminals.list"
}
for_each_user terminal_default
log "Xfce Terminal を入れ、agent の既定の端末にした"

# --- PDF ビューアー: Atril(Ubuntu の公式パッケージ。OS の更新に任せる) ---
# GTK3 で、メニューとツールバーのある普通の画面(RDP でマウスだけでも使える)。zathura は vim 風のキー操作が前提、
# MuPDF は X11 なので開くたびに Xwayland が起動する、qpdfview は Qt を一式入れることになるので選ばなかった
pdf_default() {
    apt-get install -y atril
    mimeapps="$AGENT_HOME/.config/mimeapps.list"
    if [ ! -f "$mimeapps" ]; then
        printf '[Default Applications]\n' | write_agent_file 644 "$mimeapps"
    fi
    ini_set --as-agent "$mimeapps" "Default Applications" application/pdf atril.desktop
}
for_each_user pdf_default
log "Atril を入れ、agent の PDF の既定のアプリにした"

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
# パスワードを保存させないのは、agent に置く秘密を各サービスのログインだけにする前提(SPEC.md §4)に合わせるため
install -d -m 755 /etc/opt/chrome/policies/managed
cat >/etc/opt/chrome/policies/managed/agent-host.json <<'EOF'
{
  "MetricsReportingEnabled": false,
  "PasswordManagerEnabled": false,
  "PromotionsEnabled": false
}
EOF
desktop_user() {
    : | write_agent_file 644 "$AGENT_HOME/.config/google-chrome/First Run"

    # --- 壁紙の色と Dock(env.yaml の desktop_color と editors で変わる) ---
    # desktop-env.sh がログインのたびに読み、変わっていれば入れる。ログイン中なら、その場でも入れる(Issue #13)
    printf 'DESKTOP_COLOR=%s\n' "${AH_DESKTOP_COLOR:-#4a4a4a}" |
        write_agent_file 644 "$AGENT_HOME/.config/agent-host/desktop.env"
    write_agent_file 644 "$AGENT_HOME/.config/autostart/agent-host-desktop.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=agent-host desktop settings
Exec=$AH_ROOT/first-login/desktop-env.sh
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF
    if [ -f "$AGENT_HOME/.config/agent-host/first-login.done" ]; then
        rc=0
        agent_session_run "$AH_ROOT/first-login/desktop-env.sh" >/dev/null || rc=$?
        [ "$rc" = 0 ] || [ "$rc" = 2 ] || log "注意: 壁紙の色と Dock をその場では入れられなかった。次のログインで入る"
    fi

    # --- Files のサイドバーに ~/work ---
    # 新規インストールではまだファイルがない(xdg-user-dirs-gtk-update は 80 で止めている)ので、よく使う場所も一緒に書く
    bookmarks="$AGENT_HOME/.config/gtk-3.0/bookmarks"
    if [ ! -f "$bookmarks" ]; then
        printf 'file://%s/%s\n' "$AGENT_HOME" Documents "$AGENT_HOME" Downloads "$AGENT_HOME" Pictures |
            write_agent_file 664 "$bookmarks"
    fi
    if ! grep -q "^file://$AGENT_HOME/work " "$bookmarks"; then
        # shellcheck disable=SC2016  # agent の sh の中で展開する
        agent_run sh -c 'printf "file://%s/work work\n" "$2" >>"$1"' sh "$bookmarks" "$AGENT_HOME"
    fi
}
for_each_user desktop_user
log "Chrome のポリシー、壁紙の色、~/work のブックマークを設定した"
