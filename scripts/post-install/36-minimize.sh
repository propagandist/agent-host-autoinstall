#!/usr/bin/env bash
# 常時稼働のエージェントホストに要らないサービスを止め、資源の使い方を詰める。
# 止めたものは mask するので、ほかのパッケージから起こされない。戻すときは systemctl unmask。
# どれを止めるかは、VirtualBox で動いているサービスを洗い出して決めた(docs/notes.md)。
set -euo pipefail
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"

# 入っていない unit を指定しても止まらないように、あるものだけ mask する
mask_units() {
    local unit
    for unit in "$@"; do
        if systemctl list-unit-files "$unit" --no-legend 2>/dev/null | grep -q .; then
            systemctl mask --now "$unit" >/dev/null 2>&1 || systemctl mask "$unit" >/dev/null
            # 動いている途中で止めた unit は failed の印が残り、systemctl --failed に出続けるので消す
            systemctl reset-failed "$unit" >/dev/null 2>&1 || true
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

# 7. snap と snapd(Chrome が既定のブラウザで、snap で入れるものはない。snapd の常駐と、snap 一式の約 1.3GB を減らす)。
# snapd を消すと、入っている snap(セキュリティセンター、権限の確認、ハードウェアの検査など)も消える。
# firefox のパッケージは snap を入れるための中身のないものなので一緒に消す。apt でまた入らないように止める
if dpkg-query -W -f='${Status}' snapd 2>/dev/null | grep -q 'install ok installed'; then
    # 初回起動の直後は snap の初期化(seed)が終わっていないことがあるので待つ
    snap wait system seed.loaded || true
    apt-get purge -y snapd firefox
    rm -rf /var/cache/snapd /root/snap
    agent_run rm -rf "$AGENT_HOME/snap"
fi
cat >/etc/apt/preferences.d/agent-host-no-snapd.pref <<'EOF'
# agent-host-autoinstall が置いた設定: snapd を入れない(36-minimize.sh)
Package: snapd
Pin: release a=*
Pin-Priority: -10
EOF

# 7b. 使わないパッケージ(止めるだけでなく消す)
#   画面の読み上げ・点字(読み上げの orca は /usr/bin/orca で、Orca(orca-ide)と名前がぶつかる)、印刷のドライバー、
#   AD・LDAP(sssd)、VPN・モデム、Bluetooth、中国語の入力、エラーと利用状況の報告。
#   cups 本体はデスクトップのまとめ(ubuntu-desktop-minimal)の必須なので残す(1. で止めている)。
#   whoopsie-preferences と apport-symptoms は消すと GNOME の画面まで外れるので残す
purge_pkgs=()
mapfile -t purge_pkgs < <(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' \
    orca speech-dispatcher speech-dispatcher-audio-plugins speech-dispatcher-espeak-ng espeak-ng-data brltty \
    hplip hplip-data 'printer-driver-*' bluez-cups \
    'sssd*' openvpn pptp-linux ppp modemmanager bluez bluez-obexd 'ibus-table*' \
    whoopsie apport apport-gtk apport-core-dump-handler ubuntu-report ubuntu-insights 2>/dev/null |
    awk '$1 == "ii" {print $2}')
if [ "${#purge_pkgs[@]}" -gt 0 ]; then
    # 念のため、デスクトップを巻き込まないことを確かめてから消す
    if apt-get -s purge "${purge_pkgs[@]}" | grep -qE '^Purg (ubuntu-desktop-minimal|gdm3|gnome-shell|gnome-control-center|network-manager) '; then
        log "注意: 使わないパッケージを消すとデスクトップまで外れるので、消さなかった"
    else
        apt-get purge -y "${purge_pkgs[@]}"
        log "使わないパッケージを ${#purge_pkgs[@]} 個消した"
    fi
fi

# 8. kdump(クラッシュ時の調査用。32〜64GB の機種で 1GB のメモリを常に予約する)
if dpkg-query -W -f='${Status}' kdump-tools 2>/dev/null | grep -q 'install ok installed'; then
    apt-get purge -y kdump-tools
fi

# 9. そのほか(journald と記録が二重の rsyslog、NetworkManager では使わない networkd-dispatcher、
#    インストールが終われば要らない cloud-init、有効なだけの openvpn・sssd)。
#    syslog.socket は rsyslog を起こそうとして失敗し続けるので一緒に止める
mask_units rsyslog.service syslog.socket networkd-dispatcher.service openvpn.service sssd.service
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
# zram はディスクより速いので早めにスワップへ逃がし(swappiness は 0〜200、既定 60)、先読みは止める。
# 値は Pop!_OS の zram の設定にならった。カーネルの文書は、zram では 100 を超える値も「考えられる」とするだけ(#18)
cat >/etc/sysctl.d/60-agent-host-zram.conf <<'EOF'
# agent-host-autoinstall が置いた設定
vm.swappiness = 180
vm.page-cluster = 0
EOF
sysctl -q -p /etc/sysctl.d/60-agent-host-zram.conf

# 14. 電源のプロファイル(ビルドやテストを速くする)
if command -v powerprofilesctl >/dev/null; then
    powerprofilesctl set performance || log "注意: 電源のプロファイルを performance にできなかった"
fi

# 15. 正しく終了しなかったあとの GRUB の待ちを 30 秒から 5 秒に(停電からの復帰を早くする)。
#     起動画面(splash)は出さない(モニターをつながないので見る人がいない。起動が少し速くなる)
printf '# agent-host-autoinstall が置いた設定\nGRUB_RECORDFAIL_TIMEOUT=5\nGRUB_CMDLINE_LINUX_DEFAULT="quiet"\n' \
    >/etc/default/grub.d/60-agent-host.cfg
update-grub >/dev/null 2>&1

log "snap・kdump の削除、zram、電源のプロファイル、GRUB の待ちと起動画面を設定した"
