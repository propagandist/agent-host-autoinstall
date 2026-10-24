#!/usr/bin/env bash
# ホストが仕様どおりに構成されているかを、機械的に確かめる(読むだけで、何も変えない)。
# 固定した版は、このホストの /opt/agent-host/post-install/ に書いてある値と比べる(入れた版と、入れるはずの版が合っているか)。
# env.yaml の選択(editors・agents・clouds など)は /opt/agent-host/env.sh から読む。
#
# 使い方: sudo /opt/agent-host/verify.sh(手元からは just verify <ホスト>)
# 結果: 1 項目 1 行で ✓ か ✗。✗ が 1 つでもあれば終了コード 1
set -euo pipefail

AH_ROOT=/opt/agent-host
AGENT_USER=agent
AGENT_HOME=/home/agent
export LC_ALL=C.UTF-8

[ "$(id -u)" = 0 ] || { echo "root で実行する(sudo)" >&2; exit 2; }
[ -r "$AH_ROOT/env.sh" ] || { echo "$AH_ROOT/env.sh がない(このホストは agent-host-autoinstall で作られていない)" >&2; exit 2; }
# shellcheck source=/dev/null
. "$AH_ROOT/env.sh"

passed=0
failed=0
section() { printf '\n[%s]\n' "$1"; }
ok() { passed=$((passed + 1)); printf '  ✓ %s\n' "$1"; }
ng() { failed=$((failed + 1)); printf '  ✗ %s%s\n' "$1" "${2:+: $2}"; }
# check <説明> <コマンド...>: コマンドが成功すれば ✓
check() {
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then ok "$desc"; else ng "$desc"; fi
}
# eq <説明> <実際の値> <期待する値>
eq() {
    if [ "$2" = "$3" ]; then ok "$1"; else ng "$1" "「$2」(期待は「$3」)"; fi
}

# post-install/ に書いてある固定の版(NAME=値 の行)
pin() { sed -n "s/^$1=//p" "$AH_ROOT"/post-install/*.sh | head -1 | tr -d '"'; }
# post-install/ に書いてある並び(NAME=( ... ) の中。コメントは除く)
pin_list() {
    awk -v name="$1=(" 'index($0, name) == 1 {on = 1; sub(/^[^(]*\(/, "")}
        on {sub(/#.*/, ""); done = sub(/\).*/, ""); print; if (done) exit}' "$AH_ROOT"/post-install/*.sh |
        tr -s ' \t' '\n' | sed '/^$/d'
}
selected() { [[ " $1 " == *" $2 "* ]]; }
installed() { dpkg-query -W -f='${db:Status-Abbrev}' "$1" 2>/dev/null | grep -q '^ii'; }
dpkg_ver() { dpkg-query -W -f='${Version}' "$1" 2>/dev/null || true; }
holds="$(apt-mark showhold 2>/dev/null || true)"
held() { grep -qx "$1" <<<"$holds"; }
# パッケージが固定の版で入り、hold されている
pkg_pinned() {
    local pkg="$1" want="$2" have
    have="$(dpkg_ver "$pkg")"
    if [ "$have" != "$want" ]; then
        ng "$pkg $want" "入っているのは「${have:-なし}」"
    elif ! held "$pkg"; then
        ng "$pkg $want" "hold されていない"
    else
        ok "$pkg $want(hold)"
    fi
}
# コマンドの版の表示に、期待する文字列が入っている
cmd_ver() {
    local desc="$1" want="$2" have
    shift 2
    have="$("$@" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | head -1 || true)"
    if [[ "$have" == *"$want"* ]]; then ok "$desc $want"; else ng "$desc $want" "「$have」"; fi
}

agent_uid="$(id -u "$AGENT_USER" 2>/dev/null || echo 0)"
runtime_dir="/run/user/$agent_uid"
# agent のセッションの中で動かす(D-Bus を通して gsettings や grdctl を読む)
as_agent() {
    runuser -u "$AGENT_USER" -- env HOME="$AGENT_HOME" XDG_RUNTIME_DIR="$runtime_dir" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime_dir/bus" "$@"
}
gset() { as_agent gsettings get "$@" 2>/dev/null || true; }

