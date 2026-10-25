#!/usr/bin/env bash
# 利用者(env.yaml の users)のユーザーを作る(sudo なし)。sysadmin は autoinstall の identity で作られる。
# env.yaml から外した利用者は、ユーザーとホームは残したまま、ログインを止める(戻せば使える)。
# sysadmin の SSH の鍵とパスワードは、just update のたびに env.yaml に合わせる(退任した人の分を失効させる)。
set -euo pipefail
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"
load_env

getent group "$AH_USERS_GROUP" >/dev/null || groupadd --system "$AH_USERS_GROUP"

setup_user() {
    if ! id "$AGENT_USER" >/dev/null 2>&1; then
        # パスワードは設定しない(ロック状態)。セッションは systemd が立て(20-sessions.sh)、SSH は鍵だけ
        useradd --create-home --shell /bin/bash --comment "agent-host user" "$AGENT_USER"
        AGENT_HOME="$(getent passwd "$AGENT_USER" | cut -d: -f6)"
        log "$AGENT_USER を作成した"
    fi
    if [ "$(id -u "$AGENT_USER")" -lt 1000 ]; then
        log "$AGENT_USER はシステムのユーザー(uid が 1000 未満)なので、利用者にできない"
        exit 1
    fi
    usermod -a -G "$AH_USERS_GROUP" "$AGENT_USER"
    # sudo グループに入っていたら外す
    if id -nG "$AGENT_USER" | tr ' ' '\n' | grep -qx sudo; then
        gpasswd -d "$AGENT_USER" sudo
    fi
    # 外したあとに戻したときは、期限切れ(下)を外す
    if [ "$(getent shadow "$AGENT_USER" | cut -d: -f8)" = 1 ]; then
        usermod --expiredate '' "$AGENT_USER"
        log "$AGENT_USER を有効に戻した"
    fi
    # Claude Code・Codex の認証情報(~/.claude、~/.codex/auth.json)が平文なので、ホームは本人だけが読めるようにする
    # (useradd -m のホームは 750 だった)
    chmod 700 "$AGENT_HOME"
}
for_each_user setup_user

# --- env.yaml から外した利用者: ログインを止める(ユーザーとホームは残す) ---
# 期限切れにすると、PAM の account で鍵の SSH も拒まれる(パスワードのロックだけでは鍵は止まらない)。
# sshd の AllowUsers からも外れる(40-ssh-ufw.sh)。セッションと RDP のポートは 20-sessions.sh・40-ssh-ufw.sh が止める
members="$(getent group "$AH_USERS_GROUP" | cut -d: -f4 | tr ',' ' ')"
for u in $members; do
    case " $AH_USERS " in *" $u "*) continue ;; esac
    if [ "$(getent shadow "$u" | cut -d: -f8)" != 1 ]; then
        usermod --expiredate 1 "$u"
        log "$u は env.yaml の users にないので、ログインを止めた(ユーザーとホームは残す)"
    fi
    # セッション、ユーザーのサービス(rootless Docker を含む)を止める
    if systemctl is-enabled --quiet "gnome-headless-session@$u.service" 2>/dev/null; then
        systemctl disable --now "gnome-headless-session@$u.service"
        log "$u のセッションを止めた"
    fi
    if [ -e "/var/lib/systemd/linger/$u" ]; then
        loginctl disable-linger "$u"
    fi
    if [ -d "/run/user/$(id -u "$u")" ]; then
        systemctl stop "user@$(id -u "$u").service" || true
    fi
done

# --- sysadmin: env.yaml の sysadmin に合わせる(Issue #2) ---
# インストーラーが置いた ~sysadmin/.ssh/authorized_keys を、env.yaml の ssh_authorized_keys で置き換える。
# 手で足した鍵は消える。今の SSH の接続は切れないが、env.yaml に自分の鍵がなければ次から入れなくなる
# (just update は終わったあとに入りなおせるかを確かめる)。sysadmin は sudo を持つ管理者なので、ここは root で書く
admin_home="$(getent passwd sysadmin | cut -d: -f6)"
if [ -n "$admin_home" ] && [ -s "$AH_ROOT/sysadmin_authorized_keys" ]; then
    install -d -m 700 -o sysadmin -g sysadmin "$admin_home/.ssh"
    if ! cmp -s "$AH_ROOT/sysadmin_authorized_keys" "$admin_home/.ssh/authorized_keys"; then
        install -m 600 -o sysadmin -g sysadmin "$AH_ROOT/sysadmin_authorized_keys" "$admin_home/.ssh/authorized_keys"
        log "sysadmin の SSH の鍵を env.yaml に合わせた($(grep -c . "$AH_ROOT/sysadmin_authorized_keys") 本)"
    fi
fi
# パスワード(sudo とコンソール)。ホストで passwd で替えていても、env.yaml の password_hash に戻す
if [ -n "${AH_SYSADMIN_PASSWORD_HASH:-}" ] && [ -n "$admin_home" ] &&
    [ "$(getent shadow sysadmin | cut -d: -f2)" != "$AH_SYSADMIN_PASSWORD_HASH" ]; then
    usermod -p "$AH_SYSADMIN_PASSWORD_HASH" sysadmin
    log "sysadmin のパスワードを env.yaml の password_hash に合わせた"
fi
