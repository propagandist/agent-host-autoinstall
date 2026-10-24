#!/usr/bin/env bash
# Ubuntu Desktop 26.04 の ISO に、env.yaml を埋めた autoinstall.yaml と同梱スクリプトを入れた ISO を作る。
# できた ISO を USB メモリに書き込む(Rufus なら「DD イメージ」モード、Linux なら dd)。
#
# 使い方: scripts/build-usb.sh <元のISO> <出力ISO> [env.yaml]
# 必要なもの(Linux / WSL): xorriso, python3, python3-yaml
#
# 出力 ISO には env.yaml の秘密情報(パスワードハッシュ、RDP パスワード)が入る。扱いに注意する。
set -euo pipefail

usage() { echo "使い方: $0 <元のISO> <出力ISO> [env.yaml]" >&2; exit 2; }
[ $# -ge 2 ] || usage

repo="$(cd "$(dirname "$0")/.." && pwd)"
src_iso="$1"
out_iso="$2"
env_yaml="${3:-$repo/autoinstall/env.yaml}"

for cmd in xorriso python3; do
    command -v "$cmd" >/dev/null || { echo "$cmd がない(apt install xorriso python3-yaml)" >&2; exit 1; }
done
[ -f "$src_iso" ] || { echo "元のISO $src_iso がない" >&2; exit 1; }
[ -f "$env_yaml" ] || { echo "$env_yaml がない(env.example.yaml をコピーして作る)" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
stage="$work/agent-host"
mkdir -p "$stage"

# 1. autoinstall.yaml と env.sh を生成する
python3 "$repo/scripts/render-autoinstall.py" \
    "$repo/autoinstall/autoinstall.yaml" "$env_yaml" "$work/render"
cp "$work/render/env.sh" "$work/render/agent_authorized_keys" "$stage/"
cp -a "$work/render/ca" "$stage/ca"

# 2. ターゲットの /opt/agent-host に置くスクリプトをそろえる
cp -a "$repo/scripts/provision.sh" "$repo/scripts/setup-provision.sh" \
    "$repo/scripts/lib" "$repo/scripts/post-install" "$repo/scripts/first-login" \
    "$repo/scripts/systemd" "$repo/scripts/notify" "$repo/scripts/migrate" "$repo/scripts/watchdog" "$stage/"
find "$stage" -name '*.sh' -exec chmod 755 {} +
chmod 600 "$stage/env.sh"

# 3. grub.cfg の linux 行に autoinstall を足す(確認画面を出さないため)
# 26.04.1 Desktop ISO の grub.cfg は「linux /casper/vmlinuz ... --- quiet splash」の形(確認済み)
xorriso -osirrox on -indev "$src_iso" -extract /boot/grub/grub.cfg "$work/grub.cfg" >/dev/null 2>&1
chmod u+w "$work/grub.cfg"
if ! grep -Eq '^\s*linux\s.*\sautoinstall(\s|$)' "$work/grub.cfg"; then
    sed -E -i '/^\s*linux\s/ s/ ---/ autoinstall ---/' "$work/grub.cfg"
fi
grep -Eq '^\s*linux\s.*\sautoinstall(\s|$)' "$work/grub.cfg" || {
    echo "grub.cfg に autoinstall を足せなかった(linux 行の形式が想定と違う)" >&2; exit 1; }

# 4. 元の ISO のブート構成を保ったまま、ファイルを足して書き出す
rm -f "$out_iso"
xorriso -indev "$src_iso" -outdev "$out_iso" \
    -map "$work/render/autoinstall.yaml" /autoinstall.yaml \
    -map "$stage" /agent-host \
    -map "$work/grub.cfg" /boot/grub/grub.cfg \
    -boot_image any replay

echo "作成した: $out_iso"