section "構成"
check "構成が完了している(/var/lib/agent-host/provisioned)" test -f /var/lib/agent-host/provisioned
if [ -f "$AH_ROOT/BUILD-INFO" ]; then
    # shellcheck source=/dev/null
    tool="$(. "$AH_ROOT/BUILD-INFO" && echo "$tool")"
    ok "作った版の記録がある(道具 $tool)"
else
    ng "作った版の記録がある" "$AH_ROOT/BUILD-INFO がない"
fi
eq "ホスト名が env.yaml と同じ" "$(hostname)" "$AH_HOSTNAME"
failed_units="$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}' | tr '\n' ' ')"
eq "失敗した unit がない" "${failed_units% }" ""
check "dpkg のロックを待つ設定" grep -q 'DPkg::Lock::Timeout' /etc/apt/apt.conf.d/90-agent-host-lock-timeout

section "ユーザー"
check "agent がいる" id "$AGENT_USER"
if id -nG "$AGENT_USER" | tr ' ' '\n' | grep -qxE 'sudo|admin|docker'; then
    ng "agent は sudo・docker のグループに入っていない" "$(id -nG "$AGENT_USER")"
else
    ok "agent は sudo・docker のグループに入っていない"
fi
check "agent は sudo できない" bash -c "sudo -n -l -U $AGENT_USER 2>&1 | grep -q 'not allowed'"
eq "agent のホームは 700" "$(stat -c %a "$AGENT_HOME")" 700
admin_home="$(getent passwd sysadmin | cut -d: -f6)"
if [ -f "$AH_ROOT/sysadmin_authorized_keys" ]; then
    check "sysadmin の SSH の鍵が env.yaml と同じ" cmp -s "$AH_ROOT/sysadmin_authorized_keys" "$admin_home/.ssh/authorized_keys"
fi
if [ -n "${AH_SYSADMIN_PASSWORD_HASH:-}" ]; then
    check "sysadmin のパスワードが env.yaml と同じ" test "$(getent shadow sysadmin | cut -d: -f2)" = "$AH_SYSADMIN_PASSWORD_HASH"
fi

section "自動ログインとセッション"
check "GDM の自動ログインが agent" bash -c "grep -qx 'AutomaticLoginEnable=true' /etc/gdm3/custom.conf && grep -qx 'AutomaticLogin=$AGENT_USER' /etc/gdm3/custom.conf"
check "GDM に TimedLogin がない" bash -c "! grep -q '^TimedLogin' /etc/gdm3/custom.conf"
check "agent のグラフィカルなセッションがある" bash -c "loginctl list-sessions --no-legend | awk '\$3 == \"$AGENT_USER\" && \$4 == \"seat0\" && \$6 == \"user\"' | grep -q ."
check "セッションの見張りのタイマーが動いている" systemctl is-active agent-host-session-watchdog.timer
eq "スリープが mask されている" "$(systemctl is-enabled sleep.target suspend.target hibernate.target hybrid-sleep.target 2>/dev/null | sort -u | tr '\n' ' ')" "masked "
eq "画面のロックが無効" "$(gset org.gnome.desktop.screensaver lock-enabled)" false
eq "アイドルで画面を消さない" "$(gset org.gnome.desktop.session idle-delay)" "uint32 0"
check "空パスワードのログインキーリングがある" test -f "$AGENT_HOME/.local/share/keyrings/login.keyring"
check "first-login が済んでいる" test -f "$AGENT_HOME/.config/agent-host/first-login.done"
check "RDP の認証情報を入れる自動起動" test -f "$AGENT_HOME/.config/autostart/agent-host-rdp-credentials.desktop"
check "渡した RDP の認証情報がキーリングに入った(rdp.env が残っていない)" test ! -e "$AGENT_HOME/.config/agent-host/rdp.env"

section "RDP(GNOME のデスクトップ共有)"
grd="$(as_agent grdctl status 2>&1 || true)"
grd_field() { printf '%s\n' "$grd" | sed -n "s/^[[:space:]]*$1: *//p" | head -1; }
eq "gnome-remote-desktop が動いている" "$(grd_field 'Unit status')" active
eq "RDP が有効" "$(grd_field Status)" enabled
eq "RDP のポートが 3389" "$(grd_field Port)" 3389
eq "操作できる(閲覧だけではない)" "$(grd_field View-only)" no
eq "ポートを変えない" "$(grd_field 'Negotiate port')" no
eq "認証情報が設定されている" "$(grd_field Username)" "(hidden)"
check "TLS の証明書がある" test -f "$AGENT_HOME/.local/share/gnome-remote-desktop/tls.crt"
check "3389 を待ち受けている" bash -c "ss -tlnH | awk '{print \$4}' | grep -qE ':3389\$'"

