#!/usr/bin/env bash
# VM(VirtualBox か QEMU/KVM)に、今のスクリプトで作った ISO を入れなおし、受け入れテストのうち機械で確かめられるものを通しで行う。
#   1. ISO を作る → VM のディスクを空にして ISO から起動する(無人インストール → 初回の構成 → 利用者ごとのセッション)
#   2. 利用者全員の RDP が待ち受けるまで待ち、just verify と just verify-rdp
#   3. 電源を切って(強制)起動しなおし、人手なしで戻るか(2 と同じ検査)
#   4. 1 人目の gnome-shell を落とし、その人のセッションだけが立ちなおり、2 人目は続いているか(RDP の認証)
# VM が無ければ作る。あれば、ディスクを消して作りなおす(VM の中身はすべて消える)。
#
# 使い方: scripts/local/vm-test.sh <env.yaml>...(just vm-test)
#   env.yaml は試験用のもの。lan_cidrs に VM の NAT(VirtualBox も QEMU も 10.0.2.0/24)を入れ、sysadmin の公開鍵に
#   AGENT_HOST_VM_SSH_KEY の鍵を入れておく。users は 2 人以上にし、port は 3389〜3392 にする
#   (VM は 127.0.0.1:13389〜13392 に転送する。docs/release.md)
# VM の道具: AGENT_HOST_VM_BACKEND で決める。指定がなければ、VBoxManage があれば VirtualBox、なくて
#   qemu-system-x86_64 と /dev/kvm があれば QEMU(エージェントのホストでは env.yaml の vm で入る)。
#   kvm のグループに入っていても今のセッションに効いていなければ、sg kvm で実行しなおす
# 環境変数(括弧内は既定):
#   AGENT_HOST_SUDO_PASSWORD  sysadmin の sudo のパスワード(無ければ最初に聞く)
#   AGENT_HOST_VM_BACKEND     virtualbox か qemu(上のとおり自動で選ぶ)
#   AGENT_HOST_VM_NAME        VM の名前(agent-host-vm)
#   AGENT_HOST_VM_SSH_KEY     sysadmin の秘密鍵(build/test/id_ed25519)
#   AGENT_HOST_VM_CPUS        CPU の数(VirtualBox は 1。Hyper-V と共存する Windows の VirtualBox では 2 以上で止まった。
#                             docs/notes.md。QEMU は 2)
#   AGENT_HOST_VM_MEMORY      メモリ(MB。4096)
#   AGENT_HOST_VM_TIMEOUT     インストールから RDP が待ち受けるまで待つ時間(分。120)
#   AGENT_HOST_VM_REUSE       1 なら入れなおさず、動いている VM で 2(検査)から行う(手で直したあとの確かめなおし。
#                             無人で最後まで通ったことにはならない)
#   AGENT_HOST_VM_SSH_PORT    VM の SSH を転送する手元のポート(2222)
#   AGENT_HOST_VM_RDP_PORT_OFFSET  VM の RDP(3389〜3392)を転送する手元のポートのずれ(10000 で 13389〜13392)。
#                             ほかの利用者と共有するホストでは、ポートを取り合わないよう人ごとに変える
#   VBOXMANAGE                VBoxManage のパス(PATH に無ければ Windows の既定の場所)
set -euo pipefail
# shellcheck source=envs.sh
. "$(dirname "$0")/envs.sh"

