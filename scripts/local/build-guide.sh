#!/usr/bin/env bash
# 詳細な設定手順書の PDF を build/setup-guide/setup-guide.pdf に作る(just guide と GitHub Actions のリリースが使う)。
# docs/guide.Dockerfile の TeX Live のイメージを作り、その中で latexmk を動かす。手元に TeX は要らない。
# 版(表紙とフッター)は、作った日付と git describe(タグがあれば v0.1.0 など)
set -euo pipefail

out=build/setup-guide
mkdir -p "$out"
# shellcheck disable=SC2016  # \newcommand はそのまま書く
printf '%s{%s 版(%s)}\n' '\newcommand{\guideversion}' "$(date +%Y-%m-%d)" \
    "$(git describe --tags --always --dirty 2>/dev/null || echo 不明)" >"$out/guide-version.tex"

docker build -q -t agent-host-guide -f docs/guide.Dockerfile docs >/dev/null

# Windows(Git Bash)では Docker に Windows の形のパスを渡す。Linux では作ったファイルを自分の持ち物にする
case "$(uname -s)" in
MINGW* | MSYS*) repo="$(pwd -W)"; user=() ;;
*) repo="$(pwd)"; user=(--user "$(id -u):$(id -g)") ;;
esac
if ! MSYS_NO_PATHCONV=1 docker run --rm "${user[@]}" -v "$repo:/repo" -w /repo \
    -e TEXINPUTS="/repo/$out:" agent-host-guide \
    latexmk -lualatex -interaction=nonstopmode -halt-on-error -outdir="$out" docs/setup-guide.tex \
    >"$out/latexmk.out" 2>&1; then
    tail -30 "$out/latexmk.out" >&2
    exit 1
fi
echo "作成した: $out/setup-guide.pdf($(sed 's/.*}{\(.*\)}$/\1/' "$out/guide-version.tex"))"
