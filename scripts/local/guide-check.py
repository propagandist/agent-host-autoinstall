#!/usr/bin/env python3
"""手順書の PDF の各ページを画像にして、左右の余白に何か描かれていないかを確かめる(guide-check.sh から呼ぶ)。

使い方: guide-check.py <PDF>
余白は docs/setup-guide.tex の geometry(A4、margin=22mm)。1 ページ目は表紙で、絵を全面に敷くので見ない。
淡い地の色(コマンドの枠の #F4F5F7、表の見出しの #E6ECF4)も拾うよう、白に近いしきい値で見る。
"""
import glob
import os
import subprocess
import sys
import tempfile

DPI = 144
PAGE_W = 595.276  # A4 の幅(pt)
MARGIN = 22 / 25.4 * 72  # geometry の margin=22mm(pt)
TOL = 1.0  # 字や線の縁のにじみの分(pt)
WHITE = 250  # これより暗い画素を「描かれている」とみなす


def read_pgm(path):
    with open(path, "rb") as f:
        data = f.read()
    fields, pos = [], 0
    while len(fields) < 4:  # P5、幅、高さ、最大値
        while data[pos:pos + 1].isspace():
            pos += 1
        start = pos
        while not data[pos:pos + 1].isspace():
            pos += 1
        fields.append(data[start:pos])
    if fields[0] != b"P5":
        sys.exit(f"{path} が PGM(P5)でない")
    return int(fields[1]), int(fields[2]), data[pos + 1:]


def check_page(path):
    """余白に描かれている所を (左右, 上の y, 下の y, 余白へ出た幅) で返す(単位は pt)"""
    w, h, px = read_pgm(path)
    s = w / PAGE_W
    left = int((MARGIN - TOL) * s)
    right = int((PAGE_W - MARGIN + TOL) * s) + 1
    hits = {"左": [], "右": []}
    for y in range(h):
        row = px[y * w:(y + 1) * w]
        xs = [x for x in range(left) if row[x] < WHITE]
        if xs:
            hits["左"].append((y, MARGIN - min(xs) / s))
        xs = [x for x in range(right, w) if row[x] < WHITE]
        if xs:
            hits["右"].append((y, (max(xs) + 1) / s - (PAGE_W - MARGIN)))
    found = []
    for side, rows in hits.items():
        group = []
        for y, d in rows + [(None, 0)]:
            if group and (y is None or y - group[-1][0] > 3):
                found.append((side, group[0][0] / s, group[-1][0] / s, max(g[1] for g in group)))
                group = []
            if y is not None:
                group.append((y, d))
    return found


def main():
    if len(sys.argv) != 2:
        sys.exit("使い方: guide-check.py <PDF>")
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(["pdftoppm", "-gray", "-r", str(DPI), "-f", "2", sys.argv[1], os.path.join(tmp, "p")], check=True)
        pages = sorted(glob.glob(os.path.join(tmp, "p-*.pgm")))
        if not pages:
            sys.exit("ページの画像ができなかった")
        bad = 0
        for path in pages:
            page = int(path.rsplit("-", 1)[1].split(".")[0])
            for side, top, bottom, d in check_page(path):
                print(f"✗ {page} ページ: {side}の余白へ {d:.1f}pt 出ている(上から {top:.0f}〜{bottom:.0f}pt)", file=sys.stderr)
                bad += 1
    if bad:
        sys.exit(1)
    print(f"余白の画素: {len(pages)} ページに、はみ出しはない")


if __name__ == "__main__":
    main()
