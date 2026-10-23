#!/usr/bin/env python3
"""env.yaml の値を埋めた autoinstall.yaml と、スクリプト用の env.sh を書き出す。

使い方: render-autoinstall.py <autoinstall.yaml> <env.yaml> <出力ディレクトリ>
出力: <出力ディレクトリ>/autoinstall.yaml, <出力ディレクトリ>/env.sh
"""
import ipaddress
import os
import shlex
import sys

import yaml


def fail(msg):
    sys.exit(f"render-autoinstall: {msg}")


def require(env, path):
    """env から "a.b" 形式のキーを取り出す。無い・空・CHANGE_ME を含むなら止める。"""
    value = env
    for key in path.split("."):
        if not isinstance(value, dict) or key not in value:
            fail(f"env.yaml に {path} がない")
        value = value[key]
    if value in (None, "", []):
        fail(f"env.yaml の {path} が空")
    if "CHANGE_ME" in repr(value):
        fail(f"env.yaml の {path} に CHANGE_ME が残っている")
    return value


def main():
    if len(sys.argv) != 4:
        fail("使い方: render-autoinstall.py <autoinstall.yaml> <env.yaml> <出力ディレクトリ>")
    src, env_path, out_dir = sys.argv[1:]

    with open(src, encoding="utf-8") as f:
        doc = yaml.safe_load(f)
    with open(env_path, encoding="utf-8") as f:
        env = yaml.safe_load(f) or {}

    hostname = require(env, "hostname")
    password_hash = require(env, "admin.password_hash")
    keys = require(env, "admin.ssh_authorized_keys")
    cidrs = require(env, "lan_cidrs")
    rdp_user = require(env, "rdp.username")
    rdp_password = require(env, "rdp.password")

    if not str(password_hash).startswith("$"):
        fail("admin.password_hash は crypt 形式のハッシュ($6$... など)にする")
    for c in cidrs:
        try:
            ipaddress.ip_network(str(c), strict=False)
        except ValueError:
            fail(f"lan_cidrs の {c} が CIDR として読めない")

    ai = doc["autoinstall"]
    ai["identity"]["hostname"] = str(hostname)
    ai["identity"]["password"] = str(password_hash)
    ai["ssh"]["authorized-keys"] = [str(k) for k in keys]

    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "autoinstall.yaml"), "w", encoding="utf-8", newline="\n") as f:
        yaml.safe_dump(doc, f, allow_unicode=True, sort_keys=False)

    lines = [
        "# build-usb.sh が env.yaml から生成した環境固有値(秘密情報を含む)",
        f"AH_HOSTNAME={shlex.quote(str(hostname))}",
        f"AH_LAN_CIDRS={shlex.quote(' '.join(str(c) for c in cidrs))}",
        f"AH_RDP_USER={shlex.quote(str(rdp_user))}",
        f"AH_RDP_PASSWORD={shlex.quote(str(rdp_password))}",
    ]
    with open(os.path.join(out_dir, "env.sh"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
