#!/usr/bin/env bash
# 詳細な設定手順書の PDF を build/setup-guide/setup-guide.pdf に作る(just guide と GitHub Actions のリリースが使う)。
# docs/guide.Dockerfile の TeX Live のイメージを作り、その中で latexmk を動かす。手元に TeX は要らない。
# 版(表紙・フッター・奥付)は、作った日付と git describe(タグがあれば v0.1.0 など)。
# 奥付のリポジトリの URL と著作権者は、本文に書かず、git の origin(Actions では GITHUB_REPOSITORY)と LICENSE から入れる
set -euo pipefail

out=build/setup-guide
mkdir -p "$out"
date="$(date +%Y-%m-%d)"
rev="$(git describe --tags --always --dirty 2>/dev/null || echo 不明)"
if [ -n "${GITHUB_REPOSITORY:-}" ]; then
    repo_url="${GITHUB_SERVER_URL:-https://github.com}/$GITHUB_REPOSITORY"
else
    repo_url="$(git remote get-url origin 2>/dev/null | sed -e 's#^git@\([^:]*\):#https://\1/#' -e 's#\.git$##' || true)"
fi
copyright="$(grep -m1 '^Copyright' LICENSE 2>/dev/null | sed 's/(c)/©/' || true)"
holder="$(printf '%s' "$copyright" | sed 's/^Copyright © [0-9-]* //')"
{
    printf '\\newcommand{\\guidedate}{%s}\n' "$date"
    printf '\\newcommand{\\guiderev}{%s}\n' "$rev"
    printf '\\newcommand{\\guideversion}{%s 版(%s)}\n' "$date" "$rev"
    printf '\\newcommand{\\guiderepo}{%s}\n' "${repo_url:-(なし)}"
    printf '\\newcommand{\\guidecopyright}{%s}\n' "${copyright:-(なし)}"
    printf '\\newcommand{\\guideholder}{%s}\n' "${holder:-(なし)}"
} >"$out/guide-version.tex"

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
echo "作成した: $out/setup-guide.pdf($date 版、$rev)"
