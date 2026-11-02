#!/usr/bin/env bash
# 手順書の PDF(build/setup-guide/setup-guide.pdf)の、余白へのはみ出しを確かめる(just guide-check。just guide のあとに動く)。
#   1. ログの Overfull \hbox(図、表、本文の改行できない \code)
#   2. ログの、コマンドの枠の長い行(Verbatim は Overfull を出さないので、setup-guide.tex の前置きで警告を出している)
#   3. ページを画像にして、左右の余白に何か描かれていないか(guide-check.py。図の線や淡い地の色も拾う)
set -euo pipefail

out=build/setup-guide
pdf="$out/setup-guide.pdf"
log="$out/setup-guide.log"
[ -f "$pdf" ] && [ -f "$log" ] || { echo "$pdf がない。先に just guide で作る" >&2; exit 1; }

fail=0
if grep -q '^Overfull \\hbox' "$log"; then
    echo "✗ Overfull \\hbox(行は setup-guide.tex の行番号):" >&2
    grep -A1 '^Overfull \\hbox' "$log" | grep -v '^--$' >&2
    fail=1
fi
if grep -q '^Package guide Warning: verbatim line too wide' "$log"; then
    echo "✗ コマンドの枠からはみ出す行(コメントを次の行に分けるか、上の行に移す):" >&2
    grep -A1 '^Package guide Warning: verbatim line too wide' "$log" | grep -v '^--$' | paste -d ' ' - - | sort -u >&2
    fail=1
fi
scripts/local/in-ubuntu.sh "poppler-utils python3" "pdftoppm python3" python3 scripts/local/guide-check.py "$pdf" || fail=1

if [ "$fail" -ne 0 ]; then
    echo "手順書の PDF にはみ出しがある" >&2
    exit 1
fi
echo "手順書の PDF にはみ出しはない"
