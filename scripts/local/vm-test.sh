#!/usr/bin/env bash
# VirtualBox の VM に、今のスクリプトで作った ISO を入れなおし、受け入れテストのうち機械で確かめられるものを通しで行う。
#   1. ISO を作る → VM のディスクを空にして ISO から起動する(無人インストール → 初回の構成 → 利用者ごとのセッション)
#   2. 利用者全員の RDP が待ち受けるまで待ち、just verify と just verify-rdp
#   3. 電源を切って(強制)起動しなおし、人手なしで戻るか(2 と同じ検査)
#   4. 1 人目の gnome-shell を落とし、その人のセッションだけが立ちなおり、2 人目は続いているか(RDP の認証)
# VM が無ければ作る。あれば、ディスクを消して作りなおす(VM の中身はすべて消える)。
#
# 使い方: scripts/local/vm-test.sh <env.yaml>...(just vm-test)
#   env.yaml は試験用のもの。lan_cidrs に VirtualBox の NAT(10.0.2.0/24)を入れ、sysadmin の公開鍵に
#   AGENT_HOST_VM_SSH_KEY の鍵を入れておく。users は 2 人以上にし、port は 3389〜3392 にする
#   (VM は 127.0.0.1:13389〜13392 に転送する。docs/release.md)
# 環境変数(括弧内は既定):
#   AGENT_HOST_SUDO_PASSWORD  sysadmin の sudo のパスワード(無ければ最初に聞く)
#   AGENT_HOST_VM_NAME        VM の名前(agent-host-vm)
#   AGENT_HOST_VM_SSH_KEY     sysadmin の秘密鍵(build/test/id_ed25519)
#   AGENT_HOST_VM_CPUS        CPU の数(1。Hyper-V と共存する Windows の VirtualBox では 2 以上で止まった。docs/notes.md)
#   AGENT_HOST_VM_MEMORY      メモリ(MB。4096)
#   AGENT_HOST_VM_TIMEOUT     インストールから RDP が待ち受けるまで待つ時間(分。120)
#   VBOXMANAGE                VBoxManage のパス(PATH に無ければ Windows の既定の場所)
set -euo pipefail
# shellcheck source=envs.sh
. "$(dirname "$0")/envs.sh"

