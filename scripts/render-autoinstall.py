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


def render_network(net):
    """env.yaml の network から netplan の設定(autoinstall の network キー)を作る。"""
    mode = net.get("mode")
    iface = str(net.get("interface") or "en*")
    # Desktop なので NetworkManager に任せる(GNOME の設定画面から見える)
    eth = {"match": {"name": iface}}
    if mode == "dhcp":
        eth["dhcp4"] = True
    elif mode == "static":
        for key in ("address", "gateway", "dns"):
            if not net.get(key):
                fail(f"network.mode が static のときは network.{key} が要る")
        try:
            ipaddress.ip_interface(str(net["address"]))
            ipaddress.ip_address(str(net["gateway"]))
            for d in net["dns"]:
                ipaddress.ip_address(str(d))
        except ValueError as e:
            fail(f"network の値が読めない: {e}")
        if "/" not in str(net["address"]):
            fail("network.address はプレフィックス付き(192.0.2.10/24 の形)にする")
        eth["dhcp4"] = False
        eth["addresses"] = [str(net["address"])]
        eth["routes"] = [{"to": "default", "via": str(net["gateway"])}]
        eth["nameservers"] = {"addresses": [str(d) for d in net["dns"]]}
        if net.get("search"):
            eth["nameservers"]["search"] = [str(s) for s in net["search"]]
    else:
        fail("network.mode は dhcp か static にする")
    return {"version": 2, "renderer": "NetworkManager", "ethernets": {"lan": eth}}


def main():
    if len(sys.argv) != 4:
        fail("使い方: render-autoinstall.py <autoinstall.yaml> <env.yaml> <出力ディレクトリ>")
    src, env_path, out_dir = sys.argv[1:]

    with open(src, encoding="utf-8") as f:
        doc = yaml.safe_load(f)
    with open(env_path, encoding="utf-8") as f:
        env = yaml.safe_load(f) or {}

    hostname = require(env, "hostname")
    keyboard_layout = require(env, "keyboard_layout")
    password_hash = require(env, "sysadmin.password_hash")
    keys = require(env, "sysadmin.ssh_authorized_keys")
    cidrs = require(env, "lan_cidrs")
    rdp_user = require(env, "rdp.username")
    rdp_password = require(env, "rdp.password")
    git_user_name = require(env, "git_user_name")
    git_user_email = require(env, "git_user_email")
    network = render_network(require(env, "network"))
    ntp_servers = env.get("ntp_servers") or []

    if not str(password_hash).startswith("$"):
        fail("sysadmin.password_hash は crypt 形式のハッシュ($6$... など)にする")
    if keyboard_layout not in ("us", "jp"):
        fail("keyboard_layout は us か jp にする")
    for c in cidrs:
        try:
            ipaddress.ip_network(str(c), strict=False)
        except ValueError:
            fail(f"lan_cidrs の {c} が CIDR として読めない")

    ai = doc["autoinstall"]
    ai["keyboard"]["layout"] = str(keyboard_layout)
    ai["network"] = network
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
        f"AH_NTP_SERVERS={shlex.quote(' '.join(str(s) for s in ntp_servers))}",
        f"AH_GIT_USER_NAME={shlex.quote(str(git_user_name))}",
        f"AH_GIT_USER_EMAIL={shlex.quote(str(git_user_email))}",
    ]
    with open(os.path.join(out_dir, "env.sh"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
