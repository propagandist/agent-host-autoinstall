"""render-autoinstall.py と stage.sh の試験(just test)。

env.yaml の検査(知らないキー、SOPS、書き忘れ、値の形、組み合わせ)と重ね方、生成する env.sh と
/opt/agent-host に置くものの形を確かめる。ホストは要らない(Linux の python3 と python3-yaml で動く)。
"""
import os
import shlex
import subprocess
import sys
import tempfile
import unittest

import yaml

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RENDER = os.path.join(REPO, "scripts", "render-autoinstall.py")
STAGE = os.path.join(REPO, "scripts", "stage.sh")
AUTOINSTALL = os.path.join(REPO, "autoinstall", "autoinstall.yaml")

# 通る最小の env.yaml
BASE = {
    "hostname": "agent-host-test",
    "keyboard_layout": "us",
    "sysadmin": {
        "password_hash": "$6$salt$hash",
        "ssh_authorized_keys": ["ssh-ed25519 AAAAtest sysadmin@test"],
    },
    "network": {"mode": "dhcp"},
    "git_user_name": "agent-host-test",
    "git_user_email": "agent-host-test@example.invalid",
    "lan_cidrs": ["192.0.2.0/24"],
    "rdp": {"username": "rdp", "password": "rdp-password"},
}


def read_env_sh(path):
    """env.sh を辞書にする(KEY='値' の行だけ)。"""
    out = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            if line.startswith("AH_"):
                key, value = line.rstrip("\n").split("=", 1)
                out[key] = shlex.split(value)[0] if value else ""
    return out


