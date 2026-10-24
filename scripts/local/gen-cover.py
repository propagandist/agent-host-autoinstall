#!/usr/bin/env python3
"""手順書の表紙の絵を Gemini で作る(docs/cover.jpg)。

使い方: python3 scripts/local/gen-cover.py <出力ファイル> [枚数]
API キーは環境変数 GEMINI_API_KEY(リポジトリ直下の .env に書いてよい。.env はコミットしない)。
文字は TeX で組むので、絵には文字を入れさせない。候補を何枚か作り、選んだものを docs/cover.jpg に置く。
"""
import base64
import json
import os
import sys
import urllib.request

MODEL = "gemini-3-pro-image"
PROMPT = """\
A refined editorial cover illustration for a technical handbook about an always-on AI agent workstation.
Scene: a single compact desktop PC tower in a quiet office at night, glowing softly, running continuously.
Around it, several translucent luminous panels float like parallel terminal windows, each tended by an
abstract, faceless AI agent rendered as a small geometric light form, working in parallel.
Thin glowing network lines connect the tower to a distant laptop, suggesting remote desktop access over a private LAN.
Style: modern flat-meets-isometric vector illustration, clean geometry, subtle grain, soft volumetric light.
Palette: deep navy (#1F3A5F) and midnight blue dominant, cool cyan highlights, one restrained warm amber accent.
Composition: tall portrait book cover, ONE continuous seamless scene from top to bottom with smooth gradients;
no bands, no stripes, no frames, no borders, no split panels, no hard horizontal edges.
The top third is a softly lit dark wall that is nearly empty, so a title can sit there; the bottom fifth is a dark floor
that fades smoothly into deep navy. The main subject sits in the middle, slightly right of center, and its glow fades
gradually into the surrounding darkness.
Strictly no text, no letters, no numbers, no logos, no brand marks, no UI text anywhere in the image.
"""


def load_key() -> str:
    key = os.environ.get("GEMINI_API_KEY", "")
    if not key and os.path.exists(".env"):
        for line in open(".env", encoding="utf-8"):
            if line.startswith("GEMINI_API_KEY="):
                key = line.split("=", 1)[1].strip().strip('"')
    if not key:
        sys.exit("GEMINI_API_KEY がない(.env か環境変数に書く)")
    return key


def generate(key: str) -> bytes:
    body = {
        "contents": [{"parts": [{"text": PROMPT}]}],
        "generationConfig": {
            "responseModalities": ["IMAGE"],
            "imageConfig": {"aspectRatio": "3:4", "imageSize": "2K"},
        },
    }
    req = urllib.request.Request(
        f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "x-goog-api-key": key},
    )
    with urllib.request.urlopen(req, timeout=300) as res:
        data = json.load(res)
    for part in data["candidates"][0]["content"]["parts"]:
        if "inlineData" in part:
            return base64.b64decode(part["inlineData"]["data"])
    sys.exit(f"絵が返らなかった: {json.dumps(data)[:500]}")


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    out = sys.argv[1]
    count = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    key = load_key()
    root, ext = os.path.splitext(out)
    for i in range(count):
        path = out if count == 1 else f"{root}-{i + 1}{ext}"
        with open(path, "wb") as f:
            f.write(generate(key))
        print(f"作った: {path}")


if __name__ == "__main__":
    main()