section "SSH と ufw"
sshd_t="$(sshd -T 2>/dev/null || true)"
eq "SSH のパスワード認証なし" "$(printf '%s\n' "$sshd_t" | sed -n 's/^passwordauthentication //p')" no
eq "SSH の root ログインなし" "$(printf '%s\n' "$sshd_t" | sed -n 's/^permitrootlogin //p')" no
eq "SSH のキーボード対話の認証なし" "$(printf '%s\n' "$sshd_t" | sed -n 's/^kbdinteractiveauthentication //p')" no
check "agent は SFTP だけ" grep -q 'ForceCommand internal-sftp' /etc/ssh/sshd_config.d/10-agent-host.conf
check "22 を待ち受けている" bash -c "ss -tlnH | awk '{print \$4}' | grep -qE ':22\$'"
ufw_v="$(ufw status verbose 2>/dev/null || true)"
check "ufw が有効" grep -q '^Status: active' <<<"$ufw_v"
check "ufw の既定は受信を拒否" grep -q 'deny (incoming)' <<<"$ufw_v"
# 許可の規則の送信元が、すべて lan_cidrs のどれかであること(Anywhere を含まない)
bad_from=""
while read -r from; do
    selected "$AH_LAN_CIDRS" "$from" || bad_from+="$from "
done < <(ufw status 2>/dev/null | awk '$2 == "ALLOW" || $3 == "ALLOW" {print $NF}')
eq "ufw の許可は lan_cidrs からだけ" "${bad_from% }" ""

section "更新"
check "自動更新を有効にしている" grep -q 'Unattended-Upgrade "1"' /etc/apt/apt.conf.d/20auto-upgrades
check "自動更新はセキュリティ更新と Chrome だけ" test -f /etc/apt/apt.conf.d/52agent-host-unattended-upgrades

section "要らないものを止めた・消した"
check "snapd がない" bash -c "! dpkg-query -W -f='\${db:Status-Abbrev}' snapd 2>/dev/null | grep -q '^ii'"
check "snapd を入れない設定" test -f /etc/apt/preferences.d/agent-host-no-snapd.pref
check "スクリーンリーダー(orca)がない" test ! -e /usr/bin/orca
check "kdump-tools がない" bash -c "! dpkg-query -W -f='\${db:Status-Abbrev}' kdump-tools 2>/dev/null | grep -q '^ii'"
check "crashkernel を予約しない(GRUB の設定)" bash -c "! grep -q crashkernel= /boot/grub/grub.cfg"
check "起動画面(splash)を出さない(GRUB の設定)" bash -c "! grep -E '^[[:space:]]*linux[[:space:]]' /boot/grub/grub.cfg | grep -qw splash"
if grep -qE 'crashkernel=|(^| )splash( |$)' /proc/cmdline; then
    # 構成の前のカーネル引数で動いている(入れた直後の初回の起動など)。再起動すると GRUB の設定になる
    printf '  - 動いているカーネルの引数に crashkernel か splash が残っている(再起動で反映される)\n'
fi
for unit in cups.service avahi-daemon.service ModemManager.service bluetooth.service rsyslog.service syslog.socket \
    motd-news.timer fwupd-refresh.timer; do
    state="$(systemctl is-enabled "$unit" 2>/dev/null || true)"
    case "$state" in masked | "" | not-found) ok "$unit は止めている(${state:-なし})" ;; *) ng "$unit は止めている" "$state" ;; esac
done
check "zram のスワップがある" bash -c "swapon --show=NAME --noheadings | grep -q zram"
check "cloud-init を止めている" test -f /etc/cloud/cloud-init.disabled

section "システム"
check "時刻同期(chrony)が動いている" systemctl is-active chrony
eq "inotify の上限" "$(sysctl -n fs.inotify.max_user_watches)" 524288

