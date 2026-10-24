#!/usr/bin/env python3
"""env.yaml の値を埋めた autoinstall.yaml と、スクリプト用の env.sh を書き出す。

使い方: render-autoinstall.py <autoinstall.yaml> <env.yaml> <出力ディレクトリ>
出力: <出力ディレクトリ>/autoinstall.yaml, env.sh, agent_authorized_keys, ca/*.crt
"""
import ipaddress
import os
import re
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
    proxy = env.get("proxy") or {}
    proxy_url = str(proxy.get("url") or "")
    no_proxy = str(proxy.get("no_proxy") or "localhost,127.0.0.1,::1")
    ca_certs = env.get("ca_certs") or []
    editors = env.get("editors") or []
    agent_keys = env.get("agent_ssh_authorized_keys") or []
    dev_ports = [str(p) for p in (env.get("dev_ports") or [])]

    if proxy_url and not re.fullmatch(r"https?://\S+", proxy_url):
        fail("proxy.url は http://host:port の形にする")
    for i, pem in enumerate(ca_certs):
        if "-----BEGIN CERTIFICATE-----" not in str(pem):
            fail(f"ca_certs の {i + 1} 番目が PEM の証明書に見えない")
    for e in editors:
        if e not in ("vscode", "neovim", "zed"):
            fail(f"editors の {e} は使えない(vscode, neovim, zed)")
    for p in dev_ports:
        m = re.fullmatch(r"(\d+)(?::(\d+))?", p)
        if not m or not all(1024 <= int(x) <= 65535 for x in m.groups() if x):
            fail(f"dev_ports の {p} は 1024〜65535 のポートか範囲(3000:3999)にする")
    for k in agent_keys:
        if "CHANGE_ME" in str(k):
            fail("agent_ssh_authorized_keys に CHANGE_ME が残っている")
    agents = env.get("agents") or []
    for a in agents:
        if a not in ("opencode", "copilot", "antigravity"):
            fail(f"agents の {a} は使えない(opencode, copilot, antigravity)")
    desktop_color = str(env.get("desktop_color") or "")
    if desktop_color and not re.fullmatch(r"#[0-9a-fA-F]{6}", desktop_color):
        fail("desktop_color は #RRGGBB の形にする")
    notify = env.get("notify") or {}
    slack_url = str(notify.get("slack_webhook_url") or "")
    if slack_url and not slack_url.startswith("https://hooks.slack.com/"):
        fail("notify.slack_webhook_url は https://hooks.slack.com/ で始まる URL にする")
    # 宛先は IP か、IP Messenger のユーザー名・ホスト名・ニックネーム(送るときにブロードキャストで探す)
    ipmsg_to = [str(a) for a in (notify.get("ipmsg_to") or [])]
    for a in ipmsg_to:
        if not re.fullmatch(r"[^\s:]+", a):
            fail(f"notify.ipmsg_to の {a} は空白と : を含まない名前か IP にする")
    ipmsg_broadcast = [str(a) for a in (notify.get("ipmsg_broadcast") or [])]
    for a in ipmsg_broadcast:
        try:
            ipaddress.ip_address(a)
        except ValueError:
            fail(f"notify.ipmsg_broadcast の {a} が IP アドレスとして読めない")

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
    if proxy_url:
        ai["proxy"] = proxy_url
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
        f"AH_PROXY_URL={shlex.quote(proxy_url)}",
        f"AH_NO_PROXY={shlex.quote(no_proxy)}",
        f"AH_EDITORS={shlex.quote(' '.join(editors))}",
        f"AH_DEV_PORTS={shlex.quote(' '.join(dev_ports))}",
        f"AH_AGENTS={shlex.quote(' '.join(agents))}",
        f"AH_DESKTOP_COLOR={shlex.quote(desktop_color)}",
        f"AH_SLACK_WEBHOOK_URL={shlex.quote(slack_url)}",
        f"AH_IPMSG_TO={shlex.quote(' '.join(ipmsg_to))}",
        f"AH_IPMSG_BROADCAST={shlex.quote(' '.join(ipmsg_broadcast))}",
    ]
    with open(os.path.join(out_dir, "env.sh"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")

    # 公開鍵と CA 証明書は行をまたぐのでファイルで渡す
    with open(os.path.join(out_dir, "agent_authorized_keys"), "w", encoding="utf-8", newline="\n") as f:
        f.write("".join(str(k).strip() + "\n" for k in agent_keys))
    ca_dir = os.path.join(out_dir, "ca")
    os.makedirs(ca_dir, exist_ok=True)
    for i, pem in enumerate(ca_certs):
        path = os.path.join(ca_dir, f"agent-host-{i + 1:02d}.crt")
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(str(pem).strip() + "\n")


if __name__ == "__main__":
    main()
