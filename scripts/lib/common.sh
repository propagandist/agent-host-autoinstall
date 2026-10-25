# shellcheck shell=bash
# post-install スクリプトの共通関数。source して使う。
# shellcheck disable=SC2034  # 変数は source した側で使う

AH_ROOT=/opt/agent-host
AH_ENV="${AH_ENV:-$AH_ROOT/env.sh}"
AH_CACHE=/var/cache/agent-host
# 利用者(env.yaml の users)全員が入るグループ。外した利用者を見つけるのと、通知の設定を読ませるのに使う
AH_USERS_GROUP=agent-host-users
# いま構成している利用者(for_each_user・use_user が設定する)。以下の agent_* の関数はこの利用者に対して働く
AGENT_USER=""
AGENT_HOME=""

log() { echo "[agent-host] $*"; }

# 利用者の権限でコマンドを実行する。利用者のホームの中は root で読み書きしない。
# 利用者が置いたシンボリックリンク(末端でも途中のディレクトリでも)を root がたどると、
# ホームの外の root のファイルを書き換えたり所有者を変えたりできてしまうため(Issue #1)。
# 作業ディレクトリは / にする(root のホームに入れず警告が出るのを避ける)
agent_run() { (cd / && runuser -u "$AGENT_USER" -- "$@"); }

# 環境固有値(render-autoinstall.py が env.yaml から生成した env.sh)を読む
load_env() {
    [ -r "$AH_ENV" ] || { log "環境固有値 $AH_ENV が読めない"; exit 1; }
    # shellcheck source=/dev/null
    . "$AH_ENV"
}

# 利用者 <名前> を「いま構成している利用者」にし、利用者ごとの値(users/<名前>.env)を読む
use_user() {
    local env_file="$AH_ROOT/users/$1.env"
    [ -r "$env_file" ] || { log "利用者ごとの値 $env_file が読めない"; exit 1; }
    AGENT_USER="$1"
    AGENT_HOME="$(getent passwd "$1" | cut -d: -f6)"
    AGENT_HOME="${AGENT_HOME:-/home/$1}"
    # shellcheck source=/dev/null
    . "$env_file"
}

# env.yaml の users の 1 人ずつ、use_user してから <関数> を呼ぶ。load_env のあとで使う
for_each_user() {
    local fn="$1" u
    for u in $AH_USERS; do
        use_user "$u"
        "$fn"
    done
}

# 標準入力の内容を、利用者全員のホームの <ホームからのパス> に書く(1 人ずつ write_agent_file で)。
# 終わったあとの「いま構成している利用者」は最後の 1 人になる
write_users_file() {
    local mode="$1" rel="$2" content u
    content="$(cat)"
    for u in $AH_USERS; do
        use_user "$u"
        printf '%s\n' "$content" | write_agent_file "$mode" "$AGENT_HOME/$rel"
    done
}

# スクリプトの残りを利用者ごとに動かす。全体が利用者ごとの処理のスクリプトで、load_env のあとに呼ぶ。
# 利用者の 1 人ずつ同じスクリプトを実行しなおし(その中では use_user した状態で続きが動く)、呼んだ側は終わる
run_per_user() {
    if [ -n "${AH_FOR_USER:-}" ]; then
        use_user "$AH_FOR_USER"
        return 0
    fi
    local u
    for u in $AH_USERS; do
        AH_FOR_USER="$u" bash "$0"
    done
    exit 0
}

# 利用者のユーザーのバス(linger で、セッションがなくてもある)でコマンドを動かす。gsettings・grdctl・systemctl --user に使う
agent_bus_run() {
    local uid
    uid="$(id -u "$AGENT_USER")"
    agent_run env HOME="$AGENT_HOME" XDG_RUNTIME_DIR="/run/user/$uid" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" "$@"
}

