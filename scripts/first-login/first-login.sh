#!/usr/bin/env bash
# 利用者の GNOME の設定を一度だけ入れる。セッションを立てる前に、88-start-sessions.sh が root から
# 利用者の権限とユーザーのバス(linger)で実行する(gsettings・xfconf はセッションがなくても書ける)。
# 画面ロックを先に止めておかないと、立てた直後のセッションがロックされ、パスワードのない利用者は外せない(#15 の段 0)。
# 失敗したら印を付けないので、次の構成でもう一度動く。RDP の設定は 20-sessions.sh が行う。
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
# ロックの操作もできなくする。利用者のパスワードはロックしてあるので、ロックすると本人も外せない
gsettings set org.gnome.desktop.lockdown disable-lock-screen true
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

mkdir -p "$state_dir"
touch "$done_mark"
# 0.2 までのホストでは、ログインのたびの自動起動から動かしていた
rm -f "$autostart"
echo "[agent-host] first-login 完了: $(date -Is)"
