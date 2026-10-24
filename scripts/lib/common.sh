# shellcheck shell=bash
# post-install スクリプトの共通関数。source して使う。
# shellcheck disable=SC2034  # 変数は source した側で使う

AH_ROOT=/opt/agent-host
AH_ENV="${AH_ENV:-$AH_ROOT/env.sh}"
AH_CACHE=/var/cache/agent-host
AGENT_USER=agent
AGENT_HOME=/home/agent

log() { echo "[agent-host] $*"; }

# agent の権限でコマンドを実行する。agent のホームの中は root で読み書きしない。
# agent が置いたシンボリックリンク(末端でも途中のディレクトリでも)を root がたどると、
# ホームの外の root のファイルを書き換えたり所有者を変えたりできてしまうため(Issue #1)。
# 作業ディレクトリは / にする(root のホームに入れず警告が出るのを避ける)
agent_run() { (cd / && runuser -u "$AGENT_USER" -- "$@"); }

# 環境固有値(build-usb.sh が生成した env.sh)を読む
load_env() {
    [ -r "$AH_ENV" ] || { log "環境固有値 $AH_ENV が読めない"; exit 1; }
    # shellcheck source=/dev/null
    . "$AH_ENV"
}

# ini 形式のファイルの [section] に key=value を設定する。
# 既にある行(コメントアウトされた行を含む)は置き換え、なければ section の末尾に足す。
# agent のホームの中のファイルは、先頭に --as-agent を付けて agent の権限で書く
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

# 標準入力の内容を agent のホーム配下のファイルに書く。途中のディレクトリも含めて、すべて agent の権限で行う
# (root で書くと、agent が置いたリンクをたどってホームの外に書けてしまう。Issue #1)。
# 同じディレクトリに一時ファイルを作ってから置き換えるので、末端がリンクでもリンク先は変えない
write_agent_file() {
    local mode="$1" dest="$2"
    agent_run mkdir -p "$(dirname "$dest")"
    # shellcheck disable=SC2016  # agent の sh の中で展開する
    agent_run sh -c 'tmp="$(mktemp "$1.XXXXXX")" && cat >"$tmp" && chmod "$2" "$tmp" && mv -fT "$tmp" "$1"' \
        sh "$dest" "$mode"
}