[ $# -ge 1 ] || { echo "試験用の env.yaml を指定する" >&2; exit 2; }
envs=("$@")
name="${AGENT_HOST_VM_NAME:-agent-host-vm}"
key="$(resolve_path "${AGENT_HOST_VM_SSH_KEY:-build/test/id_ed25519}")"
memory="${AGENT_HOST_VM_MEMORY:-4096}"
timeout_min="${AGENT_HOST_VM_TIMEOUT:-120}"
ssh_port="${AGENT_HOST_VM_SSH_PORT:-2222}"
# 利用者の RDP のポート 3389〜3392 を、手元の PC の 13389〜13392 に転送する(verify-rdp はポートにずれを足す)
rdp_ports=(3389 3390 3391 3392)
export AGENT_HOST_RDP_PORT_OFFSET="${AGENT_HOST_VM_RDP_PORT_OFFSET:-10000}"
[ -f "$key" ] || { echo "$key がない(AGENT_HOST_VM_SSH_KEY で指定する)" >&2; exit 1; }

backend="${AGENT_HOST_VM_BACKEND:-}"
vbm="${VBOXMANAGE:-$(command -v VBoxManage || echo "/c/Program Files/Oracle/VirtualBox/VBoxManage.exe")}"
if [ -z "$backend" ]; then
    if [ -x "$vbm" ]; then
        backend=virtualbox
    elif command -v qemu-system-x86_64 >/dev/null && [ -e /dev/kvm ]; then
        backend=qemu
    else
        echo "VM の道具がない。VirtualBox を入れるか、エージェントのホストなら env.yaml の vm を true にして" \
            "just update する(QEMU/KVM。docs/release.md)" >&2
        exit 1
    fi
fi
case "$backend" in
virtualbox)
    [ -x "$vbm" ] || { echo "VBoxManage がない(VBOXMANAGE で場所を指定する)" >&2; exit 1; }
    cpus="${AGENT_HOST_VM_CPUS:-1}"
    ;;
qemu)
    command -v qemu-system-x86_64 >/dev/null || { echo "qemu-system-x86_64 がない(env.yaml の vm)" >&2; exit 1; }
    if [ ! -r /dev/kvm ] || [ ! -w /dev/kvm ]; then
        # kvm に入れたあと、まだ新しいログインをしていない。グループが効いていればそれで実行しなおす
        if [ -z "${AGENT_HOST_VM_SG:-}" ] && getent group kvm | cut -d: -f4 | tr , '\n' | grep -qx "$(id -un)"; then
            echo "kvm のグループが今のセッションに効いていないので、sg kvm で実行しなおす" >&2
            exec env AGENT_HOST_VM_SG=1 sg kvm -c "$(printf '%q ' "$0" "$@")"
        fi
        echo "/dev/kvm を読み書きできない(kvm のグループに入っていない。env.yaml の vm)" >&2
        exit 1
    fi
    ovmf_code=/usr/share/OVMF/OVMF_CODE_4M.fd
    ovmf_vars=/usr/share/OVMF/OVMF_VARS_4M.fd
    [ -f "$ovmf_code" ] && [ -f "$ovmf_vars" ] || { echo "$ovmf_code がない(ovmf-generic)" >&2; exit 1; }
    cpus="${AGENT_HOST_VM_CPUS:-2}"
    ;;
*)
    echo "AGENT_HOST_VM_BACKEND は virtualbox か qemu にする" >&2
    exit 2
    ;;
esac
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

# shellcheck disable=SC2029  # コマンドは手元で組み立てて VM に渡す
vm_ssh() { ssh "${ssh_opts[@]}" sysadmin@127.0.0.1 "$@"; }
vm_sudo() { printf '%s\n' "$AGENT_HOST_SUDO_PASSWORD" | vm_ssh "sudo -S -p '' $*"; }