[ $# -ge 1 ] || { echo "試験用の env.yaml を指定する" >&2; exit 2; }
envs=("$@")
name="${AGENT_HOST_VM_NAME:-agent-host-vm}"
key="$(resolve_path "${AGENT_HOST_VM_SSH_KEY:-build/test/id_ed25519}")"
cpus="${AGENT_HOST_VM_CPUS:-1}"
memory="${AGENT_HOST_VM_MEMORY:-4096}"
timeout_min="${AGENT_HOST_VM_TIMEOUT:-120}"
ssh_port=2222
# 利用者の RDP のポート 3389〜3392 を、手元の PC の 13389〜13392 に転送する(verify-rdp はポートに 10000 を足す)
rdp_ports=(3389 3390 3391 3392)
export AGENT_HOST_RDP_PORT_OFFSET=10000
vbm="${VBOXMANAGE:-$(command -v VBoxManage || echo "/c/Program Files/Oracle/VirtualBox/VBoxManage.exe")}"
[ -x "$vbm" ] || { echo "VBoxManage がない(VBOXMANAGE で場所を指定する)" >&2; exit 1; }
[ -f "$key" ] || { echo "$key がない(AGENT_HOST_VM_SSH_KEY で指定する)" >&2; exit 1; }
iso="build/$name.iso"
base="build/vm"

export AGENT_HOST_SSH_OPTS="-p $ssh_port -i $key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10 -o BatchMode=yes"
# shellcheck disable=SC2206  # オプションは空白で分けて渡す
ssh_opts=($AGENT_HOST_SSH_OPTS)
if [ -z "${AGENT_HOST_SUDO_PASSWORD:-}" ]; then
    read -rsp "VM の sysadmin の sudo のパスワード: " AGENT_HOST_SUDO_PASSWORD </dev/tty
    echo >&2
fi
export AGENT_HOST_SUDO_PASSWORD

# VBoxManage は Windows では Windows の形のパスを受け取る
winpath() { if command -v cygpath >/dev/null; then cygpath -w "$1"; else printf '%s\n' "$1"; fi; }
# shellcheck disable=SC2029  # コマンドは手元で組み立てて VM に渡す
vm_ssh() { ssh "${ssh_opts[@]}" sysadmin@127.0.0.1 "$@"; }
vm_sudo() { printf '%s\n' "$AGENT_HOST_SUDO_PASSWORD" | vm_ssh "sudo -S -p '' $*"; }
vm_state() { "$vbm" showvminfo "$name" --machinereadable | sed -n 's/^VMState="\(.*\)"/\1/p'; }
step() { printf '\n=== %s (%s)\n' "$1" "$(date +%H:%M:%S)"; }

results=()
record() { results+=("$1 $2"); }
# check_all <場面>: 構成の検査と RDP の認証
check_all() {
    if scripts/local/host.sh verify 127.0.0.1; then record ✓ "$1: just verify"; else record ✗ "$1: just verify"; fi
    if scripts/local/host.sh verify-rdp 127.0.0.1 "${envs[@]}"; then
        record ✓ "$1: just verify-rdp"
    else
        record ✗ "$1: just verify-rdp"
    fi
}
# wait_ready <分> [<前の起動の boot_id>]: 構成が終わり、利用者全員の RDP が待ち受けるまで待つ
# (boot_id を渡すと、起動しなおしたことも確かめる)。利用者の数は agent-host-users グループの人数
wait_ready() {
    local deadline=$((SECONDS + $1 * 60)) old_boot="${2:-}" boot
    while [ "$SECONDS" -lt "$deadline" ]; do
        case "$(vm_state)" in poweroff | aborted) echo "VM が止まった" >&2; return 1 ;; esac
        # shellcheck disable=SC2016  # VM の中で展開する
        boot="$(vm_ssh 'test -f /var/lib/agent-host/provisioned &&
            n="$(getent group agent-host-users | cut -d: -f4 | tr , "\n" | grep -c .)" &&
            [ "$n" -gt 0 ] && [ "$(ss -tlnH | awk "{print \$4}" | grep -c -E ":339[0-2]\$")" -ge "$n" ] &&
            cat /proc/sys/kernel/random/boot_id' 2>/dev/null || true)"
        if [ -n "$boot" ] && [ "$boot" != "$old_boot" ]; then
            sleep 30  # セッションの中の自動起動(Orca など)を待つ
            return 0
        fi
        sleep 30
    done
    echo "$1 分待っても RDP が待ち受けなかった" >&2
    return 1
}
# user_session <利用者>: その利用者のセッションの番号
user_session() { vm_ssh "loginctl list-sessions --no-legend | awk '\$3 == \"$1\" && \$6 == \"user\" {print \$1}'" 2>/dev/null || true; }
shell_pid() { vm_ssh "pgrep -u $1 -x gnome-shell" 2>/dev/null || true; }
summary() {
    local r fail=0
    printf '\n=== 結果\n'
    for r in "${results[@]}"; do
        printf '  %s\n' "$r"
        [[ "$r" == ✗* ]] && fail=1
    done
    return "$fail"
}

step "1. ISO を作る(${envs[*]})"
scripts/local/iso.sh build "build/ubuntu-26.04.1-desktop-amd64.iso" "$iso" "${envs[@]}"

step "1. VM($name)のディスクを作りなおし、ISO から起動する"
if ! "$vbm" showvminfo "$name" >/dev/null 2>&1; then
    "$vbm" createvm --name "$name" --ostype Ubuntu_64 --basefolder "$(winpath "$base")" --register
    "$vbm" modifyvm "$name" --firmware efi --memory "$memory" --cpus "$cpus" --vram 128 \
        --graphicscontroller vmsvga --nic1 nat --audio-enabled off --usb-ohci off \
        --boot1 disk --boot2 dvd --boot3 none --boot4 none \
        --natpf1 "ssh,tcp,127.0.0.1,$ssh_port,,22"
    "$vbm" storagectl "$name" --name SATA --add sata --controller IntelAhci --portcount 2
else
    case "$(vm_state)" in running | paused | stuck) "$vbm" controlvm "$name" poweroff; sleep 5 ;; esac
    old_disk="$("$vbm" showvminfo "$name" --machinereadable | sed -n 's/^"SATA-0-0"="\(.*\)"/\1/p')"
    if [ -n "$old_disk" ] && [ "$old_disk" != none ]; then
        "$vbm" storageattach "$name" --storagectl SATA --port 0 --device 0 --medium none
        "$vbm" closemedium disk "$old_disk" --delete
    fi
