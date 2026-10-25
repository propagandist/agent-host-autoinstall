"""scripts/local/envs.sh の一時ディレクトリが、並行に動かしても混ざらないことの試験(Issue #9)。

2 つの bash で envs.sh を読み込み、同じファイル名(env.yaml)の別々の内容を写して、寿命を重ねる。
"""
import os
import subprocess
import tempfile
import time
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENVS = os.path.join(REPO, "scripts", "local", "envs.sh")


class TestRunDir(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        # build/ はリポジトリの直下に作られるので、作業ディレクトリをリポジトリの複製にしない(build だけ別に用意する)
        self.work = os.path.join(self.tmp.name, "work")
        os.makedirs(self.work)
        for host in ("host-a", "host-b"):
            d = os.path.join(self.tmp.name, host)
            os.makedirs(d)
            with open(os.path.join(d, "env.yaml"), "w") as f:
                f.write(f"hostname: {host}\n")

    def start(self, host, hold):
        script = f'''
            set -euo pipefail
            . "{ENVS}"
            copy_envs "{self.tmp.name}/{host}/env.yaml"
            write_build_info "{self.tmp.name}/{host}/env.yaml"
            echo "$RUN_DIR"
            sleep {hold}
            cat "${{ENV_FILES[0]}}"
            test -f "$RUN_DIR/BUILD-INFO"
        '''
        return subprocess.Popen(["bash", "-c", script], cwd=self.work, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, text=True)

    def test_parallel_runs_do_not_mix(self):
        a = self.start("host-a", 2)
        time.sleep(0.5)
        b = self.start("host-b", 0)
        out_b, err_b = b.communicate(timeout=30)
        out_a, err_a = a.communicate(timeout=30)
        self.assertEqual(a.returncode, 0, err_a)
        self.assertEqual(b.returncode, 0, err_b)
        self.assertIn("hostname: host-a", out_a)
        self.assertIn("hostname: host-b", out_b)
        run_a, run_b = out_a.splitlines()[0], out_b.splitlines()[0]
        self.assertNotEqual(run_a, run_b)
        # 終わったら一時ディレクトリは消える
        self.assertEqual([d for d in os.listdir(os.path.join(self.work, "build")) if d.startswith(".run.")], [])


class TestFleetWithEnv(unittest.TestCase):
    """構成リポジトリのひな形の with-env.sh も、実行ごとに復号先を分けること(Issue #9)。"""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.fleet = self.tmp.name
        os.makedirs(os.path.join(self.fleet, "hosts"))
        with open(os.path.join(self.fleet, "common.yaml"), "w") as f:
            f.write("keyboard_layout: us\n")
        with open(os.path.join(self.fleet, "hosts", "agent-host-01.yaml"), "w") as f:
            f.write("hostname: agent-host-01\n")
        self.with_env = os.path.join(REPO, "examples", "fleet", "scripts", "with-env.sh")

    def start(self, hold):
        # with-env.sh は、コマンドの後ろに復号した 2 つのパスを足す。待ってから自分の入力を読む
        cmd = f'sleep {hold}; cat "$1" "$2"; echo "$1"'
        return subprocess.Popen(["bash", self.with_env, "agent-host-01", "bash", "-c", cmd, "_"], cwd=self.fleet,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    def test_same_host_in_parallel(self):
        a = self.start(2)
        time.sleep(0.5)
        b = self.start(0)
        out_b, err_b = b.communicate(timeout=30)
        out_a, err_a = a.communicate(timeout=30)
        self.assertEqual(b.returncode, 0, err_b)
        self.assertEqual(a.returncode, 0, err_a)  # 後から動いたほうが終わっても、先のほうの入力は残っている
        for out in (out_a, out_b):
            self.assertIn("hostname: agent-host-01", out)
        self.assertNotEqual(out_a.splitlines()[-1], out_b.splitlines()[-1])
        self.assertEqual(os.listdir(os.path.join(self.fleet, "build", ".dec")), [])


if __name__ == "__main__":
    unittest.main()
