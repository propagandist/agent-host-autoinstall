#!/usr/bin/env bash
# agent の初回ログイン時に一度だけ実行する(~/.config/autostart から起動される)。
# GNOME の省電力・画面ロックを止め、デスクトップ共有(RDP)を有効にする。
# 失敗したら印を付けないので、次のログインでもう一度動く。再実行は agent のセッションでこのファイルを実行する。
set -euo pipefail

state_dir="$HOME/.config/agent-host"
done_mark="$state_dir/first-login.done"
creds="$state_dir/rdp.env"
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

# --- デスクトップ共有(RDP) ---
# TLS 証明書は grdctl もデーモンも作らないので自分で作る(置き場所は upstream の docs/configuration.md の慣例)
cert_dir="$HOME/.local/share/gnome-remote-desktop"
mkdir -p "$cert_dir"
if [ ! -f "$cert_dir/tls.crt" ] || [ ! -f "$cert_dir/tls.key" ]; then
    openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 \
        -subj "/CN=$(hostname)" -keyout "$cert_dir/tls.key" -out "$cert_dir/tls.crt"
    chmod 600 "$cert_dir/tls.key"
fi
# 鍵を先に設定したとき "RDP server certificate is invalid" が出た(VirtualBox。最終的な状態は正常)。
# 証明書が未設定の時点で検証されたためと推定し、証明書を先にする
grdctl rdp set-tls-cert "$cert_dir/tls.crt"
grdctl rdp set-tls-key "$cert_dir/tls.key"

# 認証情報はログインキーリングに保存される。キーリングがロックされているとここで失敗する
if [ -f "$creds" ]; then
    # shellcheck source=/dev/null
    . "$creds"
    grdctl rdp set-credentials "$RDP_USER" "$RDP_PASSWORD"
    rm -f "$creds"
fi

# 既定では閲覧のみなので操作を許可する。ポートは 3389 に固定する(使用中でも別ポートへずらさない)
grdctl rdp disable-view-only
grdctl rdp disable-port-negotiation
# enable は gnome-remote-desktop.service(systemd user)の起動と永続的な有効化まで行う
grdctl rdp enable
grdctl status || true

touch "$done_mark"
rm -f "$autostart"
echo "[agent-host] first-login 完了: $(date -Is)"
