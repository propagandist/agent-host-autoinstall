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
    "lan_cidrs": ["192.0.2.0/24"],
    "users": [{
        "name": "alice", "port": 3389,
        "rdp": {"username": "rdp", "initial_password": "rdp-password"},
        "git_user_name": "alice", "git_user_email": "alice@example.invalid",
    }],
}


def user(name, port, **kw):
    """users の 1 人(通る最小の値)。"""
    u = {"name": name, "port": port, "rdp": {"username": name, "initial_password": f"{name}-password"},
         "git_user_name": name, "git_user_email": f"{name}@example.invalid"}
    u.update(kw)
    return u


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
        self.assertEqual(env["AH_USERS"], "alice")
        self.assertNotIn("AH_RDP_INITIAL_PASSWORD", env)  # 利用者ごとの値は users/ に分ける
        alice = read_env_sh(os.path.join(out, "users", "alice.env"))
        self.assertEqual(alice["AH_USER_PORT"], "3389")
        self.assertEqual(alice["AH_RDP_USER"], "rdp")
        self.assertEqual(alice["AH_RDP_INITIAL_PASSWORD"], "rdp-password")
        self.assertEqual(alice["AH_GIT_USER_EMAIL"], "alice@example.invalid")
        with open(os.path.join(out, "users", "alice.authorized_keys"), encoding="utf-8") as f:
            self.assertEqual(f.read(), "")
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
        filled = yaml.safe_load(yaml.safe_dump(example).replace("AAAA_CHANGE_ME", "AAAAx").replace("CHANGE_ME", "x"))
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
            vm=True,
            dev_ports=[3000, "8000:8099"],
            desktop_color="#123abc",
            gitea_url="https://gitea.example.internal/",
            proxy={"url": "http://proxy.example.internal:8080"},
            notify={"slack_webhook_url": "https://hooks.slack.com/services/x",
                    "ipmsg_to": ["someone", "192.0.2.20"], "ipmsg_broadcast": ["192.0.2.255"]},
            ca_certs=["-----BEGIN CERTIFICATE-----\nAAAA\n-----END CERTIFICATE-----\n"],
            users=[user("alice", 3389, ssh_authorized_keys=["ssh-ed25519 AAAAalice alice@test"]), user("bob", 3390)],
        )))
        env = read_env_sh(os.path.join(out, "env.sh"))
        self.assertEqual(env["AH_EDITORS"], "vscode zed neovim")
        self.assertEqual(env["AH_VSCODE_EXTENSIONS"], "hashicorp.terraform@2.40.0 ms-python.python")
        self.assertEqual(env["AH_CLOUDS"], "aws gcp azure")
        self.assertEqual(env["AH_VM"], "1")
        self.assertEqual(env["AH_DEV_PORTS"], "3000 8000:8099")
        self.assertEqual(env["AH_GITEA_URL"], "https://gitea.example.internal")  # 末尾の / は落とす
        self.assertEqual(env["AH_IPMSG_TO"], "someone 192.0.2.20")
        self.assertEqual(env["AH_UPS_MODE"], "none")  # 書かなければ使わない
        with open(os.path.join(out, "autoinstall.yaml"), encoding="utf-8") as f:
            self.assertEqual(yaml.safe_load(f)["autoinstall"]["proxy"], "http://proxy.example.internal:8080")
        self.assertEqual(env["AH_USERS"], "alice bob")
        with open(os.path.join(out, "users", "alice.authorized_keys"), encoding="utf-8") as f:
            self.assertEqual(f.read(), "ssh-ed25519 AAAAalice alice@test\n")
        self.assertEqual(read_env_sh(os.path.join(out, "users", "bob.env"))["AH_USER_PORT"], "3390")
        with open(os.path.join(out, "ca", "agent-host-01.crt"), encoding="utf-8") as f:
            self.assertTrue(f.read().startswith("-----BEGIN CERTIFICATE-----"))

    def test_shell_quoting(self):
        # 単一引用符や $ を含む値でも、env.sh を読み込んだ値がそのまま戻ること
        pw = "it's $HOME `x` \"y\""
        u = user("alice", 3389)
        u["rdp"]["initial_password"] = pw
        out = self.ok(self.write(self.with_(users=[u])))
        r = subprocess.run(["bash", "-c", f'. "{out}/users/alice.env"; printf %s "$AH_RDP_INITIAL_PASSWORD"'],
                           capture_output=True, text=True)
        self.assertEqual(r.stdout, pw)


