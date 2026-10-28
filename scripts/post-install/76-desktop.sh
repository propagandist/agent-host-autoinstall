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

# --- 日本語の言語サポート: 日本語入力(fcitx5 と Mozc)と言語パック(Ubuntu の公式パッケージ。OS の更新に任せる) ---
# インストーラーはロケールに合わせて入れることがあるが、入らなかったこともある(VirtualBox の入れなおしで
# fonts-noto-cjk だけが入り、ibus-mozc と language-pack-ja が無く、日本語を打てなかった)。当てにせず入れる。
apt-get install -y mozc-utils-gui language-pack-ja language-pack-gnome-ja fonts-noto-cjk
# 入力メソッドは IBus ではなく fcitx5 にする。RDP の半角/全角キーは押しっぱなしで届き、ホストのキーリピートで
# 押され続ける(#21)。IBus の Mozc はそのたびに入力モードの表示を更新し、gnome-shell がそれを受けてメモリを漏らし、
# ホストが応答しなくなって OOM で落ちた(#36)。fcitx5 は IBus のふりをする口(ibusfrontend)で gnome-shell とつながり、表示の
# 更新を送らないので、同じリピートで漏れなかった(どちらも実機で確認。docs/notes.md)。
# Recommends は Qt6 と設定の画面、中国語の辞書まで引くので入れない(Mozc の設定は mozc-utils-gui で行う)
apt-get install -y --no-install-recommends fcitx5 fcitx5-mozc fcitx5-frontend-gtk3 fcitx5-frontend-gtk4
apt-get purge -y ibus-mozc
# ibus-daemon は GNOME のセッションが立てる(user の org.freedesktop.IBus.session.GNOME.service)。fcitx5 と
# 同じ口を取り合うので、全員で止める。ibus のパッケージは gnome-shell の Recommends なので残す
systemctl --global mask org.freedesktop.IBus.session.GNOME.service >/dev/null
# GNOME の Wayland では im-config が入力メソッドを起動しない(/etc/profile.d/im-config_wayland.sh が止めている)。
# ibus と同じ並びで、セッションが立つたびに fcitx5 を起動する
cat >/etc/systemd/user/agent-host-fcitx5.service <<'EOF'
[Unit]
Description=Fcitx 5 (日本語入力。agent-host が IBus の代わりに置く)
Requisite=gnome-session-initialized.target
After=gnome-session-initialized.target
PartOf=gnome-session-initialized.target
Before=gnome-session.target

[Service]
ExecStart=/usr/bin/fcitx5 --replace
Restart=on-failure
Slice=session.slice

[Install]
WantedBy=gnome-session.target
EOF
systemctl --global enable agent-host-fcitx5.service >/dev/null 2>&1
# 配列(env.yaml の keyboard_layout)と Mozc の組。fcitx5 が終わるときに書きなおすので、ないときだけ置く。
# 切り替えは fcitx5 の既定のキー(Ctrl+Space と半角/全角)で行う(GNOME の入力ソースの設定は first-login)
fcitx5_user() {
    local layout
    # shellcheck source=/dev/null
    layout="$(. /etc/default/keyboard && echo "${XKBLAYOUT%%,*}")"
    [ -f "$AGENT_HOME/.config/fcitx5/profile" ] || write_agent_file 644 "$AGENT_HOME/.config/fcitx5/profile" <<EOF
[Groups/0]
Name=Default
Default Layout=$layout
DefaultIM=mozc

[Groups/0/Items/0]
Name=keyboard-$layout
Layout=

[Groups/0/Items/1]
Name=mozc
Layout=

[GroupOrder]
0=Default
EOF
    # キーの割り当て。RDP の半角/全角は押しっぱなしで届き、ホストがリピートし続ける(#21)。切り替え(Trigger)に
    # すると日本語と英字を行き来し続けるので、何度押されても同じになる「日本語にする」(Activate)にし、英字は無変換と
    # Ctrl+Space で戻す(実機で確認)。fcitx5 が終わるときに書きなおすので、ないときだけ置く
    [ -f "$AGENT_HOME/.config/fcitx5/config" ] || write_agent_file 644 "$AGENT_HOME/.config/fcitx5/config" <<'EOF'
[Hotkey/TriggerKeys]
0=Control+space

[Hotkey/ActivateKeys]
0=Zenkaku_Hankaku

[Hotkey/DeactivateKeys]
0=Muhenkan
EOF
    # 日本語になったあとのリピートは Mozc に届き、Mozc の割り当て(MS-IME)の半角/全角で入力モードを切り替え続ける。
    # 半角/全角を外した表を独自の割り当てにする(実機で確認)。利用者が Mozc の設定を保存していれば、それを残す
    if [ ! -f "$AGENT_HOME/.config/mozc/config1.db" ]; then
        agent_run install -d -m 700 "$AGENT_HOME/.config/mozc"
        python3 "$(dirname "$0")/mozc-config.py" "$(dirname "$0")/mozc-keymap.tsv" |
            write_agent_file 600 "$AGENT_HOME/.config/mozc/config1.db"
    fi
    # セッションが動いていれば(just update)、その場で IBus から fcitx5 に替える。gnome-shell は IBus の口が
    # 替わるとつなぎなおす(実機で確認)。替えないと、desktop-env.sh が入力ソースから IBus の Mozc を外したあと、
    # セッションを立てなおすまで日本語を打てない
    agent_bus_run systemctl --user daemon-reload >/dev/null 2>&1 || return 0
    agent_bus_run systemctl --user is-active --quiet gnome-session-initialized.target || return 0
    if agent_bus_run systemctl --user is-active --quiet org.freedesktop.IBus.session.GNOME.service; then
        agent_bus_run systemctl --user stop org.freedesktop.IBus.session.GNOME.service >/dev/null 2>&1 || true
        # Mozc のサーバーは IBus と fcitx5 で共通で、設定は起動したときに読む。上の config1.db を読ませるために止める
        # (fcitx5-mozc が必要なときに起動しなおす)
        agent_run pkill -u "$AGENT_USER" -x mozc_server || true
    fi
    agent_bus_run systemctl --user start agent-host-fcitx5.service >/dev/null 2>&1 ||
        log "注意: $AGENT_USER のセッションで fcitx5 を起動できなかった。セッションを立てなおすと起動する"
}
for_each_user fcitx5_user
log "日本語入力(fcitx5 と Mozc)と日本語の言語パックを入れ、IBus を止めた"

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
