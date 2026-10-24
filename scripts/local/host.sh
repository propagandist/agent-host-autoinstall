#!/usr/bin/env bash
# 手元の PC から、動いているホストを扱う(just のレシピから使う)。
#
# 使い方: scripts/local/host.sh <操作> <ホスト> [引数]
#   status  <ホスト>                 作った版・構成・RDP・セッション・ディスク・メモリ・失敗した unit を見る
#   facts   <ホスト>                 台帳のための情報を YAML で出す(sudo のパスワードを聞かれる)
#   logs    <ホスト>                 構成・first-login・見張りの記録を見る(sudo のパスワードを聞かれる)
#   verify  <ホスト>                 仕様どおりに構成されているかを確かめる(scripts/verify.sh。何も変えない)
#   verify-rdp <ホスト>[:ポート] <env.yaml>...  env.yaml の rdp で RDP の認証が通るかを確かめる(FreeRDP)
#   update  <ホスト> <env.yaml>...   スクリプトと env.yaml の変更を反映して構成を再実行する(OS は入れなおさない)
#   backup  <ホスト> [出力ファイル]  移行の書き出し(既定は build/backups/<ホスト>-<日時>.tar.zst)
#   restore <ホスト> <ファイル>      移行の取り込み
# SSH に足すオプションは環境変数 AGENT_HOST_SSH_OPTS(例: 試験用の VM なら "-p 2222 -i build/test/id_ed25519")
set -euo pipefail
# shellcheck source=envs.sh
. "$(dirname "$0")/envs.sh"

usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
[ $# -ge 2 ] || usage
op="$1"
host="$2"
shift 2
# shellcheck disable=SC2206  # オプションは空白で分けて渡す
ssh_opts=(${AGENT_HOST_SSH_OPTS:-})
target="sysadmin@$host"

# sudo のパスワードを 1 回だけ聞く(標準入力を受け渡しに使う操作では、先頭の 1 行で sudo -S に渡す)。
# 端末がない自動化や試験のときだけ、環境変数 AGENT_HOST_SUDO_PASSWORD を使える(履歴に残さないこと)
ask_password() {
    if [ -n "${AGENT_HOST_SUDO_PASSWORD:-}" ]; then
        PW="$AGENT_HOST_SUDO_PASSWORD"
        return
    fi
    read -rsp "$target の sudo のパスワード: " PW </dev/tty
    echo >&2
}

case "$op" in
status)
    ssh "${ssh_opts[@]}" "$target" '
        if [ -f /opt/agent-host/BUILD-INFO ]; then
            . /opt/agent-host/BUILD-INFO
            echo "作った版: 道具 $tool${config:+、構成 $config}($built)"
        else echo "作った版: 記録なし(BUILD-INFO を置く前の版で作った)"; fi
        if [ -f /var/lib/agent-host/provisioned ]; then echo "構成: 済み"
        else echo "構成: 未完了(サービスは $(systemctl is-active agent-host-provision.service))"; fi
        echo "RDP: $(ss -tln | grep -q ":3389 " && echo "待ち受け中" || echo "止まっている")"
        loginctl list-sessions --no-legend | awk '\''$3 == "agent" && $6 == "user" {print "agent のセッション: " $4 " " $7}'\''
        df -h / | awk '\''NR == 2 {print "ディスク: " $3 " / " $2 "(" $5 ")"}'\''
        free -h | awk '\''NR == 2 {print "メモリ: 使用 " $3 " / " $2}'\''
        echo "失敗した unit:"; systemctl --failed --no-legend --no-pager | sed "s/^/  /"
    '
    ;;
facts)
    # 台帳(構成リポジトリの docs/inventory.md など)に写すための情報。秘密情報は出さない
    ask_password
    # 標準入力の先頭の 1 行は sudo のパスワード、残りは bash に渡すスクリプト
    {
        printf '%s\n' "$PW"
        cat <<'EOF'
set -u
dmi() { cat "/sys/class/dmi/id/$1" 2>/dev/null | tr -d '\n' || true; }
q() { printf '"%s"' "$(printf '%s' "$1" | sed 's/["\\]/\\&/g')"; }
echo "hostname: $(q "$(hostname)")"
if [ -f /opt/agent-host/BUILD-INFO ]; then
    . /opt/agent-host/BUILD-INFO
    echo "build:"
    echo "  tool: $(q "$tool")"
    echo "  config: $(q "$config")"
    echo "  env: $(q "$env")"
    echo "  built: $(q "$built")"
fi
echo "machine:"
echo "  vendor: $(q "$(dmi sys_vendor)")"
echo "  product: $(q "$(dmi product_name)")"
echo "  serial: $(q "$(dmi product_serial)")"
echo "  bios: $(q "$(dmi bios_version) ($(dmi bios_date))")"
echo "  cpu: $(q "$(sed -n 's/^model name[[:space:]]*: //p' /proc/cpuinfo | head -1)($(nproc) スレッド)")"
echo "  memory: $(q "$(free -h | awk 'NR==2 {print $2}')")"
echo "disks:"
lsblk -dno NAME,SIZE,MODEL -e 7,11 | while read -r name size model; do
    case "$name" in zram*) continue ;; esac  # メモリ上のスワップ
    echo "  - $(q "$name $size ${model:-}")"
