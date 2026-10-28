#!/usr/bin/env bash
# env.yaml から決まるデスクトップの設定(壁紙の色、Dock)を入れる(agent のセッションで動く)。
# ログインのたびの自動起動で動き、前回入れたものから変わったときだけ入れる。利用者が変えた Dock や色は、
# env.yaml の desktop_color か、入っているエディターが変わるまで残る。first-login.sh からも呼ぶ。
# just update のときに agent がログイン中なら、76-desktop.sh がその場でも呼ぶ(Issue #13)
set -euo pipefail

state_dir="$HOME/.config/agent-host"
applied="$state_dir/desktop.applied"

# 壁紙の色は env.yaml の desktop_color(76-desktop.sh が desktop.env に渡す)
desktop_color="#4a4a4a"
if [ -f "$state_dir/desktop.env" ]; then
    # shellcheck source=/dev/null
    . "$state_dir/desktop.env"
    desktop_color="${DESKTOP_COLOR:-$desktop_color}"
fi
# Dock: Orca・端末・Chrome・入っているエディター・Files に絞る
favorites=""
for app in orca-ide xfce4-terminal google-chrome com.microsoft.VSCode dev.zed.Zed org.gnome.Nautilus; do
    if [ -f "/usr/share/applications/$app.desktop" ]; then
        favorites+="${favorites:+, }'$app.desktop'"
    fi
done

# 0.3 までは IBus の Mozc(mozc-on。0.3.0 より前は mozc-jp も)を入力ソースに置き、Ctrl+Space を GNOME の切り替えに
# 割り当てていた。日本語入力を fcitx5 に替えたので(76-desktop.sh)、IBus の入力ソースを外し、Ctrl+Space を fcitx5 に渡す
sources="$(gsettings get org.gnome.desktop.input-sources sources)"
if [[ "$sources" == *"('ibus', "* ]]; then
    sources="$(sed -E "s/(, )?\('ibus', '[^']*'\)//g; s/^\[, /[/" <<<"$sources")"
    if [ "$sources" = "[]" ]; then
        # shellcheck source=/dev/null
        sources="[('xkb', '$(. /etc/default/keyboard && echo "${XKBLAYOUT%%,*}")')]"
    fi
    gsettings set org.gnome.desktop.input-sources sources "$sources"
    echo "[agent-host] 入力ソースから IBus を外した: $sources"
fi
if [[ "$(gsettings get org.gnome.desktop.wm.keybindings switch-input-source)" == *"'<Control>space'"* ]]; then
    gsettings reset org.gnome.desktop.wm.keybindings switch-input-source
    gsettings reset org.gnome.desktop.wm.keybindings switch-input-source-backward
    echo "[agent-host] Ctrl+Space を GNOME の切り替えから外した(fcitx5 が使う)"
fi

want="color=$desktop_color favorites=[$favorites]"
if [ "$(cat "$applied" 2>/dev/null || true)" = "$want" ]; then
    exit 0
fi
# 壁紙を単色にする(RDP は画面の変化を送るので、模様が少ないほど軽い)
gsettings set org.gnome.desktop.background picture-options 'none'
gsettings set org.gnome.desktop.background color-shading-type 'solid'
gsettings set org.gnome.desktop.background primary-color "$desktop_color"
gsettings set org.gnome.shell favorite-apps "[$favorites]"
mkdir -p "$state_dir"
printf '%s\n' "$want" >"$applied"
echo "[agent-host] 壁紙の色と Dock を入れた: $want"
