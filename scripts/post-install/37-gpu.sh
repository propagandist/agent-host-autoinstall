#!/usr/bin/env bash
# GPU に RDP の画面の符号化を任せる(パフォーマンスを優先する)。
# gnome-remote-desktop 50 は、GPU があれば Vulkan で色を変換し、VA-API で H.264 を作る(設定は要らない。ソースで確認)。
# NVIDIA は CUDA と NVENC を使う(プロプライエタリ ドライバーが要る。autoinstall の drivers でインストールの中で入る)。
#   Intel: VA-API の full 版(intel-media-va-driver-non-free、multiverse)。free 版は Broadwell で H.264 を符号化できず、
#          Skylake〜Ice Lake では低電力の符号化(HuC のファームウェアが要る)だけになる(Intel の media-driver の README)
#   AMD:   Mesa の radeonsi(mesa-libgallium)。Desktop に最初から入っている
#   Vulkan: Mesa の mesa-vulkan-drivers(Intel・AMD)
# GPU がない機種(VM など)では、入れても使われないだけ。
# 実機で GPU による符号化が効くかは未確認(just verify の「GPU」で確かめる)
set -euo pipefail
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"

# --- Intel の VA-API(full 版) ---
if LC_ALL=C apt-cache policy intel-media-va-driver-non-free | grep -q "Candidate: [0-9]"; then
    apt-get install -y intel-media-va-driver-non-free
    log "Intel の VA-API の full 版を入れた"
else
    # Desktop の既定の apt の設定には multiverse が入っている。外したときは free 版にする
    apt-get install -y intel-media-va-driver
    log "注意: intel-media-va-driver-non-free が見つからない(multiverse が無効)。free 版を入れた"
fi

# --- Vulkan のドライバーと、確かめる道具(vainfo。just verify が使う) ---
apt-get install -y mesa-vulkan-drivers vainfo

# --- NVIDIA ---
# 新しく入れたホストは autoinstall の drivers で入る。それより前に入れたホストや、あとから GPU を挿したときは手で入れる
nvidia_gpu=no
for dev in /sys/bus/pci/devices/*; do
    if [ "$(cat "$dev/vendor")" = 0x10de ] && [[ "$(cat "$dev/class")" == 0x03* ]]; then
        nvidia_gpu=yes
    fi
done
if [ "$nvidia_gpu" = yes ]; then
    if dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 'nvidia-driver-*' 2>/dev/null | grep -q '^ii'; then
        log "NVIDIA のドライバーが入っている"
    else
        log "注意: NVIDIA の GPU があるが、ドライバーが入っていない。sudo ubuntu-drivers install のあとに再起動する"
    fi
fi