done
echo "network:"
for dev in $(ls /sys/class/net); do
    [ "$dev" = lo ] && continue
    mac="$(cat "/sys/class/net/$dev/address")"
    ips="$(ip -4 -o addr show dev "$dev" | awk '{printf "%s ", $4}')"
    echo "  - $(q "$dev $mac ${ips% }")"
done
. /etc/os-release
echo "os: $(q "$PRETTY_NAME (kernel $(uname -r))")"
echo "ssh_host_key: $(q "$(ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub | awk '{print $2}')")"
crt=/home/agent/.local/share/gnome-remote-desktop/tls.crt
if [ -f "$crt" ]; then
    echo "rdp_cert: $(q "$(openssl x509 -in "$crt" -noout -fingerprint -sha256 | cut -d= -f2)")"
fi
EOF
    } | ssh "${ssh_opts[@]}" "$target" 'sudo -S -p "" bash -s'
    unset PW
    ;;
verify)
    # 手元の scripts/verify.sh を流す(ホストに置いた版が古くても、今の検査で確かめる)。固定の版はホストの post-install/ と比べる
    ask_password
    { printf '%s\n' "$PW"; cat "$(dirname "$0")/../verify.sh"; } | ssh "${ssh_opts[@]}" "$target" 'sudo -S -p "" bash -s'
    unset PW
    ;;
verify-rdp)
    # host は <ホスト> か <ホスト>:<ポート>(試験用の VM はポートを転送している)
    [ $# -ge 1 ] || { echo "env.yaml を指定する(RDP の認証情報を読む)" >&2; exit 2; }
    port=3389
    case "$host" in *:*) port="${host##*:}"; host="${host%:*}" ;; esac
    copy_envs "$@"
    scripts/local/in-ubuntu.sh "freerdp3-x11 python3-yaml" "xfreerdp3 python3" \
        bash scripts/local/rdp-auth.sh "$host" "$port" "${ENV_FILES[@]}"
    ;;
logs)
    ssh -t "${ssh_opts[@]}" "$target" '
        sudo journalctl -u agent-host-provision.service -o cat --no-pager | grep -E "^\[agent-host\]|注意|^(E|W):" | tail -40
        echo "--- first-login"; sudo tail -15 /home/agent/.local/state/agent-host/first-login.log
        echo "--- セッションの見張り"; sudo journalctl -u agent-host-session-watchdog.service -o cat --no-pager | grep "^\[agent-host\]" | tail -5
    '
    ;;
update)
    [ $# -ge 1 ] || { echo "env.yaml を指定する" >&2; exit 2; }
    copy_envs "$@"
    write_build_info "$@"
    tmp="build/.update-$host"
    rm -rf "$tmp"
    mkdir -p "$tmp"
    trap 'rm -rf "$tmp" build/.env' EXIT
    scripts/local/in-ubuntu.sh python3-yaml python3 \
        bash scripts/stage.sh --build-info build/.env/BUILD-INFO "${ENV_FILES[@]}" "$tmp" >/dev/null
    # 別のホストの env.yaml を流さないよう、重ねた結果のホスト名を確かめる
    want="$(sed -n "s/^AH_HOSTNAME=//p" "$tmp/agent-host/env.sh" | tr -d "'")"
    have="$(ssh "${ssh_opts[@]}" "$target" hostname)"
    [ "$want" = "$have" ] || { echo "env.yaml のホスト名($want)と、つないだホスト($have)が違う" >&2; exit 1; }
    ask_password
    # 今の /opt/agent-host は /opt/agent-host.prev に残す(戻すときに使う)
    { printf '%s\n' "$PW"; tar -C "$tmp" -czf - agent-host; } |
        ssh "${ssh_opts[@]}" "$target" 'sudo -S -p "" bash -c "
            set -euo pipefail
            t=\$(mktemp -d); tar -xzf - -C \$t
            rm -rf /opt/agent-host.prev; mv /opt/agent-host /opt/agent-host.prev; mv \$t/agent-host /opt/agent-host
            chown -R root:root /opt/agent-host; chmod -R u=rwX,go=rX /opt/agent-host
            chmod 600 /opt/agent-host/env.sh /opt/agent-host/agent_authorized_keys
            DEBIAN_FRONTEND=noninteractive /opt/agent-host/provision.sh 2>&1 | grep -E \"^\[agent-host\]|注意|^(E|W):\"
        "'
    unset PW
    ;;
backup)
    out="$(resolve_path "${1:-build/backups/$host-$(date +%Y%m%d-%H%M).tar.zst}")"
    mkdir -p "$(dirname "$out")"
    ask_password
    (umask 077; printf '%s\n' "$PW" | ssh "${ssh_opts[@]}" "$target" 'sudo -S -p "" agent-host-backup' >"$out")
    unset PW
    echo "書き出した: $out(ログインの情報が入る。暗号化された場所に移し、取り込んだら消す)" >&2
    ;;
restore)
    file="$(resolve_path "${1:?取り込むファイルを指定する}")"
    [ -f "$file" ] || { echo "$file がない" >&2; exit 1; }
    ask_password
    { printf '%s\n' "$PW"; cat "$file"; } | ssh "${ssh_opts[@]}" "$target" 'sudo -S -p "" agent-host-restore'
    unset PW
    echo "再起動して反映する: ssh -t $target sudo systemctl reboot" >&2
    ;;
*)
    usage
    ;;
esac
