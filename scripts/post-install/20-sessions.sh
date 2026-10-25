#!/usr/bin/env bash
# 利用者ごとのヘッドレスの GNOME のセッションと RDP(gnome-remote-desktop の headless)を設定する。
# セッションを立てるのは、ほかの設定(キーリング、first-login)が済んだあとの 88-start-sessions.sh。
# 0.2 までの作り(seat0 への agent の自動ログインと、セッションの見張り)はやめる。
set -euo pipefail
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"
load_env

# --- 0.2 までの作りをやめる ---
# 26.04 の gdm3 50.x でも設定ファイルは /etc/gdm3/custom.conf の [daemon](ソースで確認済み)
conf=/etc/gdm3/custom.conf
was_autologin=false
if grep -qx 'AutomaticLoginEnable *= *[Tt]rue' "$conf" 2>/dev/null; then
    was_autologin=true
fi
ini_set "$conf" daemon AutomaticLoginEnable false
sed -i '/^AutomaticLogin *=/d; /^TimedLogin/d' "$conf"
if [ -e /etc/systemd/system/agent-host-session-watchdog.timer ]; then
    systemctl disable --now agent-host-session-watchdog.timer || true
    rm -f /etc/systemd/system/agent-host-session-watchdog.timer /etc/systemd/system/agent-host-session-watchdog.service \
        /usr/local/sbin/agent-host-session-watchdog
    log "セッションの見張り(0.2 まで)を外した"
fi

# --- ヘッドレスのセッションのユニットを直す ---
install -d -m 755 /etc/systemd/system/gnome-headless-session@.service.d
cat >/etc/systemd/system/gnome-headless-session@.service.d/50-agent-host.conf <<'EOF'
# agent-host-autoinstall(20-sessions.sh)が置いた設定(#15 の段 0、VirtualBox で確認)
# DynamicUser のままだと gdm-new-session が「The connection is closed」で止まった。gdm の polkit の規則(20-gdm.rules)は
# gdm グループで、ユニット名が gnome-headless-session@<利用者>.service のときに許すので、静的な gdm で動かす。
# gnome-shell が落ちると gdm-new-session は 0 で終わり、Restart=on-failure では戻らなかったので always にする
[Service]
DynamicUser=no
User=gdm
Restart=always
RestartSec=5
EOF
systemctl daemon-reload

# --- 利用者ごとの RDP ---
setup_rdp() {
    local uid cert_dir have
    uid="$(id -u "$AGENT_USER")"
    # ユーザーのバスを常に置く(セッションがなくても grdctl・gsettings を使えるように。rootless Docker も使う)
    loginctl enable-linger "$AGENT_USER"
    for _ in $(seq 1 30); do
        [ -S "/run/user/$uid/bus" ] && break
        sleep 1
    done
    [ -S "/run/user/$uid/bus" ] || { log "$AGENT_USER のユーザーのバスが立たない"; exit 1; }

    # 0.2 までの seat0 の共有(gnome-remote-desktop.service)と、認証情報の受け渡しをやめる。headless のものと同時には動かない
    agent_bus_run systemctl --user disable --now gnome-remote-desktop.service >/dev/null 2>&1 || true
    agent_run rm -f "$AGENT_HOME/.config/autostart/agent-host-rdp-credentials.desktop" "$AGENT_HOME/.config/agent-host/rdp.env"

    # TLS 証明書は grdctl もデーモンも作らないので自分で作る(置き場所は upstream の docs/configuration.md の慣例。
    # 0.2 までの agent と同じ場所なので、上げたホストでは証明書の指紋が変わらない)
    cert_dir="$AGENT_HOME/.local/share/gnome-remote-desktop"
    if ! agent_run test -f "$cert_dir/tls.crt" || ! agent_run test -f "$cert_dir/tls.key"; then
        agent_run mkdir -p "$cert_dir"
        agent_run openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 -subj "/CN=$(hostname)" \
            -keyout "$cert_dir/tls.key" -out "$cert_dir/tls.crt" 2>/dev/null
        agent_run chmod 600 "$cert_dir/tls.key"
    fi
    # grdctl は "RDP server certificate is invalid" と "Init TPM credentials failed" を出すが、待ち受けと認証は正常
    # (VirtualBox。今の作りでも出ていた)。ポートは利用者に固定し、使われていても別のポートへずらさない
    agent_bus_run grdctl --headless rdp set-port "$AH_USER_PORT" 2>/dev/null
    agent_bus_run grdctl --headless rdp set-tls-cert "$cert_dir/tls.crt" 2>/dev/null
    agent_bus_run grdctl --headless rdp set-tls-key "$cert_dir/tls.key" 2>/dev/null
    agent_bus_run grdctl --headless rdp disable-view-only 2>/dev/null
    agent_bus_run grdctl --headless rdp disable-port-negotiation 2>/dev/null
    # 認証情報は、まだないときだけ仮の値を入れる。本人が最初の RDP で変えたものは上書きしない。
    # TPM がないと ~/.local/share/gnome-remote-desktop/credentials.ini(600)に入る
    have="$(agent_bus_run grdctl --headless status --show-credentials 2>/dev/null | sed -n 's/^[[:space:]]*Username:[[:space:]]*//p' | head -1)"
    # 認証情報がないと Username は (null) と出る(gnome-remote-desktop 50.2、VirtualBox で確認)
    if [ -z "$have" ] || [ "$have" = "(null)" ] || [ "$have" = "(empty)" ]; then
        agent_bus_run grdctl --headless rdp set-credentials "$AH_RDP_USER" "$AH_RDP_INITIAL_PASSWORD" 2>/dev/null
        # 動いているデーモンは起動したときの認証情報を使い続けるので、動いていれば再起動する(VirtualBox で確認)
        agent_bus_run systemctl --user try-restart gnome-remote-desktop-headless.service >/dev/null 2>&1 || true
        log "$AGENT_USER の RDP の認証情報に仮のパスワードを入れた(本人が最初の RDP で変える)"
    fi
    agent_bus_run grdctl --headless rdp enable 2>/dev/null
    agent_bus_run systemctl --user enable gnome-remote-desktop-headless.service >/dev/null 2>&1
    log "$AGENT_USER の RDP をポート $AH_USER_PORT で設定した"
}
for_each_user setup_rdp

# 0.2 から上げたホストでは、seat0 の agent のセッションが残っている。GDM を再起動して終わらせる
# (動いていた端末やエージェントも終わる。CHANGELOG の「env.yaml の変更」に書いた)。
# ヘッドレスのセッションは 88-start-sessions.sh が立てる
if $was_autologin && systemctl is-active --quiet gdm.service; then
    systemctl restart gdm.service
    log "自動ログインをやめたので GDM を再起動した(seat0 のセッションは終わった)"
fi
