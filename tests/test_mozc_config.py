"""mozc-config.py と mozc-keymap.tsv の試験(just test)。

作った config1.db を protobuf として読みなおし、キーの割り当てが独自(CUSTOM)で、表に半角/全角がないことを確かめる。
ホストは要らない(python3 だけで動く)。
"""
import os
import subprocess
import sys
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = os.path.join(REPO, "scripts", "post-install", "mozc-config.py")
TABLE = os.path.join(REPO, "scripts", "post-install", "mozc-keymap.tsv")


def read_varint(data, pos):
    n = shift = 0
    while True:
        byte = data[pos]
        pos += 1
        n |= (byte & 0x7F) << shift
        shift += 7
        if not byte & 0x80:
            return n, pos


def parse(data):
    """protobuf を {field 番号: 値} にする(varint と長さ付きだけ。config1.db に入れるのはこの 2 つ)"""
    fields, pos = {}, 0
    while pos < len(data):
        key, pos = read_varint(data, pos)
        number, wire = key >> 3, key & 7
        if wire == 0:
            fields[number], pos = read_varint(data, pos)
        elif wire == 2:
            length, pos = read_varint(data, pos)
            fields[number] = data[pos:pos + length]
            pos += length
        else:
            raise ValueError(f"想定しない wire type {wire}")
    return fields


class TestMozcConfig(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        out = subprocess.run([sys.executable, SCRIPT, TABLE], capture_output=True, check=True).stdout
        cls.fields = parse(out)
        cls.rows = cls.fields[42].decode("utf-8").splitlines()

    def test_custom_keymap(self):
        self.assertEqual(self.fields[41], 0)  # session_keymap = CUSTOM
        self.assertEqual(sorted(self.fields), [41, 42])

    def test_table_header_and_rows(self):
        # Mozc は 1 行目を見出しとして飛ばす。注釈は入れない
        self.assertEqual(self.rows[0], "status\tkey\tcommand")
        self.assertFalse([r for r in self.rows if r.startswith("#")])
        for row in self.rows[1:]:
            self.assertEqual(len(row.split("\t")), 3, row)

    def test_no_hankaku_zenkaku(self):
        self.assertFalse([r for r in self.rows if r.split("\t")[1] == "Hankaku/Zenkaku"])

    def test_keeps_other_keys(self):
        # MS-IME の表(159 行)から半角/全角の 4 行を外した残り
        self.assertEqual(len(self.rows), 155)
        self.assertIn("Precomposition\tHenkan\tReconvert", self.rows)
        self.assertIn("Composition\tSpace\tConvert", self.rows)


if __name__ == "__main__":
    unittest.main()
