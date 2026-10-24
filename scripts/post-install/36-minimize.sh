#!/usr/bin/env bash
# 常時稼働のエージェントホストに要らないサービスを止め、資源の使い方を詰める。
# 止めたものは mask するので、ほかのパッケージから起こされない。戻すときは systemctl unmask。
# どれを止めるかは、VirtualBox で動いているサービスを洗い出して決めた(HANDOVER.md)。
set -euo pipefail
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"

# 入っていない unit を指定しても止まらないように、あるものだけ mask する
mask_units() {
    local unit
    for unit in "$@"; do
        if systemctl list-unit-files "$unit" --no-legend 2>/dev/null | grep -q .; then
            systemctl mask --now "$unit" >/dev/null 2>&1 || systemctl mask "$unit" >/dev/null
        fi
    done
}
# agent のセッションで動く unit(systemd のユーザー側)。全ユーザーに効く --global で mask する
mask_user_units() {
    local unit
    for unit in "$@"; do
        if systemctl --global list-unit-files "$unit" --no-legend 2>/dev/null | grep -q .; then
            systemctl --global mask "$unit" >/dev/null
        fi
    done
}
# ログイン時の自動起動を agent だけ止める(/etc/xdg/autostart の同名ファイルを Hidden で上書きする)
hide_autostart() {
    local name
    for name in "$@"; do
        [ -f "/etc/xdg/autostart/$name.desktop" ] || continue
        printf '[Desktop Entry]\nType=Application\nName=%s\nHidden=true\n' "$name" |
            write_agent_file 644 "$AGENT_HOME/.config/autostart/$name.desktop"
    done
}

# 1. 印刷
mask_units cups.service cups.socket cups.path cups-browsed.service
mask_user_units org.gnome.SettingsDaemon.PrintNotifications.service
# 2. ネットワークの自動検出と無線・携帯回線・GPU の切り替え(wpa_supplicant は有線の 802.1X に要るので残す)
mask_units avahi-daemon.service avahi-daemon.socket ModemManager.service bluetooth.service \
    switcheroo-control.service
mask_user_units org.gnome.SettingsDaemon.Wwan.service org.gnome.SettingsDaemon.Smartcard.service \
    mpris-proxy.service
# 3. root の containerd は、Docker を入れたあとの 65-docker.sh で止める
# 4. 外への送信と定期の取得(Canonical への利用状況の送信、MOTD のニュース、更新の通知、ファームウェアの情報)
mask_units motd-news.timer update-notifier-download.timer update-notifier-motd.timer fwupd-refresh.timer
[ -f /etc/default/motd-news ] && sed -i 's/^ENABLED=.*/ENABLED=0/' /etc/default/motd-news
mask_user_units ubuntu-insights-collect.timer ubuntu-insights-upload.timer
# 5. ファイルの索引作り(ホーム全体を索引し、worktree や node_modules で CPU とディスクを使う)
mask_user_units localsearch-3.service
hide_autostart localsearch-3
# 6. agent のセッションの不要な常駐(予定表・連絡先、携帯・カメラ・オンラインアカウントの監視、位置情報、
#    Ubuntu Pro と利用報告の通知、ディスクの通知、snap の補助、Mozc のために常に起動される Xwayland)
mask_user_units evolution-addressbook-factory.service evolution-calendar-factory.service \
    evolution-source-registry.service gvfs-afc-volume-monitor.service gvfs-gphoto2-volume-monitor.service \
    gvfs-mtp-volume-monitor.service gvfs-goa-volume-monitor.service
hide_autostart org.gnome.Evolution-alarm-notify geoclue-demo-agent ubuntu-advantage-notification \
    ubuntu-report-on-upgrade org.gnome.SettingsDaemon.DiskUtilityNotify snap-userd-autostart \
    ibus-mozc-launch-xwayland
log "要らないサービスを止めた"

# 7. snap のアプリ(Chrome が既定のブラウザ。agent は App Center から入れられない)。snapd はほかの snap が使うので残す
# 初回起動の直後は snap の初期化(seed)が終わっていないことがあるので待つ
snap wait system seed.loaded
for snap in firefox snap-store firmware-updater; do
    if snap list "$snap" >/dev/null 2>&1; then
        snap remove --purge "$snap"
    fi
done

# 8. kdump(クラッシュ時の調査用。32〜64GB の機種で 1GB のメモリを常に予約する)
if dpkg-query -W -f='${Status}' kdump-tools 2>/dev/null | grep -q 'install ok installed'; then
    apt-get purge -y kdump-tools
fi

# 9. そのほか(journald と記録が二重の rsyslog、NetworkManager では使わない networkd-dispatcher、
#    インストールが終われば要らない cloud-init、有効なだけの openvpn・sssd)
mask_units rsyslog.service networkd-dispatcher.service openvpn.service sssd.service
touch /etc/cloud/cloud-init.disabled

# 10. zram(メモリの半分を圧縮したスワップにする。ファイルのスワップは優先度の低い予備として残す)
apt-get install -y systemd-zram-generator
cat >/etc/systemd/zram-generator.conf <<'EOF'
# agent-host-autoinstall が置いた設定
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
swap-priority = 100
EOF
systemctl daemon-reload
systemctl restart systemd-zram-setup@zram0.service || log "注意: zram を今は作れなかった(次の起動で作られる)"

# 14. 電源のプロファイル(ビルドやテストを速くする)
if command -v powerprofilesctl >/dev/null; then
    powerprofilesctl set performance || log "注意: 電源のプロファイルを performance にできなかった"
fi

# 15. RDP の画面の符号化を Intel の内蔵 GPU に任せる(VA-API。GPU がなければ使われないだけ)
apt-get install -y intel-media-va-driver

# 16. 正しく終了しなかったあとの GRUB の待ちを 30 秒から 5 秒に(停電からの復帰を早くする)
printf '# agent-host-autoinstall が置いた設定\nGRUB_RECORDFAIL_TIMEOUT=5\n' >/etc/default/grub.d/60-agent-host.cfg
update-grub >/dev/null 2>&1

log "snap・kdump の削除、zram、電源のプロファイル、VA-API、GRUB の待ちを設定した"