# --- VM の操作(道具ごと)。vm_reinstall: ディスクを空にして ISO から起動する、vm_poweroff: 電源を切る(強制)、
#     vm_start: ディスクから起動する、vm_running: 動いているか ---
# VBoxManage は Windows では Windows の形のパスを受け取る
winpath() { if command -v cygpath >/dev/null; then cygpath -w "$1"; else printf '%s\n' "$1"; fi; }
vbox_state() { "$vbm" showvminfo "$name" --machinereadable 2>/dev/null | sed -n 's/^VMState="\(.*\)"/\1/p'; }
vbox_running() { case "$(vbox_state)" in running | paused | stuck) return 0 ;; *) return 1 ;; esac; }
vbox_poweroff() { "$vbm" controlvm "$name" poweroff; }
vbox_start() { "$vbm" startvm "$name" --type headless; }
vbox_reinstall() {
    if ! "$vbm" showvminfo "$name" >/dev/null 2>&1; then
        "$vbm" createvm --name "$name" --ostype Ubuntu_64 --basefolder "$(winpath "$base")" --register
        "$vbm" modifyvm "$name" --firmware efi --memory "$memory" --cpus "$cpus" --vram 128 \
            --graphicscontroller vmsvga --nic1 nat --audio-enabled off --usb-ohci off \
            --boot1 disk --boot2 dvd --boot3 none --boot4 none
        "$vbm" storagectl "$name" --name SATA --add sata --controller IntelAhci --portcount 2
    else
        old_disk="$("$vbm" showvminfo "$name" --machinereadable | sed -n 's/^"SATA-0-0"="\(.*\)"/\1/p')"
        if [ -n "$old_disk" ] && [ "$old_disk" != none ]; then
            "$vbm" storageattach "$name" --storagectl SATA --port 0 --device 0 --medium none
            "$vbm" closemedium disk "$old_disk" --delete
        fi
    fi
    # 転送をそろえる。名前が ssh か rdp で始まる転送(0.2 までの 3389 の 1 本や、手で足したもの)を消してから足す
    while read -r rule; do
        "$vbm" modifyvm "$name" --natpf1 delete "$rule"
    done < <("$vbm" showvminfo "$name" --machinereadable | sed -n 's/^Forwarding([0-9]*)="\(\(ssh\|rdp\)[^,]*\),.*/\1/p')
    "$vbm" modifyvm "$name" --natpf1 "ssh,tcp,127.0.0.1,$ssh_port,,22"
    for p in "${rdp_ports[@]}"; do
        "$vbm" modifyvm "$name" --natpf1 "rdp$p,tcp,127.0.0.1,$((p + AGENT_HOST_RDP_PORT_OFFSET)),,$p"
    done
    disk="$base/$name/$name-$(date +%Y%m%d-%H%M%S).vdi"
    mkdir -p "$(dirname "$disk")"
    "$vbm" createmedium disk --filename "$(winpath "$disk")" --size 40960 --format VDI
    "$vbm" storageattach "$name" --storagectl SATA --port 0 --device 0 --type hdd --medium "$(winpath "$disk")"
    "$vbm" storageattach "$name" --storagectl SATA --port 1 --device 0 --type dvddrive --medium "$(winpath "$iso")"
    vbox_start
}
# QEMU: build/vm/<名前>/ にディスク(qcow2)、UEFI の変数(OVMF_VARS の写し)、pid、シリアルのログを置く。
# -daemonize のあとは作業ディレクトリが変わりうるので、パスは絶対にする
qdir="$PWD/$base/$name"
qemu_pid() { cat "$qdir/qemu.pid" 2>/dev/null || true; }
qemu_running() {
    local pid
    pid="$(qemu_pid)"
    [ -n "$pid" ] && [ -d "/proc/$pid" ] && [[ "$(cat "/proc/$pid/comm" 2>/dev/null)" == qemu* ]]
}
qemu_poweroff() {
    local pid
    pid="$(qemu_pid)"
    qemu_running || return 0
    kill -KILL "$pid"
    for _ in $(seq 30); do qemu_running || return 0; sleep 1; done
    echo "QEMU(PID $pid)が止まらない" >&2
    return 1
}
# qemu_start [<ISO>]: ディスクを先に、ISO を後に起動の順に入れる(VirtualBox の boot1 disk・boot2 dvd と同じ)。
# 空のディスクからは起動できないので ISO から入り、入れたあとはディスクから起動する
qemu_start() {
    local fwd="" p
    for p in "${rdp_ports[@]}"; do fwd+=",hostfwd=tcp:127.0.0.1:$((p + AGENT_HOST_RDP_PORT_OFFSET))-:$p"; done
    local args=(
        -name "$name" -enable-kvm -machine q35 -cpu host -smp "$cpus" -m "$memory"
        -drive "if=pflash,format=raw,readonly=on,file=$ovmf_code"
        -drive "if=pflash,format=raw,file=$qdir/OVMF_VARS.fd"
        -device "virtio-blk-pci,drive=disk,bootindex=1" -drive "if=none,id=disk,format=qcow2,file=$qdir/disk.qcow2"
        -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:$ssh_port-:22$fwd" -device "virtio-net-pci,netdev=net0"
        -device virtio-rng-pci
        -display none -serial "file:$qdir/serial.log" -daemonize -pidfile "$qdir/qemu.pid"
    )
    if [ -n "${1:-}" ]; then
        args+=(-device "ide-cd,drive=cd,bootindex=2" -drive "if=none,id=cd,media=cdrom,readonly=on,file=$1")
    fi
    qemu-system-x86_64 "${args[@]}"
}
qemu_reinstall() {
    mkdir -p "$qdir"
    rm -f "$qdir/disk.qcow2" "$qdir/OVMF_VARS.fd"
    qemu-img create -q -f qcow2 "$qdir/disk.qcow2" 40G
    cp "$ovmf_vars" "$qdir/OVMF_VARS.fd"
    qemu_start "$PWD/$iso"
}
case "$backend" in
virtualbox) vm_running() { vbox_running; }; vm_poweroff() { vbox_poweroff; }; vm_start() { vbox_start; }; vm_reinstall() { vbox_reinstall; } ;;
qemu) vm_running() { qemu_running; }; vm_poweroff() { qemu_poweroff; }; vm_start() { qemu_start; }; vm_reinstall() { qemu_reinstall; } ;;
esac
# ports_free: 転送する手元のポートが空いているか(ほかの利用者の VM などと取り合わない)
ports_free() {
    local p busy=""
    for p in "$ssh_port" $(for q in "${rdp_ports[@]}"; do echo $((q + AGENT_HOST_RDP_PORT_OFFSET)); done); do
        if timeout 2 bash -c "</dev/tcp/127.0.0.1/$p" 2>/dev/null; then busy+="$p "; fi
    done
    [ -z "$busy" ] && return 0
    echo "手元のポート ${busy% } が使われている(AGENT_HOST_VM_SSH_PORT・AGENT_HOST_VM_RDP_PORT_OFFSET で変える)" >&2
    return 1
}

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
        vm_running || { echo "VM が止まった" >&2; return 1; }
        # shellcheck disable=SC2016  # VM の中で展開する
        boot="$(vm_ssh 'test -f /var/lib/agent-host/provisioned &&
            n="$(getent group agent-host-users | cut -d: -f4 | tr , "\n" | grep -c .)" &&
            [ "$n" -gt 0 ] && open=0 && for p in 3389 3390 3391 3392; do { timeout 2 bash -c "</dev/tcp/127.0.0.1/$p" 2>/dev/null && open=$((open + 1)); } || true; done &&
            [ "$open" -ge "$n" ] &&
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

if [ "${AGENT_HOST_VM_REUSE:-}" != 1 ]; then
    step "1. ISO を作る(${envs[*]})"
    scripts/local/iso.sh build "build/ubuntu-26.04.1-desktop-amd64.iso" "$iso" "${envs[@]}"

    step "1. VM($name、$backend)のディスクを作りなおし、ISO から起動する"
    if vm_running; then
        vm_poweroff
        sleep 5
    fi
    ports_free
    vm_reinstall
fi

step "2. インストールと構成を待つ(最大 $timeout_min 分)"
if [ "${AGENT_HOST_VM_REUSE:-}" = 1 ]; then
    record - "入れなおしは飛ばした(AGENT_HOST_VM_REUSE=1。無人で最後まで通ったことにはならない)"
    check_all "今の VM"
elif wait_ready "$timeout_min"; then
    record ✓ "インストールから RDP の待ち受けまで(人手なし)"
    check_all "入れた直後"
else
    record ✗ "インストールから RDP の待ち受けまで(人手なし)"
    summary || true
    exit 1
fi

step "3. 電源を切って(強制)起動しなおす"
boot="$(vm_ssh cat /proc/sys/kernel/random/boot_id)"
vm_poweroff
sleep 5
vm_start
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
