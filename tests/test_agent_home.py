"""agent のホームへの書き込みが、agent の置いたリンクをたどってホームの外を変えないことの試験(Issue #1)。

scripts/lib/common.sh の write_agent_file・ini_set --as-agent・agent_run を、実際に agent ユーザーを作って動かす。
ユーザーを作るので、使い捨てのコンテナ(just test は Docker の中で root で動く)のときだけ実行する。
"""
import os
import pwd
import subprocess
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COMMON = os.path.join(REPO, "scripts", "lib", "common.sh")
HOME = "/home/agent"

IN_CONTAINER = os.path.exists("/.dockerenv") and os.geteuid() == 0


def sh(script, stdin=""):
    """common.sh を読み込んだ root の bash で、agent を「いま構成している利用者」にして動かす。"""
    return subprocess.run(["bash", "-c", f'set -uo pipefail; . "{COMMON}"; AGENT_USER=agent AGENT_HOME={HOME}; {script}'],
                          input=stdin, capture_output=True, text=True)


@unittest.skipUnless(IN_CONTAINER, "使い捨てのコンテナの中で root のときだけ(ユーザーを作るため)")
class TestAgentHome(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        try:
            pwd.getpwnam("agent")
        except KeyError:
            subprocess.run(["useradd", "--create-home", "--shell", "/bin/bash", "agent"], check=True)

    def setUp(self):
        subprocess.run(["rm", "-rf", f"{HOME}/.config", "/srv/ah-target", "/srv/ah-dir"], check=True)
        subprocess.run(["runuser", "-u", "agent", "--", "mkdir", "-p", f"{HOME}/.config"], check=True)
        # ホームの外の root のファイルとディレクトリ(書き換えられてはいけないもの)
        with open("/srv/ah-target", "w") as f:
            f.write("original\n")
        os.chmod("/srv/ah-target", 0o600)
        os.makedirs("/srv/ah-dir", mode=0o755)

    def agent_link(self, target, link):
        subprocess.run(["runuser", "-u", "agent", "--", "ln", "-sfn", target, link], check=True)

    def assert_target_untouched(self):
        with open("/srv/ah-target") as f:
            self.assertEqual(f.read(), "original\n")
        st = os.stat("/srv/ah-target")
        self.assertEqual((st.st_uid, st.st_mode & 0o777), (0, 0o600))
        self.assertEqual(os.listdir("/srv/ah-dir"), [])

    def test_write_agent_file_leaf_link(self):
        link = f"{HOME}/.config/leaf.conf"
        self.agent_link("/srv/ah-target", link)
        r = sh(f'write_agent_file 644 "{link}"', "new\n")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assert_target_untouched()
        # リンクは agent のふつうのファイルに置き換わる
        self.assertFalse(os.path.islink(link))
        self.assertEqual(pwd.getpwuid(os.stat(link).st_uid).pw_name, "agent")
        with open(link) as f:
            self.assertEqual(f.read(), "new\n")

    def test_write_agent_file_parent_link(self):
        self.agent_link("/srv/ah-dir", f"{HOME}/.config/environment.d")
        r = sh(f'write_agent_file 644 "{HOME}/.config/environment.d/63-aws.conf"', "AWS_PAGER=\n")
        self.assertNotEqual(r.returncode, 0)
        self.assert_target_untouched()

    def test_ini_set_as_agent_leaf_link(self):
        link = f"{HOME}/.config/mimeapps.list"
        self.agent_link("/srv/ah-target", link)
        r = sh(f'ini_set --as-agent "{link}" "Default Applications" text/html google-chrome.desktop')
        self.assertNotEqual(r.returncode, 0)
        self.assert_target_untouched()

    def test_agent_run_append_leaf_link(self):
        link = f"{HOME}/.config/bashrc"
        self.agent_link("/srv/ah-target", link)
        r = sh(f"""printf 'x\\n' | agent_run sh -c 'cat >>"$1"' sh "{link}" """)
        self.assertNotEqual(r.returncode, 0)
        self.assert_target_untouched()

    def test_ini_set_as_agent_normal_file(self):
        path = f"{HOME}/.config/mimeapps.list"
        r = sh(f"""printf '[Default Applications]\\n' | write_agent_file 644 "{path}" &&
                   ini_set --as-agent "{path}" "Default Applications" text/html google-chrome.desktop""")
        self.assertEqual(r.returncode, 0, r.stderr)
        with open(path) as f:
            self.assertIn("text/html=google-chrome.desktop", f.read())
        self.assertEqual(pwd.getpwuid(os.stat(path).st_uid).pw_name, "agent")


if __name__ == "__main__":
    unittest.main()