section "開発の道具(版は post-install/ の固定の値)"
cmd_ver "Node.js" "v$(pin NODE_VERSION)" node --version
pkg_pinned claude-code "$(pin CLAUDE_CODE_VERSION)"
cmd_ver "Codex" "$(pin CODEX_VERSION)" codex --version
cmd_ver "CCManager" "$(pin CCMANAGER_VERSION)" ccmanager --version
pkg_pinned gh "$(pin GH_VERSION)"
cmd_ver "Gitea CLI(tea)" "$(pin TEA_VERSION)" tea --version
cmd_ver "uv" "$(pin UV_VERSION)" uv --version
cmd_ver "mise" "$(pin MISE_VERSION)" mise --version
pkg_pinned orca-ide "$(pin ORCA_VERSION)"
check "Orca の自動起動" test -f "$AGENT_HOME/.config/autostart/orca.desktop"
check "Google Chrome が入っている" installed google-chrome-stable
check "Chrome のポリシー" test -f /etc/opt/chrome/policies/managed/agent-host.json
check "既定のブラウザが Chrome" grep -q 'x-scheme-handler/https=google-chrome.desktop' "$AGENT_HOME/.config/mimeapps.list"
check "Xfce Terminal が入っている" installed xfce4-terminal
npm_ver() { node -p "require('$(npm root -g)/$1/package.json').version" 2>/dev/null || true; }
selected "${AH_AGENTS:-}" opencode && eq "OpenCode $(pin OPENCODE_VERSION)" "$(npm_ver opencode-ai)" "$(pin OPENCODE_VERSION)"
selected "${AH_AGENTS:-}" copilot && eq "GitHub Copilot CLI $(pin COPILOT_VERSION)" "$(npm_ver @github/copilot)" "$(pin COPILOT_VERSION)"
selected "${AH_AGENTS:-}" antigravity && check "Antigravity CLI $(pin ANTIGRAVITY_VERSION)" \
    bash -c "readlink -f /usr/local/bin/agy | grep -q '/opt/antigravity-$(pin ANTIGRAVITY_VERSION)/'"
selected "${AH_CLOUDS:-}" aws && cmd_ver "AWS CLI" "aws-cli/$(pin AWSCLI_VERSION) " aws --version
selected "${AH_CLOUDS:-}" gcp && pkg_pinned google-cloud-cli "$(pin GCLOUD_VERSION)"
selected "${AH_CLOUDS:-}" azure && pkg_pinned azure-cli "$(pin AZURE_CLI_VERSION)"

section "Docker(rootless)"
for pkg in docker-ce docker-ce-cli docker-ce-rootless-extras; do pkg_pinned "$pkg" "$(pin DOCKER_VERSION)"; done
pkg_pinned containerd.io "$(pin CONTAINERD_VERSION)"
pkg_pinned docker-buildx-plugin "$(pin BUILDX_VERSION)"
pkg_pinned docker-compose-plugin "$(pin COMPOSE_VERSION)"
eq "root の Docker は止めている" "$(systemctl is-active docker.service 2>/dev/null || true)" inactive
check "root の Docker のソケットがない" test ! -e /var/run/docker.sock
check "agent の Docker が動いている" as_agent systemctl --user is-active docker.service
check "agent の Docker の掃除のタイマー" as_agent systemctl --user is-active docker-prune.timer
dinfo="$(as_agent env DOCKER_HOST="unix://$runtime_dir/docker.sock" docker info --format '{{.SecurityOptions}}' 2>&1 || true)"
if [[ "$dinfo" == *rootless* ]]; then ok "agent の docker が rootless で応える"; else ng "agent の docker が rootless で応える" "$dinfo"; fi

section "GPU(RDP の画面の符号化)"
check "vainfo が入っている" installed vainfo
check "Vulkan のドライバー(mesa-vulkan-drivers)が入っている" installed mesa-vulkan-drivers
render="$(find /dev/dri -name 'renderD*' 2>/dev/null | sort | head -1)"
gpu_vendor=""
if [ -n "$render" ]; then
    gpu_vendor="$(cat "/sys/class/drm/${render##*/}/device/vendor" 2>/dev/null || true)"
fi
case "$gpu_vendor" in
0x8086 | 0x1002)
    # Intel か AMD: VA-API で H.264(High)を符号化できること
    if [ "$gpu_vendor" = 0x8086 ]; then
        check "Intel の VA-API の full 版" installed intel-media-va-driver-non-free
    fi
    if vainfo --display drm --device "$render" 2>/dev/null | grep -qE 'VAProfileH264High[[:space:]]*:[[:space:]]*VAEntrypointEncSlice'; then
        ok "GPU($gpu_vendor)で H.264 を符号化できる(vainfo)"
    else
        ng "GPU($gpu_vendor)で H.264 を符号化できる(vainfo)" "vainfo --display drm --device $render に VAEntrypointEncSlice がない"
    fi
    # RDP でつないだあとに、gnome-remote-desktop が VA-API を使い始めた記録が残る
    if journalctl -b "_UID=$agent_uid" -o cat --no-pager 2>/dev/null | grep -q 'HWAccel.VAAPI\] Successfully initialized'; then
        ok "RDP が GPU で符号化している(gnome-remote-desktop の記録)"
    else
        printf '  - RDP が GPU で符号化しているかは、RDP でつないだあとに確かめる(gnome-remote-desktop の記録がまだない)\n'
    fi
    ;;