class Case(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.n = 0

    def write(self, data, text=None):
        self.n += 1
        path = os.path.join(self.tmp.name, f"env{self.n}.yaml")
        with open(path, "w", encoding="utf-8") as f:
            f.write(text if text is not None else yaml.safe_dump(data, allow_unicode=True))
        return path

    def render(self, *envs):
        out = os.path.join(self.tmp.name, "out")
        return subprocess.run(
            [sys.executable, RENDER, AUTOINSTALL, *envs, out],
            capture_output=True, text=True,
        ), out

    def ok(self, *envs):
        r, out = self.render(*envs)
        self.assertEqual(r.returncode, 0, r.stderr)
        return out

    def ng(self, data, message):
        r, _ = self.render(self.write(data))
        self.assertNotEqual(r.returncode, 0, f"通ってしまった: {data}")
        self.assertIn(message, r.stderr)

    def with_(self, **kw):
        d = yaml.safe_load(yaml.safe_dump(BASE))
        d.update(kw)
        return d


class TestValid(Case):
    def test_minimal(self):
        out = self.ok(self.write(BASE))
        env = read_env_sh(os.path.join(out, "env.sh"))
        self.assertEqual(env["AH_HOSTNAME"], "agent-host-test")
        self.assertEqual(env["AH_LAN_CIDRS"], "192.0.2.0/24")
        self.assertEqual(env["AH_RDP_PASSWORD"], "rdp-password")
        self.assertEqual(env["AH_NO_PROXY"], "localhost,127.0.0.1,::1")
        self.assertEqual(env["AH_EDITORS"], "")
        with open(os.path.join(out, "autoinstall.yaml"), encoding="utf-8") as f:
            ai = yaml.safe_load(f)["autoinstall"]
        self.assertEqual(ai["identity"]["hostname"], "agent-host-test")
        self.assertEqual(ai["identity"]["password"], "$6$salt$hash")
        self.assertEqual(ai["ssh"]["authorized-keys"], ["ssh-ed25519 AAAAtest sysadmin@test"])
        # sysadmin の鍵とパスワードは just update でも反映する(Issue #2)
        with open(os.path.join(out, "sysadmin_authorized_keys"), encoding="utf-8") as f:
            self.assertEqual(f.read(), "ssh-ed25519 AAAAtest sysadmin@test\n")
        self.assertEqual(env["AH_SYSADMIN_PASSWORD_HASH"], "$6$salt$hash")
        self.assertEqual(ai["network"]["ethernets"]["lan"], {"match": {"name": "en*"}, "dhcp4": True})
        self.assertNotIn("proxy", ai)
        self.assertEqual(ai["drivers"], {"install": True})  # NVIDIA などのドライバーをインストールの中で入れる

    def test_example_is_rejected_until_filled(self):
        r, _ = self.render(os.path.join(REPO, "autoinstall", "env.example.yaml"))
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("CHANGE_ME", r.stderr)

    def test_example_keys_are_known(self):
        # サンプルに書いたキーは、すべて KNOWN_KEYS にあること(CHANGE_ME 以外で落ちないこと)
        with open(os.path.join(REPO, "autoinstall", "env.example.yaml"), encoding="utf-8") as f:
            example = yaml.safe_load(f)
        filled = yaml.safe_load(yaml.safe_dump(example).replace("CHANGE_ME", "x"))
        filled["sysadmin"]["password_hash"] = "$6$x"
        out = self.ok(self.write(filled))
        self.assertTrue(os.path.exists(os.path.join(out, "env.sh")))

    def test_static_network(self):
        out = self.ok(self.write(self.with_(network={
            "mode": "static", "interface": "enp1s0", "address": "192.0.2.10/24",
            "gateway": "192.0.2.1", "dns": ["192.0.2.53"], "search": ["example.internal"],
        })))
        with open(os.path.join(out, "autoinstall.yaml"), encoding="utf-8") as f:
            lan = yaml.safe_load(f)["autoinstall"]["network"]["ethernets"]["lan"]
        self.assertEqual(lan["addresses"], ["192.0.2.10/24"])
        self.assertEqual(lan["routes"], [{"to": "default", "via": "192.0.2.1"}])
        self.assertEqual(lan["nameservers"], {"addresses": ["192.0.2.53"], "search": ["example.internal"]})

    def test_options(self):
        out = self.ok(self.write(self.with_(
            editors=["vscode", "zed", "neovim"],
            vscode_extensions=["hashicorp.terraform@2.40.0", "ms-python.python"],
            zed_extensions=["toml"],
            agents=["opencode"],
            clouds=["aws", "gcp", "azure"],
            dev_ports=[3000, "8000:8099"],
            desktop_color="#123abc",
            gitea_url="https://gitea.example.internal/",
            proxy={"url": "http://proxy.example.internal:8080"},
            notify={"slack_webhook_url": "https://hooks.slack.com/services/x",
                    "ipmsg_to": ["someone", "192.0.2.20"], "ipmsg_broadcast": ["192.0.2.255"]},
            ca_certs=["-----BEGIN CERTIFICATE-----\nAAAA\n-----END CERTIFICATE-----\n"],
            agent_ssh_authorized_keys=["ssh-ed25519 AAAAagent agent@test"],
        )))
        env = read_env_sh(os.path.join(out, "env.sh"))
        self.assertEqual(env["AH_EDITORS"], "vscode zed neovim")
        self.assertEqual(env["AH_VSCODE_EXTENSIONS"], "hashicorp.terraform@2.40.0 ms-python.python")
        self.assertEqual(env["AH_CLOUDS"], "aws gcp azure")
        self.assertEqual(env["AH_DEV_PORTS"], "3000 8000:8099")
        self.assertEqual(env["AH_GITEA_URL"], "https://gitea.example.internal")  # 末尾の / は落とす
        self.assertEqual(env["AH_IPMSG_TO"], "someone 192.0.2.20")
        self.assertEqual(env["AH_UPS_MODE"], "none")  # 書かなければ使わない
        with open(os.path.join(out, "autoinstall.yaml"), encoding="utf-8") as f:
            self.assertEqual(yaml.safe_load(f)["autoinstall"]["proxy"], "http://proxy.example.internal:8080")
        with open(os.path.join(out, "agent_authorized_keys"), encoding="utf-8") as f:
            self.assertEqual(f.read(), "ssh-ed25519 AAAAagent agent@test\n")
        with open(os.path.join(out, "ca", "agent-host-01.crt"), encoding="utf-8") as f:
            self.assertTrue(f.read().startswith("-----BEGIN CERTIFICATE-----"))

    def test_shell_quoting(self):
        # 単一引用符や $ を含む値でも、env.sh を読み込んだ値がそのまま戻ること
        pw = "it's $HOME `x` \"y\""
        out = self.ok(self.write(self.with_(rdp={"username": "rdp", "password": pw})))
        r = subprocess.run(["bash", "-c", f'. "{out}/env.sh"; printf %s "$AH_RDP_PASSWORD"'],
                           capture_output=True, text=True)
        self.assertEqual(r.stdout, pw)


class TestUps(Case):
    def test_usb(self):
        env = read_env_sh(os.path.join(self.ok(self.write(self.with_(ups={"mode": "usb"}))), "env.sh"))
        self.assertEqual((env["AH_UPS_MODE"], env["AH_UPS_DRIVER"], env["AH_UPS_PORT"], env["AH_UPS_NAME"]),
                         ("usb", "usbhid-ups", "auto", "ups"))

    def test_netclient(self):
        out = self.ok(self.write(self.with_(ups={"mode": "netclient", "server": "nas.example.internal",
                                                 "name": "ups1", "username": "monuser", "password": "secret"})))
        env = read_env_sh(os.path.join(out, "env.sh"))
        self.assertEqual((env["AH_UPS_SERVER"], env["AH_UPS_NAME"], env["AH_UPS_USER"], env["AH_UPS_PASSWORD"]),
                         ("nas.example.internal", "ups1", "monuser", "secret"))

    def test_rejected(self):
        cases = [
            ({"mode": "serial"}, "ups.mode"),
            ({"mode": "usb", "driver": "USB HID"}, "ups.driver"),
            ({"mode": "usb", "port": "a b"}, "ups.port"),
            ({"mode": "usb", "name": "my ups"}, "ups.name"),
            ({"mode": "netclient"}, "ups.server"),
            ({"mode": "netclient", "server": "nas"}, "ups.username と ups.password"),
            ({"mode": "netclient", "server": "nas", "username": "u", "password": "a b"}, "ups.password に空白"),
            ({"mode": "netclient", "server": "nas", "username": "u", "password": "CHANGE_ME"}, "CHANGE_ME"),
            ({"mode": "usb", "baud": 9600}, "ups.baud は知らないキー"),
        ]
        for ups, message in cases:
            with self.subTest(ups=ups):
                self.ng(self.with_(ups=ups), message)


class TestOverlay(Case):
    def test_later_wins_and_dicts_merge(self):
        common = self.write(self.with_(hostname="common", editors=["vscode", "zed"]))
        host = self.write({"hostname": "agent-host-02", "editors": ["neovim"],
                           "rdp": {"password": "host-password"}})
        env = read_env_sh(os.path.join(self.ok(common, host), "env.sh"))
        self.assertEqual(env["AH_HOSTNAME"], "agent-host-02")
        self.assertEqual(env["AH_EDITORS"], "neovim")         # 並びは置き換える
        self.assertEqual(env["AH_RDP_USER"], "rdp")            # 辞書はキーごとに重ねる
        self.assertEqual(env["AH_RDP_PASSWORD"], "host-password")

    def test_empty_file(self):
        self.ok(self.write(BASE), self.write(None, text=""))


class TestRejected(Case):
    def test_unknown_key(self):
        self.ng(self.with_(hostnmae="x"), "hostnmae は知らないキー")

    def test_unknown_subkey(self):
        self.ng(self.with_(rdp={"username": "rdp", "password": "p", "port": 1}), "rdp.port は知らないキー")

    def test_unknown_key_in_later_file(self):
        r, _ = self.render(self.write(BASE), self.write({"clods": ["aws"]}))
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("clods は知らないキー", r.stderr)

    def test_sops_encrypted(self):
        self.ng(self.with_(sops={"age": []}), "SOPS で暗号化されたまま")

    def test_not_a_mapping(self):
        r, _ = self.render(self.write(None, text="- a\n- b\n"))
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("キーと値の形", r.stderr)

    def test_required(self):
        for key in ("hostname", "keyboard_layout", "lan_cidrs", "git_user_name", "git_user_email", "network"):
            with self.subTest(key=key):
                d = self.with_()
                del d[key]
                self.ng(d, f"{key} がない")
        for key in ("password_hash", "ssh_authorized_keys"):
            with self.subTest(key=key):
                d = self.with_()
                del d["sysadmin"][key]
                self.ng(d, f"sysadmin.{key} がない")
        self.ng(self.with_(lan_cidrs=[]), "lan_cidrs が空")

    def test_change_me(self):
        self.ng(self.with_(hostname="CHANGE_ME"), "hostname に CHANGE_ME")
        self.ng(self.with_(agent_ssh_authorized_keys=["ssh-ed25519 CHANGE_ME"]), "agent_ssh_authorized_keys")

    def test_values(self):
        cases = [
            (dict(keyboard_layout="de"), "keyboard_layout は us か jp"),
            (dict(sysadmin={"password_hash": "plain", "ssh_authorized_keys": ["k"]}), "crypt 形式"),
            (dict(lan_cidrs=["192.0.2.0/33"]), "CIDR として読めない"),
            (dict(network={"mode": "auto"}), "network.mode は dhcp か static"),
            (dict(network={"mode": "static", "address": "192.0.2.10/24", "gateway": "192.0.2.1"}),
             "network.dns が要る"),
            (dict(network={"mode": "static", "address": "192.0.2.10", "gateway": "192.0.2.1",
                           "dns": ["192.0.2.53"]}), "プレフィックス付き"),
            (dict(network={"mode": "static", "address": "192.0.2.10/24", "gateway": "x",
                           "dns": ["192.0.2.53"]}), "network の値が読めない"),
            (dict(proxy={"url": "proxy:8080"}), "proxy.url"),
            (dict(ca_certs=["not a pem"]), "PEM の証明書"),
            (dict(editors=["emacs"]), "editors の emacs"),
            (dict(dev_ports=[80]), "dev_ports の 80"),
            (dict(dev_ports=["3000-3999"]), "dev_ports の 3000-3999"),
            (dict(agents=["aider"]), "agents の aider"),
            (dict(clouds=["oci"]), "clouds の oci"),
            (dict(editors=["vscode"], vscode_extensions=["no-dot"]), "発行者.名前"),
            (dict(editors=["zed"], zed_extensions=["Upper"]), "zed.dev の拡張機能の ID"),
            (dict(desktop_color="red"), "#RRGGBB"),
            (dict(gitea_url="gitea.example.internal"), "gitea_url"),
            (dict(notify={"slack_webhook_url": "https://example.com/hook"}), "hooks.slack.com"),
            (dict(notify={"ipmsg_to": ["a b"]}), "ipmsg_to"),
            (dict(notify={"ipmsg_broadcast": ["255.255.255.256"]}), "ipmsg_broadcast"),
        ]
        for kw, message in cases:
            with self.subTest(kw=kw):
                self.ng(self.with_(**kw), message)

    def test_extensions_need_editor(self):
        self.ng(self.with_(vscode_extensions=["ms-python.python"]), "editors に vscode")
        self.ng(self.with_(editors=["vscode"], zed_extensions=["toml"]), "editors に zed")


class TestStage(Case):
    def stage(self, *args):
        out = os.path.join(self.tmp.name, "stage")
        r = subprocess.run(["bash", STAGE, *args, out], capture_output=True, text=True)
        return r, out

    def test_layout_and_modes(self):
        info = os.path.join(self.tmp.name, "BUILD-INFO")
        with open(info, "w", encoding="utf-8") as f:
            f.write("tool='v0.0.0-test'\nconfig=''\nenv='env1.yaml'\nbuilt='2026-01-01T00:00:00+0900'\n")
        r, out = self.stage("--build-info", info, self.write(BASE))
        self.assertEqual(r.returncode, 0, r.stderr)
        stage = os.path.join(out, "agent-host")
        self.assertTrue(os.path.isfile(os.path.join(out, "autoinstall.yaml")))
        for name in ("provision.sh", "setup-provision.sh", "verify.sh", "env.sh", "agent_authorized_keys", "sysadmin_authorized_keys", "BUILD-INFO",
                     "lib/common.sh", "systemd/agent-host-provision.service", "notify/agent-notify",
                     "migrate/agent-host-backup", "migrate/agent-host-restore"):
            with self.subTest(name=name):
                self.assertTrue(os.path.exists(os.path.join(stage, name)), name)
        self.assertFalse(os.path.exists(os.path.join(stage, "render")))
        mode = lambda p: os.stat(os.path.join(stage, p)).st_mode & 0o777  # noqa: E731
        self.assertEqual(mode("env.sh"), 0o600)
        self.assertEqual(mode("agent_authorized_keys"), 0o600)
        self.assertEqual(mode("sysadmin_authorized_keys"), 0o600)
        self.assertEqual(mode("BUILD-INFO"), 0o644)
        self.assertEqual(mode("provision.sh"), 0o755)
        self.assertEqual(mode("notify/agent-notify"), 0o755)
        posts = sorted(os.listdir(os.path.join(stage, "post-install")))
        self.assertEqual(posts, sorted(os.listdir(os.path.join(REPO, "scripts", "post-install"))))
        for p in posts:
            self.assertEqual(mode(f"post-install/{p}"), 0o755, p)
        # BUILD-INFO はホストでシェルの変数として読み込む
        r = subprocess.run(["bash", "-c", f'. "{stage}/BUILD-INFO"; printf "%s|%s" "$tool" "$env"'],
                           capture_output=True, text=True)
        self.assertEqual(r.stdout, "v0.0.0-test|env1.yaml")

    def test_without_build_info(self):
        r, out = self.stage(self.write(BASE))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertFalse(os.path.exists(os.path.join(out, "agent-host", "BUILD-INFO")))

    def test_rejected_env_stops(self):
        r, _ = self.stage(self.write(self.with_(hostnmae="x")))
        self.assertNotEqual(r.returncode, 0)

    def test_missing_env(self):
        r, _ = self.stage(os.path.join(self.tmp.name, "nothing.yaml"))
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("がない", r.stderr)


if __name__ == "__main__":
    unittest.main()