fi
# 利用者の RDP の転送をそろえる。名前が rdp で始まる転送(0.2 までの 3389 の 1 本や、手で足したもの)を消してから足す
while read -r rule; do
    "$vbm" modifyvm "$name" --natpf1 delete "$rule"
done < <("$vbm" showvminfo "$name" --machinereadable | sed -n 's/^Forwarding([0-9]*)="\(rdp[^,]*\),.*/\1/p')
for p in "${rdp_ports[@]}"; do
    "$vbm" modifyvm "$name" --natpf1 "rdp$p,tcp,127.0.0.1,$((p + 10000)),,$p"
done
disk="$base/$name/$name-$(date +%Y%m%d-%H%M%S).vdi"
mkdir -p "$(dirname "$disk")"
"$vbm" createmedium disk --filename "$(winpath "$disk")" --size 40960 --format VDI
"$vbm" storageattach "$name" --storagectl SATA --port 0 --device 0 --type hdd --medium "$(winpath "$disk")"
"$vbm" storageattach "$name" --storagectl SATA --port 1 --device 0 --type dvddrive --medium "$(winpath "$iso")"
"$vbm" startvm "$name" --type headless

step "2. インストールと構成を待つ(最大 $timeout_min 分)"
if wait_ready "$timeout_min"; then
    record ✓ "インストールから RDP の待ち受けまで(人手なし)"
    check_all "入れた直後"
else
    record ✗ "インストールから RDP の待ち受けまで(人手なし)"
    summary || true
    exit 1
fi

step "3. 電源を切って(強制)起動しなおす"
boot="$(vm_ssh cat /proc/sys/kernel/random/boot_id)"
"$vbm" controlvm "$name" poweroff
sleep 5
"$vbm" startvm "$name" --type headless
if wait_ready 15 "$boot"; then
    record ✓ "電源を切ったあと、RDP の待ち受けまで(人手なし)"
    check_all "電源を切ったあと"
else
    record ✗ "電源を切ったあと、RDP の待ち受けまで(人手なし)"
fi

step "4. 1 人目の gnome-shell を落とし、その人だけが立ちなおるか"
mapfile -t vm_users < <(vm_ssh "getent group agent-host-users | cut -d: -f4 | tr , '\n'" 2>/dev/null | grep . || true)
if [ "${#vm_users[@]}" -lt 2 ]; then
    record ✗ "利用者が 2 人以上いない(試験用の env.yaml の users を 2 人以上にする)"
    summary
    exit 1
fi
u1="${vm_users[0]}"
u2="${vm_users[1]}"
before="$(user_session "$u1")"
other_before="$(shell_pid "$u2")"
vm_sudo pkill -SEGV -u "$u1" -x gnome-shell || true
deadline=$((SECONDS + 300))
now=""
while [ "$SECONDS" -lt "$deadline" ]; do
    sleep 20
    now="$(user_session "$u1")"
    if [ -n "$now" ] && [ "$now" != "$before" ]; then
        break
    fi
    now=""
done
if [ -n "$now" ]; then
    sleep 60  # RDP の待ち受けが戻るのを待つ(起動のときは約 60 秒かかった)
    record ✓ "$u1 のセッションが落ちたあと、新しいセッション(${before:-なし} → $now)"
    if scripts/local/host.sh verify-rdp 127.0.0.1 "${envs[@]}"; then
        record ✓ "セッションが落ちたあと: just verify-rdp(全員)"
    else
        record ✗ "セッションが落ちたあと: just verify-rdp(全員)"
    fi
else
    record ✗ "$u1 のセッションが落ちたあと、5 分以内に新しいセッション(前は ${before:-なし})"
fi
if [ -n "$other_before" ] && [ "$(shell_pid "$u2")" = "$other_before" ]; then
    record ✓ "$u1 が落ちても、$u2 の gnome-shell は続いている(PID $other_before)"
else
    record ✗ "$u1 が落ちたとき、$u2 の gnome-shell が変わった(${other_before:-なし} → $(shell_pid "$u2"))"
fi

summary