0x10de)
    # NVIDIA: プロプライエタリ ドライバーと NVENC(gnome-remote-desktop は CUDA と NVENC を使う)
    check "NVIDIA のドライバーが動いている" test -d /sys/module/nvidia
    check "NVENC のライブラリがある" bash -c "ldconfig -p | grep -q libnvidia-encode.so"
    ;;
*)
    printf '  - GPU がない(VM など。vendor %s)ので、符号化の確認は対象外\n' "${gpu_vendor:-なし}"
    ;;
esac

section "日本語"
for pkg in ibus-mozc language-pack-ja language-pack-gnome-ja fonts-noto-cjk; do
    check "$pkg が入っている" installed "$pkg"
done
sources="$(gset org.gnome.desktop.input-sources sources)"
if [[ "$sources" == *"('ibus', 'mozc-on')"* ]]; then ok "入力ソースに Mozc がある"; else ng "入力ソースに Mozc がある" "$sources"; fi
# IBus のアドレスは ~/.config/ibus/bus/ にある(新しいものが今のセッション)
# shellcheck disable=SC2012  # ファイル名は 16 進と英数字だけ
bus_file="$(ls -t "$AGENT_HOME"/.config/ibus/bus/* 2>/dev/null | head -1 || true)"
if [ -n "$bus_file" ]; then
    engines="$(as_agent bash -c ". '$bus_file'; export IBUS_ADDRESS; ibus list-engine" 2>/dev/null || true)"
    if grep -q 'mozc-on' <<<"$engines"; then ok "IBus が Mozc を使える"; else ng "IBus が Mozc を使える" "list-engine に mozc-on がない"; fi
else
    ng "IBus が Mozc を使える" "IBus が動いていない(~/.config/ibus/bus/ がない)"
fi

if selected "${AH_EDITORS:-}" vscode; then
    section "VS Code"
    pkg_pinned code "$(pin VSCODE_VERSION)"
    check "表示を日本語にする設定(argv.json)" grep -q '"locale": *"ja"' "$AGENT_HOME/.vscode/argv.json"
    check "Language Pack の一覧(languagepacks.json)に ja" grep -q '"ja"' "$AGENT_HOME/.config/Code/languagepacks.json"
    check "本体の自動更新を止めている" grep -q '"update.mode": *"none"' "$AGENT_HOME/.config/Code/User/settings.json"
    exts=()
    mapfile -t exts < <(pin_list VSCODE_EXTENSIONS)
    selected "${AH_CLOUDS:-}" aws && exts+=("$(pin VSCODE_EXT_AWS)")
    selected "${AH_CLOUDS:-}" gcp && exts+=("$(pin VSCODE_EXT_GCP)")
    selected "${AH_CLOUDS:-}" azure && exts+=("$(pin VSCODE_EXT_AZURE)")
    [ -n "${AH_CLOUDS:-}" ] && exts+=("$(pin VSCODE_EXT_TERRAFORM)")
    for ext in ${AH_VSCODE_EXTENSIONS:-}; do exts+=("$ext"); done
    have="$(as_agent code --list-extensions --show-versions 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)"
    missing=""
    for ext in "${exts[@]}"; do
        lower="$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')"
        if [[ "$lower" == *@* ]]; then
            grep -qxF "$lower" <<<"$have" || missing+="$ext "
        else
            grep -q "^${lower}@" <<<"$have" || missing+="$ext "
        fi
    done
    eq "拡張機能が固定の版で入っている(${#exts[@]} 個)" "${missing% }" ""
fi

