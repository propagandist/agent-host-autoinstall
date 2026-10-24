#!/usr/bin/env bash
# agent の初回ログイン時に一度だけ実行する(~/.config/autostart から起動される)。
# GNOME の省電力・画面ロックを止め、デスクトップ共有(RDP)を有効にする。
# 失敗したら印を付けないので、次のログインでもう一度動く。再実行は agent のセッションでこのファイルを実行する。
set -euo pipefail

state_dir="$HOME/.config/agent-host"
done_mark="$state_dir/first-login.done"
autostart="$HOME/.config/autostart/agent-host-first-login.desktop"
log_file="$HOME/.local/state/agent-host/first-login.log"

mkdir -p "$(dirname "$log_file")"
exec >>"$log_file" 2>&1
echo "[agent-host] first-login 開始: $(date -Is)"

# --- 省電力・画面ロック ---
# 画面がロックされると RDP の接続が切れる(gnome-remote-desktop の文書で確認済み)
gsettings set org.gnome.desktop.session idle-delay 0
gsettings set org.gnome.desktop.screensaver lock-enabled false
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
# 忙しいアプリに「応答していません」を出さない(誰も見ていない画面に残る)
gsettings set org.gnome.mutter check-alive-timeout 0

# --- キーボードと日本語入力 ---
# 配列はインストール時の指定(env.yaml の keyboard_layout → /etc/default/keyboard)に合わせ、Mozc と組にする。
# Mozc は mozc-on(切り替えた時点でひらがな)を使う。mozc-jp は直接入力で始まり、ひらがなにするには
# 半角/全角キーが要るので、101 キーボードでは日本語を打てなかった(VirtualBox + RDP で確認済み)
# shellcheck source=/dev/null
layout="$(. /etc/default/keyboard && echo "${XKBLAYOUT%%,*}")"
gsettings set org.gnome.desktop.input-sources sources "[('xkb', '$layout'), ('ibus', 'mozc-on')]"
# 101 キーボードには半角/全角キーがなく、Super は RDP クライアント側に取られやすいので、Ctrl+Space でも切り替えられるようにする
gsettings set org.gnome.desktop.wm.keybindings switch-input-source "['<Super>space', '<Control>space']"
gsettings set org.gnome.desktop.wm.keybindings switch-input-source-backward "['<Shift><Super>space', '<Shift><Control>space']"

# --- RDP での使い勝手 ---
# アニメーションを切る(RDP は画面の変化を送るので、動きが少ないほど軽い)。
# 壁紙の色と Dock は env.yaml で変わるので、ログインのたびに動く desktop-env.sh が入れる(ここでも呼ぶ)
gsettings set org.gnome.desktop.interface enable-animations false
"$(dirname "$0")/desktop-env.sh"
# スクリーンショット: PrintScreen は RDP で手元の Windows に取られることがあるので、Ctrl+Shift+Alt+S でも開く
gsettings set org.gnome.shell.keybindings show-screenshot-ui "['Print', '<Shift><Control><Alt>s']"
# Ctrl+Alt+T で開く端末を Xfce Terminal に(gsd-media-keys はこの設定と xdg-terminal-exec を見る。
# xdg-terminal-exec の既定は Ptyxis で、~/.config/xdg-terminals.list は 76-desktop.sh が置く)。
# 右クリックでクリップボードから貼り付け、選択でコピー(PuTTY や Windows Terminal に近い動き)
if command -v xfce4-terminal >/dev/null; then
    gsettings set org.gnome.desktop.default-applications.terminal exec 'xfce4-terminal'
    xfconf-query -c xfce4-terminal -p /misc-right-click-action -n -t string \
        -s TERMINAL_RIGHT_CLICK_ACTION_PASTE_CLIPBOARD
    xfconf-query -c xfce4-terminal -p /misc-copy-on-select -n -t bool -s true
fi
# Caps Lock は使わない。RDP では手元とホストで Caps Lock の状態がずれることがあった(VirtualBox + mstsc)。
# 状態を持たないキーにすれば、ずれようがない。大文字は Shift で打つ
gsettings set org.gnome.desktop.input-sources xkb-options "['caps:none']"
# クリップボードの履歴(Clipboard Indicator。76-desktop.sh が入れる)を有効にする。
# gnome-extensions enable は、GNOME Shell がまだその拡張機能を知らないと失敗する(構成の途中で置いたとき)。
# 有効にする一覧に直接足せば、Shell が読み込んだときに有効になる(VirtualBox で確認済み)
ext=clipboard-indicator@tudmotu.com
enabled="$(gsettings get org.gnome.shell enabled-extensions)"
if [[ "$enabled" != *"'$ext'"* ]]; then
    if [[ "$enabled" == "@as []" || "$enabled" == "[]" ]]; then
        gsettings set org.gnome.shell enabled-extensions "['$ext']"
    else
        gsettings set org.gnome.shell enabled-extensions "${enabled%]}, '$ext']"
    fi
fi

# --- デスクトップ共有(RDP) ---
# TLS 証明書は grdctl もデーモンも作らないので自分で作る(置き場所は upstream の docs/configuration.md の慣例)
cert_dir="$HOME/.local/share/gnome-remote-desktop"
mkdir -p "$cert_dir"
if [ ! -f "$cert_dir/tls.crt" ] || [ ! -f "$cert_dir/tls.key" ]; then
    openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 \
        -subj "/CN=$(hostname)" -keyout "$cert_dir/tls.key" -out "$cert_dir/tls.crt"
    chmod 600 "$cert_dir/tls.key"
fi
# grdctl が "RDP server certificate is invalid" を出すが、最終的な状態は正常で RDP も待ち受ける(VirtualBox)。
# 証明書を先にしても出た。原因は未調査
grdctl rdp set-tls-cert "$cert_dir/tls.crt"
grdctl rdp set-tls-key "$cert_dir/tls.key"

# 認証情報(80-agent-session.sh が渡した rdp.env)をキーリングに入れる。ログインのたびの自動起動でも同じものが動く
"$(dirname "$0")/rdp-credentials.sh"

# 既定では閲覧のみなので操作を許可する。ポートは 3389 に固定する(使用中でも別ポートへずらさない)
grdctl rdp disable-view-only
grdctl rdp disable-port-negotiation
# enable は gnome-remote-desktop.service(systemd user)の起動と永続的な有効化まで行う
grdctl rdp enable
grdctl status || true

touch "$done_mark"
rm -f "$autostart"
echo "[agent-host] first-login 完了: $(date -Is)"
