# shellcheck shell=bash
# scripts/local/ のスクリプトが読み込む共通の関数(単独では実行しない)。
# 構成リポジトリ(docs/fleet.md)から使えるように、リポジトリの外の env.yaml と、呼び出したディレクトリから見た
# 相対パスを扱う。Docker の中から見えるのはこのリポジトリだけなので、env.yaml は build/.env/ に写してから渡す。

# パスを解決する。絶対パスはそのまま。相対パスは、呼び出したディレクトリ(just が AGENT_HOST_CALLER_DIR で渡す)
# にあればそれ、なければこのリポジトリの直下から見る(既定の autoinstall/env.yaml など)
resolve_path() {
    local p="$1" caller="${AGENT_HOST_CALLER_DIR:-$PWD}"
    case "$p" in
    /* | [A-Za-z]:[/\\]*) printf '%s\n' "$p" ;;
    *)
        if [ -e "$caller/$p" ] || [ ! -e "$p" ]; then
            printf '%s\n' "$caller/$p"
        else
            printf '%s\n' "$p"
        fi
        ;;
    esac
}

# env.yaml を build/.env/ に写し、写した先を ENV_FILES に入れる。終わったら消す(秘密情報が入るため)
copy_envs() {
    local i=0 f src
    ENV_FILES=()
    rm -rf build/.env
    mkdir -p build/.env
    chmod 700 build/.env
    trap 'rm -rf build/.env' EXIT
    for f in "$@"; do
        src="$(resolve_path "$f")"
        [ -f "$src" ] || { echo "$f がない" >&2; exit 1; }
        i=$((i + 1))
        install -m 600 "$src" "build/.env/$i-$(basename "$src")"
        ENV_FILES+=("build/.env/$i-$(basename "$src")")
    done
    [ "$i" -gt 0 ] || { echo "env.yaml を 1 つ以上渡す" >&2; exit 2; }
}

# 作った版の記録を build/.env/BUILD-INFO に書く(ホストの /opt/agent-host/BUILD-INFO になる。秘密情報は入れない)。
# 構成リポジトリは、自分の版を AGENT_HOST_CONFIG_REV で渡す
write_build_info() {
    local f names=()
    for f in "$@"; do names+=("$(basename "$(resolve_path "$f")")"); done
    # ホストではシェルの変数として読み込むので、値は単一引用符で囲む
    {
        printf "tool='%s'\n" "$(git describe --tags --always --dirty 2>/dev/null || echo 不明)"
        printf "config='%s'\n" "${AGENT_HOST_CONFIG_REV:-}"
        printf "env='%s'\n" "${names[*]}"
        printf "built='%s'\n" "$(date +%Y-%m-%dT%H:%M:%S%z)"
    } >build/.env/BUILD-INFO
}
