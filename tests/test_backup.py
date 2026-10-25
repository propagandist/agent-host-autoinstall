"""移行の書き出し(agent-host-backup)が、作りなおせるものだけを除き、原本を除かないことの試験(Issue #4)と、
書き出しと取り込みが、利用者の置いたリンクをたどって root のファイルを読み書きしないことの試験(Issue #23)。

実物の scripts/migrate/agent-host-backup を root で動かすので、使い捨てのコンテナ(just test は Docker の中で root で動く)の
ときだけ実行する。/opt/agent-host/lib と agent ユーザーを作る。
"""
import os
import pwd
import shutil
import subprocess
import tempfile
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HOME = "/home/agent"
WORK = f"{HOME}/work"

IN_CONTAINER = os.path.exists("/.dockerenv") and os.geteuid() == 0 and shutil.which("git") and shutil.which("zstd")


def run(*args, **kw):
    return subprocess.run(args, check=True, capture_output=True, text=True, **kw)


def write(path, text="x\n"):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)


@unittest.skipUnless(IN_CONTAINER, "使い捨てのコンテナの中で root のときだけ(git と zstd も要る)")
class TestBackupExcludes(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        os.makedirs("/opt/agent-host/lib", exist_ok=True)
        shutil.copy(os.path.join(REPO, "scripts", "lib", "common.sh"), "/opt/agent-host/lib/common.sh")
        # 書き出しは env.sh の利用者(AH_USERS)全員の分を書く
        write("/opt/agent-host/env.sh", "AH_USERS=agent\n")
        write("/opt/agent-host/users/agent.env", "AH_USER_PORT=3389\n")
        try:
            pwd.getpwnam("agent")
        except KeyError:
            run("useradd", "--create-home", "--shell", "/bin/bash", "agent")
        shutil.rmtree(WORK, ignore_errors=True)
        proj = f"{WORK}/proj"
        git = ["git", "-C", proj, "-c", "user.name=t", "-c", "user.email=t@example.invalid"]
        write(f"{proj}/dist/committed.txt")
        write(f"{proj}/src/main.py")
        write(f"{proj}/target", "a file named target\n")
        run("git", "init", "-q", "-b", "main", proj)
        run(*git, "add", "-A")
        run(*git, "commit", "-q", "-m", "first")
        # push していないブランチ(名前が除外の名前と同じ)
        run(*git, "branch", "dist")
        run(*git, "branch", "feature/target")
        write(f"{proj}/dist/untracked.txt")
        # 作りなおせるもの
        write(f"{proj}/node_modules/left-pad/index.js")
        write(f"{proj}/src/__pycache__/main.cpython-314.pyc")
        write(f"{proj}/.venv/bin/python")
        # git 管理でないディレクトリの中の dist
        write(f"{WORK}/notes/dist/report.md")
        # Orca のキャッシュと設定
        write(f"{HOME}/.config/orca/Cache/data_0")
        write(f"{HOME}/.config/orca/Partitions/p/Code Cache/js/index")
        write(f"{HOME}/.config/orca/Preferences", "{}\n")
        # クラウドの CLI と Gitea CLI のログイン(Issue #7)
        write(f"{HOME}/.aws/config")
        write(f"{HOME}/.config/gcloud/credentials.db")
        write(f"{HOME}/.config/gcloud/logs/2026.10.25/x.log")
        write(f"{HOME}/.azure/msal_token_cache.json")
        write(f"{HOME}/.config/tea/config.yml")
        run("chown", "-R", "agent:agent", HOME)
        # 利用者が途中のディレクトリを、root だけが読めるディレクトリへのリンクにする(Issue #23)
        write("/srv/ah-secret/config.json", "ROOT-ONLY\n")
        os.chmod("/srv/ah-secret/config.json", 0o600)
        os.chmod("/srv/ah-secret", 0o700)
        run("runuser", "-u", "agent", "--", "ln", "-sfn", "/srv/ah-secret", f"{HOME}/.docker")
        out = tempfile.mkdtemp()
        cls.archive = os.path.join(out, "backup.tar.zst")
        with open(cls.archive, "wb") as f:
            subprocess.run(["bash", os.path.join(REPO, "scripts", "migrate", "agent-host-backup")],
                           stdout=f, stderr=subprocess.PIPE, check=True)
        # 書き出しは root の tar のあとに利用者ごとの tar が続くので、-i で全部を読む
        cls.members = set(run("tar", "--zstd", "-i", "-tf", cls.archive).stdout.splitlines())
        cls.manifest = run("tar", "--zstd", "-i", "-xOf", cls.archive, "agent-host-manifest.txt").stdout
        cls.contents = subprocess.run(["tar", "--zstd", "-i", "-xOf", cls.archive], check=True, capture_output=True).stdout

    def has(self, path):
        p = path.lstrip("/")
        return any(m.rstrip("/") == p or m.startswith(p + "/") for m in self.members)

    def test_originals_are_kept(self):
        for path in (f"{WORK}/proj/dist/committed.txt", f"{WORK}/proj/dist/untracked.txt", f"{WORK}/proj/target",
                     f"{WORK}/proj/src/main.py", f"{WORK}/notes/dist/report.md",
                     f"{WORK}/proj/.git/refs/heads/dist", f"{WORK}/proj/.git/refs/heads/feature/target",
                     f"{HOME}/.config/orca/Preferences", f"{HOME}/.aws/config",
                     f"{HOME}/.config/gcloud/credentials.db", f"{HOME}/.azure/msal_token_cache.json",
                     f"{HOME}/.config/tea/config.yml"):
            with self.subTest(path=path):
                self.assertTrue(self.has(path), path)

    def test_rebuildable_are_excluded(self):
        for path in (f"{WORK}/proj/node_modules", f"{WORK}/proj/src/__pycache__", f"{WORK}/proj/.venv",
                     f"{HOME}/.config/orca/Cache", f"{HOME}/.config/orca/Partitions/p/Code Cache",
                     f"{HOME}/.config/gcloud/logs"):
            with self.subTest(path=path):
                self.assertFalse(self.has(path), path)

    def test_manifest_lists_users(self):
        # 取り込みは利用者ごとに UID を比べ、このホストにいない人の分を除く
        self.assertIn(f"uid.agent={pwd.getpwnam('agent').pw_uid}", self.manifest)
        self.assertIn("home.agent=home/agent", self.manifest)

    def test_root_only_file_behind_link_is_not_read(self):
        # ホームの分は利用者の権限で読むので、リンクの先の root だけが読めるファイルは入らない(Issue #23)
        self.assertFalse(self.has(f"{HOME}/.docker/config.json"))
        self.assertNotIn(b"ROOT-ONLY", self.contents)

    def test_manifest_lists_excluded(self):
        self.assertIn(f"excluded={WORK.lstrip('/')}/proj/node_modules", self.manifest)
        self.assertIn(f"excluded={WORK.lstrip('/')}/proj/.venv", self.manifest)


def restore(archive):
    with open(archive, "rb") as f:
        return subprocess.run(["bash", os.path.join(REPO, "scripts", "migrate", "agent-host-restore")],
                              stdin=f, capture_output=True, text=True)


@unittest.skipUnless(IN_CONTAINER, "使い捨てのコンテナの中で root のときだけ(git と zstd も要る)")
class TestRestore(unittest.TestCase):
    """取り込みが、ホームの分を利用者の権限で展開すること(Issue #23)。"""

    @classmethod
    def setUpClass(cls):
        TestBackupExcludes.setUpClass()
        cls.archive = TestBackupExcludes.archive
        write("/var/lib/agent-host/provisioned", "")

    def setUp(self):
        shutil.rmtree("/srv/ah-out", ignore_errors=True)
        os.makedirs("/srv/ah-out", mode=0o755)

    def test_restored_as_user(self):
        shutil.rmtree(f"{HOME}/.aws")
        r = restore(self.archive)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(os.path.exists(f"{HOME}/.aws/config"))
        self.assertEqual(pwd.getpwuid(os.stat(f"{HOME}/.aws/config").st_uid).pw_name, "agent")

    def test_existing_relative_link_is_not_followed(self):
        # 取り込む前のホームに、ホームの外を指す相対パスのリンクがあっても、その先に書かない。
        # 書庫に項目のある ~/.config/tea などは tar がリンクを置き換えるので、項目のない ~/.config をリンクにする
        os.rename(f"{HOME}/.config", f"{HOME}/.config.keep")
        try:
            run("runuser", "-u", "agent", "--", "ln", "-sfn", "../../srv/ah-out", f"{HOME}/.config")
            restore(self.archive)
            self.assertEqual(os.listdir("/srv/ah-out"), [])
        finally:
            os.remove(f"{HOME}/.config")
            os.rename(f"{HOME}/.config.keep", f"{HOME}/.config")

    def test_old_format_is_restored_as_user(self):
        # v0.2.0 までの書き出し(記録は agent_uid= だけ。ホームの分も root の tar の中)も、利用者の権限で取り込む
        src = tempfile.mkdtemp()
        write(f"{src}/agent-host-manifest.txt",
              f"hostname=old\nagent_uid={pwd.getpwnam('agent').pw_uid}\npath=home/agent/.legacy\n")
        write(f"{src}/home/agent/.legacy/file", "old\n")
        archive = os.path.join(src, "old.tar.zst")
        run("tar", "--zstd", "-cf", archive, "-C", src, "agent-host-manifest.txt", "home/agent/.legacy")
        shutil.rmtree(f"{HOME}/.legacy", ignore_errors=True)
        r = restore(archive)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(pwd.getpwuid(os.stat(f"{HOME}/.legacy/file").st_uid).pw_name, "agent")


if __name__ == "__main__":
    unittest.main()
