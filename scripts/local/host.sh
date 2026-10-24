#!/usr/bin/env bash
# 手元の PC から、動いているホストを扱う(just のレシピから使う)。
#
# 使い方: scripts/local/host.sh <操作> <ホスト> [引数]
#   status  <ホスト>                 構成・RDP・セッション・ディスク・メモリ・失敗した unit を見る
#   logs    <ホスト>                 構成・first-login・見張りの記録を見る(sudo のパスワードを聞かれる)
#   update  <ホスト> <env.yaml>      スクリプトと env.yaml の変更を反映して構成を再実行する(OS は入れなおさない)
#   backup  <ホスト> [出力ファイル]  移行の書き出し(既定は build/backups/<ホスト>-<日時>.tar.zst)
#   restore <ホスト> <ファイル>      移行の取り込み
# SSH に足すオプションは環境変数 AGENT_HOST_SSH_OPTS(例: 試験用の VM なら "-p 2222 -i build/test/id_ed25519")
set -euo pipefail

usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
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
        if [ -f /var/lib/agent-host/provisioned ]; then echo "構成: 済み"
        else echo "構成: 未完了(サービスは $(systemctl is-active agent-host-provision.service))"; fi
        echo "RDP: $(ss -tln | grep -q ":3389 " && echo "待ち受け中" || echo "止まっている")"
        loginctl list-sessions --no-legend | awk '\''$3 == "agent" && $6 == "user" {print "agent のセッション: " $4 " " $7}'\''
        df -h / | awk '\''NR == 2 {print "ディスク: " $3 " / " $2 "(" $5 ")"}'\''
        free -h | awk '\''NR == 2 {print "メモリ: 使用 " $3 " / " $2}'\''
        echo "失敗した unit:"; systemctl --failed --no-legend --no-pager | sed "s/^/  /"
    '
    ;;
logs)
    ssh -t "${ssh_opts[@]}" "$target" '
        sudo journalctl -u agent-host-provision.service -o cat --no-pager | grep -E "^\[agent-host\]|注意|^(E|W):" | tail -40
        echo "--- first-login"; sudo tail -15 /home/agent/.local/state/agent-host/first-login.log
        echo "--- セッションの見張り"; sudo journalctl -u agent-host-session-watchdog.service -o cat --no-pager | grep "^\[agent-host\]" | tail -5
    '
    ;;
update)
    env_yaml="${1:?env.yaml を指定する}"
    # 別のホストの env.yaml を流さないよう、ホスト名を確かめる
    want="$(sed -n 's/^hostname:[[:space:]]*"\{0,1\}\([^" ]*\)"\{0,1\}.*/\1/p' "$env_yaml")"
    have="$(ssh "${ssh_opts[@]}" "$target" hostname)"
    [ "$want" = "$have" ] || { echo "env.yaml のホスト名($want)と、つないだホスト($have)が違う" >&2; exit 1; }
    tmp="build/.update-$host"
    rm -rf "$tmp"
    mkdir -p "$tmp"
    trap 'rm -rf "$tmp"' EXIT
    scripts/local/in-ubuntu.sh python3-yaml python3 bash scripts/stage.sh "$env_yaml" "$tmp"
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
    out="${1:-build/backups/$host-$(date +%Y%m%d-%H%M).tar.zst}"
    mkdir -p "$(dirname "$out")"
    ask_password
    (umask 077; printf '%s\n' "$PW" | ssh "${ssh_opts[@]}" "$target" 'sudo -S -p "" agent-host-backup' >"$out")
    unset PW
    echo "書き出した: $out(ログインの情報が入る。暗号化された場所に移し、取り込んだら消す)" >&2
    ;;
restore)
    file="${1:?取り込むファイルを指定する}"
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