# ini 形式のファイルの [section] に key=value を設定する。
# 既にある行(コメントアウトされた行を含む)は置き換え、なければ section の末尾に足す。
# 利用者のホームの中のファイルは、先頭に --as-agent を付けて利用者の権限で書く
ini_set() {
    local run=()
    if [ "${1:-}" = --as-agent ]; then
        run=(agent_run)
        shift
    fi
    "${run[@]}" python3 - "$@" <<'PY'
import re, sys
path, sec, key, val = sys.argv[1:]
try:
    lines = open(path, encoding="utf-8").read().splitlines()
except FileNotFoundError:
    lines = []
out, in_sec, found_sec, done = [], False, False, False
pat = re.compile(r"^\s*#?\s*" + re.escape(key) + r"\s*=")
for line in lines:
    s = line.strip()
    if s.startswith("[") and s.endswith("]"):
        if in_sec and not done:
            out.append(f"{key}={val}")
            done = True
        in_sec = s == f"[{sec}]"
        found_sec = found_sec or in_sec
        out.append(line)
        continue
    if in_sec and pat.match(line):
        if not done:
            out.append(f"{key}={val}")
            done = True
        continue
    out.append(line)
if in_sec and not done:
    out.append(f"{key}={val}")
    done = True
if not found_sec:
    out += [f"[{sec}]", f"{key}={val}"]
with open(path, "w", encoding="utf-8") as f:
    f.write("\n".join(out) + "\n")
PY
}

# URL からファイルを取得し、SHA256 が一致したときだけ dest に置く。既に一致するファイルがあれば取得しない。
download_verified() {
    local url="$1" sha="$2" dest="$3"
    if [ -f "$dest" ] && echo "$sha  $dest" | sha256sum -c --status; then
        touch "$dest"  # 今回の構成で使った印(provision.sh が使わなかった古い版を消す)
        return 0
    fi
    mkdir -p "$(dirname "$dest")"
    curl -fsSL --retry 3 -o "$dest.part" "$url"
    if ! echo "$sha  $dest.part" | sha256sum -c --status; then
        rm -f "$dest.part"
        log "SHA256 が一致しない: $url"
        exit 1
    fi
    mv "$dest.part" "$dest"
}

# npm のパッケージを版を指定して全体に入れ、コマンドを /usr/local/bin に置く(Node.js は 60-devtools.sh で入る)
npm_global() {
    local pkg="$1" version="$2" bin="$3" prefix current
    prefix="$(npm prefix -g)"
    current="$(npm ls -g --depth=0 --json "$pkg" 2>/dev/null |
        python3 -c 'import json,sys; print(json.load(sys.stdin).get("dependencies",{}).get(sys.argv[1],{}).get("version",""))' "$pkg" || true)"
    if [ "$current" != "$version" ]; then
        npm install -g "$pkg@$version"
    fi
    ln -sfn "$prefix/bin/$bin" "/usr/local/bin/$bin"
    log "$pkg $version を入れた"
}

# 利用者の GNOME のセッションが動いていれば、そのバスでコマンドを動かす(その場で反映したいとき)。
# セッションがなければ何もせず 2 を返す
agent_session_run() {
    if ! loginctl list-sessions --no-legend | awk -v u="$AGENT_USER" '$3 == u && $6 == "user"' | grep -q .; then
        return 2
    fi
    agent_bus_run "$@"
}

# 標準入力の内容を利用者のホーム配下のファイルに書く。途中のディレクトリも含めて、すべて利用者の権限で行う
# (root で書くと、利用者が置いたリンクをたどってホームの外に書けてしまう。Issue #1)。
# 同じディレクトリに一時ファイルを作ってから置き換えるので、末端がリンクでもリンク先は変えない
write_agent_file() {
    local mode="$1" dest="$2"
    agent_run mkdir -p "$(dirname "$dest")"
    # shellcheck disable=SC2016  # agent の sh の中で展開する
    agent_run sh -c 'tmp="$(mktemp "$1.XXXXXX")" && cat >"$tmp" && chmod "$2" "$tmp" && mv -fT "$tmp" "$1"' \
        sh "$dest" "$mode"
}
