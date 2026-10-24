#!/usr/bin/env bash
# UPS(無停電電源装置)を NUT(Network UPS Tools)で見る(env.yaml の ups)。
#   usb:       この PC につないだ UPS をドライバーで読み、upsd(127.0.0.1 だけ)と upsmon(primary)で見る
#   netclient: ほかの機器の NUT サーバーを upsmon(secondary)で見る
# バッテリーが少なくなった(LB)か、NUT サーバーが終了を指示した(FSD)ら、正しく終了する。
# usb では、終了の最後に UPS の出力を止めさせる(NUT の nutshutdown が POWERDOWNFLAG を見て upsdrvctl shutdown)。
# 電源が戻ると UPS が出力を戻し、BIOS の「電源が戻ったら起動」で PC が起動する(UPS が出力を止めないと、PC は
# 電源が切れたことに気づかず起動しない)。netclient では出力を止めるのは NUT サーバーの側。
# 切り替わり(バッテリー運転、復電、まもなく終了など)は agent-notify で知らせる。
# 実際の UPS での終了と起動は未確認(VM では NUT の dummy-ups で確かめた範囲。docs/notes.md)
set -euo pipefail
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"
load_env

mode="${AH_UPS_MODE:-none}"

# --- 使わない: 前に入れていたら止める(パッケージは消さない) ---
if [ "$mode" = none ]; then
    if [ -f /etc/nut/nut.conf ]; then
        # MODE=none にすると、nutshutdown も終了のときに UPS の出力を止めない
        printf '# agent-host-autoinstall が置いた設定(env.yaml の ups)\nMODE=none\n' >/etc/nut/nut.conf
        systemctl disable --now nut.target nut-monitor.service nut-server.service \
            nut-driver-enumerator.service nut-driver-enumerator.path >/dev/null 2>&1 || true
        rm -f /etc/killpower
        log "UPS を見るのをやめた(env.yaml の ups.mode が none)"
    fi
    exit 0
fi

apt-get install -y nut-client acl
if [ "$mode" = usb ]; then
    apt-get install -y nut-server
    [ -x "/usr/libexec/nut/$AH_UPS_DRIVER" ] || { log "NUT のドライバー $AH_UPS_DRIVER がない(ups.driver を確かめる)"; exit 1; }
fi

install -d -m 750 -o root -g nut /etc/nut
# 設定は root と nut だけが読める(パスワードが入る)
write_nut() {
    local name="$1" tmp
    tmp="$(mktemp)"
    # NUT は設定の ASCII 以外の文字を捨てる(コメントでも警告が出る)ので、中身は英語にする
    { echo "# Written by agent-host-autoinstall (85-ups.sh) from env.yaml ups"; cat; } >"$tmp"
    install -m 640 -o root -g nut "$tmp" "/etc/nut/$name"
    rm -f "$tmp"
}

if [ "$mode" = usb ]; then
    printf 'MODE=standalone\n' | write_nut nut.conf
    write_nut ups.conf <<EOF
maxretry = 3

[$AH_UPS_NAME]
    driver = "$AH_UPS_DRIVER"
    port = "$AH_UPS_PORT"
    desc = "UPS of $AH_HOSTNAME"
EOF
    # upsd はこの PC の中からだけ受け付ける(LAN の他の機器に配らない)
    printf 'LISTEN 127.0.0.1 3493\nLISTEN ::1 3493\n' | write_nut upsd.conf
    # upsmon が upsd に入るためのユーザー。パスワードはこのホストで作り、次からも同じものを使う
    pw_file=/var/lib/agent-host/ups-upsmon.password
    if [ ! -s "$pw_file" ]; then
        (umask 077; openssl rand -hex 16 >"$pw_file")
    fi
    pw="$(cat "$pw_file")"
    write_nut upsd.users <<EOF
[upsmon]
    password = $pw
    upsmon primary
EOF
    monitor="$AH_UPS_NAME@localhost 1 upsmon $pw primary"
else
    printf 'MODE=netclient\n' | write_nut nut.conf
    monitor="$AH_UPS_NAME@$AH_UPS_SERVER 1 $AH_UPS_USER $AH_UPS_PASSWORD secondary"
fi

write_nut upsmon.conf <<EOF
RUN_AS_USER nut
MONITOR $monitor
MINSUPPLIES 1
SHUTDOWNCMD "/sbin/shutdown -h +0"
NOTIFYCMD /usr/local/sbin/agent-host-ups-notify
NOTIFYFLAG ONLINE SYSLOG+EXEC
NOTIFYFLAG ONBATT SYSLOG+EXEC
NOTIFYFLAG LOWBATT SYSLOG+EXEC
NOTIFYFLAG FSD SYSLOG+EXEC
NOTIFYFLAG SHUTDOWN SYSLOG+EXEC
NOTIFYFLAG COMMBAD SYSLOG+EXEC
NOTIFYFLAG COMMOK SYSLOG+EXEC
NOTIFYFLAG NOCOMM SYSLOG+EXEC
NOTIFYFLAG REPLBATT SYSLOG+EXEC
POLLFREQ 5
POLLFREQALERT 5
HOSTSYNC 15
DEADTIME 15
POWERDOWNFLAG "/etc/killpower"
FINALDELAY 5
EOF

# 通知: upsmon は nut で動くので、通知の送り先(notify.env)を nut にも読ませる(ACL。ほかの人には読ませない)
install -m 755 "$AH_ROOT/notify/agent-host-ups-notify" /usr/local/sbin/agent-host-ups-notify
if [ -f /etc/agent-host/notify.env ]; then
    setfacl -m u:nut:r /etc/agent-host/notify.env
fi

# 起動する(設定を変えたときに読み直させる)。
# パッケージを入れた時点で、設定が空の upsd が起動して失敗を繰り返し、起動の回数の上限に掛かっている
# ことがある(VirtualBox で確認)。失敗の記録を消してから起動する
systemctl reset-failed 'nut-*' >/dev/null 2>&1 || true
if [ "$mode" = usb ]; then
    systemctl enable nut.target nut-driver-enumerator.path nut-driver-enumerator.service \
        nut-server.service nut-monitor.service >/dev/null
    systemctl restart nut-driver-enumerator.service
    systemctl restart nut-driver.target nut-server.service || log "注意: UPS のドライバーか upsd が起動しない(UPS がつながっているか、ups.driver と ups.port を確かめる)"
else
    systemctl disable --now nut-server.service >/dev/null 2>&1 || true
    systemctl enable nut.target nut-monitor.service >/dev/null
fi
systemctl restart nut-monitor.service
log "UPS を NUT で見るようにした(${mode}。$AH_UPS_NAME${AH_UPS_SERVER:+@$AH_UPS_SERVER})"