if selected "${AH_EDITORS:-}" zed; then
    section "Zed"
    check "Zed $(pin ZED_VERSION)" bash -c "readlink -f /usr/local/bin/zed | grep -q '/opt/zed-$(pin ZED_VERSION)/'"
    zed_settings="$AGENT_HOME/.config/zed/settings.json"
    check "本体の自動更新を止めている" grep -q '"auto_update": *false' "$zed_settings"
    zexts=()
    mapfile -t zexts < <(pin_list ZED_EXTENSIONS)
    [ -n "${AH_CLOUDS:-}" ] && zexts+=(terraform)
    for ext in ${AH_ZED_EXTENSIONS:-}; do zexts+=("$ext"); done
    missing=""
    for ext in "${zexts[@]}"; do grep -q "\"$ext\": *true" "$zed_settings" || missing+="$ext "; done
    eq "拡張機能を入れる設定(${#zexts[@]} 個)" "${missing% }" ""
fi

if selected "${AH_EDITORS:-}" neovim; then
    section "Neovim"
    check "Neovim が入っている" installed neovim
fi

section "UPS(env.yaml の ups: ${AH_UPS_MODE:-none})"
case "${AH_UPS_MODE:-none}" in
none)
    eq "UPS を見ていない" "$(systemctl is-active nut-monitor.service 2>/dev/null || true)" inactive
    ;;
usb | netclient)
    check "upsmon が動いている" systemctl is-active nut-monitor.service
    if [ "$AH_UPS_MODE" = usb ]; then
        check "upsd が動いている(127.0.0.1 だけ)" bash -c "ss -tlnH | awk '{print \$4}' | grep -qx '127.0.0.1:3493' && ! ss -tlnH | awk '{print \$4}' | grep -qE '^(0\\.0\\.0\\.0|\\*|\\[::\\]):3493\$'"
        target="$AH_UPS_NAME@localhost"
        check "終了の最後に UPS の出力を止める(nutshutdown)" test -x /usr/lib/systemd/system-shutdown/nutshutdown
        eq "UPS の出力を止めるのは終了のときだけ(/etc/killpower がない)" "$(test -e /etc/killpower && echo ある || echo ない)" ない
    else
        target="$AH_UPS_NAME@$AH_UPS_SERVER"
    fi
    status="$(upsc "$target" ups.status 2>/dev/null || true)"
    case " $status " in
    *" OL "*) ok "UPS の状態を読める($target: $status)" ;;
    "  ") ng "UPS の状態を読める" "upsc $target で読めない" ;;
    *) ng "UPS は電源から給電している" "$target: $status(OB はバッテリー運転、LB はバッテリーが少ない)" ;;
    esac
    check "upsmon の設定は root と nut だけが読める" bash -c "[ \"\$(stat -c '%a %U:%G' /etc/nut/upsmon.conf)\" = '640 root:nut' ]"
    check "UPS の通知を agent-notify に渡す" grep -q '^NOTIFYCMD /usr/local/sbin/agent-host-ups-notify' /etc/nut/upsmon.conf
    check "nut が通知の送り先を読める(ACL)" bash -c "getfacl -p /etc/agent-host/notify.env 2>/dev/null | grep -q '^user:nut:r'"
    ;;
esac

section "エージェントへの説明と通知"
for notes in "$AGENT_HOME/.claude/CLAUDE.md" "$AGENT_HOME/.codex/AGENTS.md"; do
    check "${notes#"$AGENT_HOME"/} がある" grep -q 'agent-host-autoinstall' "$notes"
done
check "Claude Code の通知の hook" grep -q 'agent-notify --claude' "$AGENT_HOME/.claude/settings.json"
check "通知のスクリプト" test -x /usr/local/bin/agent-notify
eq "通知の設定は root と agent だけが読める" "$(stat -c '%a %U:%G' /etc/agent-host/notify.env 2>/dev/null)" "640 root:$AGENT_USER"
check "ディスクの残りの監視のタイマー" systemctl is-active agent-host-diskcheck.timer
check "移行のスクリプト" test -x /usr/local/sbin/agent-host-backup

printf '\n%d 項目のうち %d 項目が通った' "$((passed + failed))" "$passed"
if [ "$failed" -gt 0 ]; then
    printf '(✗ が %d 項目)\n' "$failed"
    exit 1
fi
printf '\n'
