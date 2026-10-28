#!/usr/bin/env bash
# env.yaml の vm を選んだら、VM を動かす道具(QEMU/KVM と UEFI のファームウェア)を入れ、利用者全員を kvm に入れる。
# エージェントがこのホストで just vm-test(scripts/local/vm-test.sh の QEMU の版)を回すため。
# 選ばなくなったら、利用者を kvm から外す(入れた道具は消さない)。env.yaml から外した利用者も外す。
# kvm のグループは次のログインから効く。動いているセッションでは `sg kvm -c '...'` で使える。
set -euo pipefail
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"
load_env

in_kvm() { id -nG "$1" 2>/dev/null | tr ' ' '\n' | grep -qx kvm; }
drop_kvm() {
    if in_kvm "$1"; then
        gpasswd -d "$1" kvm >/dev/null
        log "$1 を kvm から外した"
    fi
}

if [ "${AH_VM:-0}" = 1 ]; then
    # 版は固定しない(ほかの Ubuntu の apt の道具と同じ。unattended-upgrades で更新する)。画面を出さないので、
    # 推奨(GUI・SPICE など)は入れない。26.04 の ovmf は ovmf-generic などをまとめた移行用のパッケージなので、
    # UEFI のファームウェア(/usr/share/OVMF/OVMF_CODE_4M.fd・OVMF_VARS_4M.fd)は ovmf-generic で入れる
    apt-get install -y --no-install-recommends qemu-system-x86 qemu-utils ovmf-generic
    add_kvm() {
        if ! in_kvm "$AGENT_USER"; then
            usermod -a -G kvm "$AGENT_USER"
            log "$AGENT_USER を kvm に入れた(次のログインから効く。それまでは sg kvm -c '...')"
        fi
    }
    for_each_user add_kvm
else
    for u in $AH_USERS; do drop_kvm "$u"; done
fi

# env.yaml から外した利用者
for u in $(getent group "$AH_USERS_GROUP" | cut -d: -f4 | tr ',' ' '); do
    case " $AH_USERS " in *" $u "*) continue ;; esac
    drop_kvm "$u"
done
