#!/usr/bin/env python3
"""Mozc の設定(~/.config/mozc/config1.db)を、キーの割り当ての表から作って標準出力に書く。

使い方: mozc-config.py <表(mozc-keymap.tsv)>
config1.db は Mozc の Config メッセージを protobuf にしたもの(google/mozc の src/protocol/config.proto)。
入れるのはキーの割り当ての種類(session_keymap = 41。CUSTOM = 0)と表(custom_keymap_table = 42)だけで、
ほかの項目は Mozc の既定のまま。76-desktop.sh が呼び、出力を利用者の権限で書く。
"""
import sys

SESSION_KEYMAP = 41
CUSTOM_KEYMAP_TABLE = 42
CUSTOM = 0


def varint(n):
    out = bytearray()
    while True:
        byte = n & 0x7F
        n >>= 7
        out.append(byte | (0x80 if n else 0))
        if not n:
            return bytes(out)


def build(table_text):
    # 注釈の行(# で始まる。出典とライセンス)は Mozc も読み飛ばすので、設定には入れない
    lines = [line for line in table_text.splitlines() if line and not line.startswith("#")]
    table = ("\n".join(lines) + "\n").encode("utf-8")
    return (varint(SESSION_KEYMAP << 3 | 0) + varint(CUSTOM)
            + varint(CUSTOM_KEYMAP_TABLE << 3 | 2) + varint(len(table)) + table)


def main():
    if len(sys.argv) != 2:
        sys.exit("使い方: mozc-config.py <表(mozc-keymap.tsv)>")
    with open(sys.argv[1], encoding="utf-8") as f:
        sys.stdout.buffer.write(build(f.read()))


if __name__ == "__main__":
    main()
