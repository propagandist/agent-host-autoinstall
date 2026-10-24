#!/usr/bin/env bash
# agent ユーザーを作る(sudo なし)。sysadmin は autoinstall の identity で作られる。
# sysadmin の SSH の鍵とパスワードは、just update のたびに env.yaml に合わせる(退任した人の分を失効させる)。
set -euo pipefail
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"
load_env

if ! id "$AGENT_USER" >/dev/null 2>&1; then
    # パスワードは設定しない(ロック状態)。GDM の自動ログインで入る
    # パスワードがロックされたユーザーでも GDM 自動ログインは通る(VirtualBox で確認済み)
    useradd --create-home --shell /bin/bash --comment "AI agent" "$AGENT_USER"
    log "$AGENT_USER を作成した"
fi

# sudo グループに入っていたら外す
if id -nG "$AGENT_USER" | tr ' ' '\n' | grep -qx sudo; then
    gpasswd -d "$AGENT_USER" sudo
fi

# Codex の認証情報(~/.codex/auth.json)が平文なので、ホームは本人だけが読めるようにする
chmod 700 "$AGENT_HOME"

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