class TestUpdateScope(Case):
    """just update で反映される範囲の表(Issue #13)。"""

    def load(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location("render", RENDER)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod

    def test_every_key_is_classified(self):
        mod = self.load()
        self.assertEqual(set(mod.UPDATE_SCOPE), set(mod.KNOWN_KEYS))
        self.assertTrue(set(mod.UPDATE_SCOPE.values()) <= {"update", "relogin", "install"})

    def test_install_only_keys_do_not_reach_the_host(self):
        # インストールのときだけ効く項目(hostname は update の照合にだけ使う)は、env.sh に値として出ない
        out = self.ok(self.write(self.with_(keyboard_layout="jp", network={"mode": "dhcp", "interface": "enp9s0"})))
        with open(os.path.join(out, "env.sh"), encoding="utf-8") as f:
            text = f.read()
        self.assertNotIn("KEYBOARD", text)
        self.assertNotIn("enp9s0", text)


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
        common_notify = self.write({"notify": {"slack_webhook_url": "https://hooks.slack.com/services/x"}})
        host = self.write({"hostname": "agent-host-02", "editors": ["neovim"],
                           "notify": {"ipmsg_to": ["someone"]}, "users": [user("bob", 3390)]})
        out = self.ok(common, common_notify, host)
        env = read_env_sh(os.path.join(out, "env.sh"))
        self.assertEqual(env["AH_HOSTNAME"], "agent-host-02")
        self.assertEqual(env["AH_EDITORS"], "neovim")         # 並びは置き換える
        self.assertEqual(env["AH_USERS"], "bob")              # users も並びごと置き換える
        self.assertFalse(os.path.exists(os.path.join(out, "users", "alice.env")))
        self.assertEqual(env["AH_SLACK_WEBHOOK_URL"], "https://hooks.slack.com/services/x")  # 辞書はキーごとに重ねる
        self.assertEqual(env["AH_IPMSG_TO"], "someone")

    def test_empty_file(self):
        self.ok(self.write(BASE), self.write(None, text=""))


class TestFleetExample(unittest.TestCase):
    """構成リポジトリのひな形(examples/fleet)で、秘密の値が SOPS の暗号化の対象に入っているか(#27)"""

    def test_secret_keys_are_encrypted(self):
        import glob
        import re
        fleet = os.path.join(REPO, "examples", "fleet")
        with open(os.path.join(fleet, ".sops.yaml"), encoding="utf-8") as f:
            rules = yaml.safe_load(f)["creation_rules"]
        pattern = re.compile(rules[0]["encrypted_regex"])

        def keys(node):
            if isinstance(node, dict):
                for k, v in node.items():
                    yield k
                    yield from keys(v)
            elif isinstance(node, list):
                for v in node:
                    yield from keys(v)

        files = [os.path.join(fleet, "common.yaml")] + glob.glob(os.path.join(fleet, "hosts", "*.yaml"))
        found = set()
        for path in files:
            with open(path, encoding="utf-8") as f:
                found |= set(keys(yaml.safe_load(f)))
        # ひな形に書いていない秘密の値(UPS の password など)も、名前で一致させる
        secrets = {k for k in found if "password" in k or "webhook" in k} | {"password", "slack_webhook_url"}
        self.assertIn("initial_password", secrets)
        for k in sorted(secrets):
            with self.subTest(key=k):
                self.assertRegex(k, pattern)
        for k in ("username", "port", "name"):
            with self.subTest(key=k):
                self.assertNotRegex(k, pattern)

    def test_path_regex_matches_windows_paths(self):
        """Windows の sops はパスを \\ で区切って照らすので、hosts\\<ホスト>.yaml にも規則が当たること(#34)"""
        import re
        with open(os.path.join(REPO, "examples", "fleet", ".sops.yaml"), encoding="utf-8") as f:
            pattern = re.compile(yaml.safe_load(f)["creation_rules"][0]["path_regex"])
        for path in ("common.yaml", "hosts/agent-host-01.yaml", "hosts\\agent-host-01.yaml",
                     "/repo/hosts/agent-host-01.yaml", "C:\\repo\\hosts\\agent-host-01.yaml", "C:\\repo\\common.yaml"):
            with self.subTest(path=path):
                self.assertRegex(path, pattern)
        for path in ("hosts/sub/x.yaml", "hosts\\sub\\x.yaml", "facts/agent-host-01.yaml", "mycommon.yaml"):
            with self.subTest(path=path):
                self.assertNotRegex(path, pattern)


class TestRejected(Case):
    def test_unknown_key(self):
        self.ng(self.with_(hostnmae="x"), "hostnmae は知らないキー")

    def test_unknown_subkey(self):
        self.ng(self.with_(notify={"slack": "x"}), "notify.slack は知らないキー")
        self.ng(self.with_(users=[user("alice", 3389, shell="/bin/zsh")]), "1 人目の shell は知らないキー")
        u = user("alice", 3389)
        u["rdp"]["domain"] = "x"
        self.ng(self.with_(users=[u]), "1 人目の rdp.domain は知らないキー")

    def test_old_keys(self):
        # 0.3.0 で users に移ったキーは、書き換え方を出して止める
        for key, value, message in (
            ("rdp", {"username": "rdp", "password": "p"}, "users[].rdp"),
            ("git_user_name", "x", "users[].git_user_name"),
            ("git_user_email", "x@example.invalid", "users[].git_user_email"),
            ("agent_ssh_authorized_keys", [], "users[].ssh_authorized_keys"),
        ):
            with self.subTest(key=key):
                self.ng(self.with_(**{key: value}), f"{key} は 0.3.0 で {message}")
        u = user("alice", 3389)
        u["rdp"] = {"username": "rdp", "password": "p"}
        self.ng(self.with_(users=[u]), "rdp.password は rdp.initial_password にする")

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
        for key in ("hostname", "keyboard_layout", "lan_cidrs", "network"):
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
        self.ng(self.with_(users=[]), "users がない")
        d = self.with_()
        del d["users"]
        self.ng(d, "users がない")

    def test_change_me(self):
        self.ng(self.with_(hostname="CHANGE_ME"), "hostname に CHANGE_ME")
        self.ng(self.with_(users=[user("alice", 3389, ssh_authorized_keys=["ssh-ed25519 CHANGE_ME"])]),
                "alice の ssh_authorized_keys に CHANGE_ME")
        u = user("alice", 3389)
        u["rdp"]["initial_password"] = "CHANGE_ME"
        self.ng(self.with_(users=[u]), "alice の rdp.initial_password に CHANGE_ME")

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

    def test_types_and_forms(self):
        # 型の誤りで 1 文字ずつに分かれたり、通っても構成が止まったりしていたもの(Issue #8)
        cases = [
            (dict(sysadmin={"password_hash": "$6$salt$hash", "ssh_authorized_keys": "ssh-ed25519 AAAAtest a@b"}),
             "sysadmin.ssh_authorized_keys は並び"),
            (dict(ntp_servers="ntp.example.internal"), "ntp_servers は並び"),
            (dict(users=[user("alice", 3389, ssh_authorized_keys="ssh-ed25519 AAAAtest a@b")]),
             "1 人目の ssh_authorized_keys は並び"),
            (dict(lan_cidrs="192.0.2.0/24"), "lan_cidrs は並び"),
            (dict(network=["dhcp"]), "network はキーと値"),
            (dict(users=[user("alice", "3389")]), "1 人目の port は数"),
            (dict(users=[user("alice", True)]), "1 人目の port は数"),
            (dict(users=["alice"]), "users の 'alice' はキーと値"),
            (dict(users={"name": "alice"}), "users は並び"),
            (dict(lan_cidrs=[1]), "lan_cidrs の 1 は文字列"),
            (dict(hostname="bad host/name"), "hostname は英数字と -"),
            (dict(hostname="agent-host.example.internal"), "hostname は英数字と -"),
            (dict(sysadmin={"password_hash": "$", "ssh_authorized_keys": ["ssh-ed25519 AAAAtest a@b"]}), "crypt 形式"),
            (dict(sysadmin={"password_hash": "$1$md5$x", "ssh_authorized_keys": ["ssh-ed25519 AAAAtest a@b"]}), "crypt 形式"),
            (dict(sysadmin={"password_hash": "$6$salt$hash", "ssh_authorized_keys": ["not a key"]}), "SSH の公開鍵"),
            (dict(users=[user("alice", 3389, ssh_authorized_keys=["ssh-ed25519"])]), "SSH の公開鍵"),
            (dict(dev_ports=["4000:3000"]), "始め:終わり の順"),
            (dict(notify={"ipmsg_broadcast": ["::1"]}), "IPv4"),
            (dict(vm="true"), "vm は真偽値"),
            (dict(vm=1), "vm は真偽値"),
        ]
        for kw, message in cases:
            with self.subTest(kw=kw):
                self.ng(self.with_(**kw), message)
        # 通るもの: 数のポート、yescrypt のハッシュ、ecdsa の鍵、vm の false(書かないときと同じ)
        out = self.ok(self.write(self.with_(dev_ports=[3000, "8000:8099"],
                                      sysadmin={"password_hash": "$y$j9T$salt$hash",
                                                "ssh_authorized_keys": ["ecdsa-sha2-nistp256 AAAAE2Vj= a@b"]},
                                      vm=False)))
        self.assertEqual(read_env_sh(os.path.join(out, "env.sh"))["AH_VM"], "0")

    def test_users(self):
        def u(**kw):
            d = user("alice", 3389)
            d.update(kw)
            return d
        cases = [
            ([u(name="Alice")], "name は英小文字で始まり"),
            ([u(name="1alice")], "name は英小文字で始まり"),
            ([u(name="a" * 33)], "name は英小文字で始まり"),
            ([u(name="sysadmin")], "sysadmin はシステムが使う名前"),
            ([u(name="root")], "root はシステムが使う名前"),
            ([u(), user("alice", 3390)], "name の alice が重なっている"),
            ([{k: v for k, v in u().items() if k != "port"}], "alice に port がない"),
            ([u(port=80)], "port の 80 は 1024〜65535"),
            ([u(), user("bob", 3389)], "port の 3389 が重なっている"),
            ([u(git_user_email="")], "alice に git_user_email がない"),
            ([{**u(), "rdp": {"username": "alice"}}], "alice に rdp.initial_password がない"),
        ]
        for users, message in cases:
            with self.subTest(users=users):
                self.ng(self.with_(users=users), message)
        self.ng(self.with_(users=[user("alice", 3005)], dev_ports=["3000:3999"]), "dev_ports と重なっている")
        self.ng(self.with_(users=[user("alice", 5173)], dev_ports=[5173]), "dev_ports と重なっている")
        # 通るもの: - を含む名前、並べ替え(ポートは名前に付いたまま)
        out = self.ok(self.write(self.with_(users=[user("bob-2", 3390), user("alice", 3389)])))
        self.assertEqual(read_env_sh(os.path.join(out, "env.sh"))["AH_USERS"], "bob-2 alice")
        self.assertEqual(read_env_sh(os.path.join(out, "users", "alice.env"))["AH_USER_PORT"], "3389")

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
        for name in ("provision.sh", "setup-provision.sh", "verify.sh", "env.sh", "users/alice.env",
                     "users/alice.authorized_keys", "sysadmin_authorized_keys", "BUILD-INFO",
                     "lib/common.sh", "systemd/agent-host-provision.service", "notify/agent-notify",
                     "migrate/agent-host-backup", "migrate/agent-host-restore"):
            with self.subTest(name=name):
                self.assertTrue(os.path.exists(os.path.join(stage, name)), name)
        self.assertFalse(os.path.exists(os.path.join(stage, "render")))
        mode = lambda p: os.stat(os.path.join(stage, p)).st_mode & 0o777  # noqa: E731
        self.assertEqual(mode("env.sh"), 0o600)
        self.assertEqual(mode("users"), 0o700)
        self.assertEqual(mode("users/alice.env"), 0o600)
        self.assertEqual(mode("users/alice.authorized_keys"), 0o600)
        self.assertEqual(mode("sysadmin_authorized_keys"), 0o600)
        self.assertEqual(mode("BUILD-INFO"), 0o644)
        self.assertEqual(mode("provision.sh"), 0o755)
        self.assertEqual(mode("notify/agent-notify"), 0o755)
        posts = sorted(os.listdir(os.path.join(stage, "post-install")))
        self.assertEqual(posts, sorted(os.listdir(os.path.join(REPO, "scripts", "post-install"))))
        for p in posts:
            # スクリプトは実行できる。Mozc のキーの割り当ての表(mozc-keymap.tsv)はデータ。
            # どちらも stage.sh がそろえる(Windows の Docker では、写したファイルがすべて 777 に見える)
            self.assertEqual(mode(f"post-install/{p}"), 0o644 if p.endswith(".tsv") else 0o755, p)
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
