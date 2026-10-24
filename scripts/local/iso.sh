#!/usr/bin/env bash
# 手元の PC で env.yaml を検査し、インストール用の ISO を作る(just check-env / just iso が使う)。
# リポジトリの直下で実行する。env.yaml は複数渡せる(前から順に重ね、後のファイルの値が勝つ)。
#
# 使い方: scripts/local/iso.sh check <env.yaml>...
#         scripts/local/iso.sh build <元の ISO> <出力 ISO> <env.yaml>...
# 構成リポジトリから使うときは、AGENT_HOST_CONFIG_REV に構成の版を入れると BUILD-INFO に残る(docs/fleet.md)
set -euo pipefail
# shellcheck source=envs.sh
. "$(dirname "$0")/envs.sh"

op="${1:-}"
shift || true
case "$op" in
check)
    copy_envs "$@"
    rm -rf build/.check-env
    scripts/local/in-ubuntu.sh python3-yaml python3 python3 scripts/render-autoinstall.py \
        autoinstall/autoinstall.yaml "${ENV_FILES[@]}" build/.check-env
    rm -rf build/.check-env
    echo "$* は問題ない"
    ;;
build)
    [ $# -ge 3 ] || { echo "使い方: $0 build <元の ISO> <出力 ISO> <env.yaml>..." >&2; exit 2; }
    src_iso="$1"
    out_iso="$(resolve_path "$2")"
    shift 2
    copy_envs "$@"
    write_build_info "$@"
    # Docker の中から書けるのはこのリポジトリの中だけなので、build/ に作ってから移す
    tmp_iso=build/.agent-host.iso
    scripts/local/in-ubuntu.sh "xorriso python3-yaml" "xorriso python3" \
        bash scripts/build-usb.sh --build-info build/.env/BUILD-INFO "$src_iso" "$tmp_iso" "${ENV_FILES[@]}" >/dev/null
    mkdir -p "$(dirname "$out_iso")"
    mv -f "$tmp_iso" "$out_iso"
    echo "作成した: $out_iso(秘密情報が入る。USB に書き込んだら消す)"
    sed 's/^/  /' build/.env/BUILD-INFO
    ;;
*)
    sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 2
    ;;
esac
