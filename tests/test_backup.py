"""移行の書き出し(agent-host-backup)が、作りなおせるものだけを除き、原本を除かないことの試験(Issue #4)。

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
        run("chown", "-R", "agent:agent", HOME)
        out = tempfile.mkdtemp()
        cls.archive = os.path.join(out, "backup.tar.zst")
        with open(cls.archive, "wb") as f:
            subprocess.run(["bash", os.path.join(REPO, "scripts", "migrate", "agent-host-backup")],
                           stdout=f, stderr=subprocess.PIPE, check=True)
        cls.members = set(run("tar", "--zstd", "-tf", cls.archive).stdout.splitlines())
        cls.manifest = run("tar", "--zstd", "-xOf", cls.archive, "agent-host-manifest.txt").stdout

    def has(self, path):
        p = path.lstrip("/")
        return any(m.rstrip("/") == p or m.startswith(p + "/") for m in self.members)

    def test_originals_are_kept(self):
        for path in (f"{WORK}/proj/dist/committed.txt", f"{WORK}/proj/dist/untracked.txt", f"{WORK}/proj/target",
                     f"{WORK}/proj/src/main.py", f"{WORK}/notes/dist/report.md",
                     f"{WORK}/proj/.git/refs/heads/dist", f"{WORK}/proj/.git/refs/heads/feature/target",
                     f"{HOME}/.config/orca/Preferences"):
            with self.subTest(path=path):
                self.assertTrue(self.has(path), path)

    def test_rebuildable_are_excluded(self):
        for path in (f"{WORK}/proj/node_modules", f"{WORK}/proj/src/__pycache__", f"{WORK}/proj/.venv",
                     f"{HOME}/.config/orca/Cache", f"{HOME}/.config/orca/Partitions/p/Code Cache"):
            with self.subTest(path=path):
                self.assertFalse(self.has(path), path)

    def test_manifest_lists_excluded(self):
        self.assertIn(f"excluded={WORK.lstrip('/')}/proj/node_modules", self.manifest)
        self.assertIn(f"excluded={WORK.lstrip('/')}/proj/.venv", self.manifest)


if __name__ == "__main__":
    unittest.main()
