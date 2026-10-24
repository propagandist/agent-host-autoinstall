"""agent-notify が、実行するユーザーの HOME に書けなくても通知を送ることの試験(Issue #5)。

UPS の netclient では、upsmon が nut で agent-notify を呼ぶが、nut の HOME(/var/lib/nut)が無いことがあった。
/etc/agent-host/notify.env を書くので、使い捨てのコンテナ(just test は Docker の中で root で動く)のときだけ実行する。
"""
import http.server
import json
import os
import subprocess
import threading
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NOTIFY = os.path.join(REPO, "scripts", "notify", "agent-notify")
IN_CONTAINER = os.path.exists("/.dockerenv") and os.geteuid() == 0


class Hook(http.server.BaseHTTPRequestHandler):
    received = []

    def do_POST(self):
        Hook.received.append(json.loads(self.rfile.read(int(self.headers["Content-Length"]))))
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok")

    def log_message(self, *args):
        pass


@unittest.skipUnless(IN_CONTAINER, "使い捨てのコンテナの中で root のときだけ(/etc/agent-host を書くため)")
class TestNotifyWithoutHome(unittest.TestCase):
    def setUp(self):
        self.server = http.server.HTTPServer(("127.0.0.1", 0), Hook)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        os.makedirs("/etc/agent-host", exist_ok=True)
        with open("/etc/agent-host/notify.env", "w") as f:
            f.write(f"SLACK_WEBHOOK_URL=http://127.0.0.1:{self.server.server_port}/hook\nIPMSG_TO=\n")
        os.chmod("/etc/agent-host/notify.env", 0o644)
        Hook.received.clear()

    def tearDown(self):
        self.server.shutdown()

    def test_sends_when_home_is_missing(self):
        # nobody の HOME は /nonexistent(作れない)。upsmon と同じく HOME を外し、passwd の HOME に解決させる
        r = subprocess.run(["runuser", "-u", "nobody", "--", "env", "-u", "HOME", "python3", NOTIFY,
                            "error", "停電: UPS のバッテリーで動いている", "試験"], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(len(Hook.received), 1, r.stderr)
        self.assertIn("停電", Hook.received[0]["text"])


if __name__ == "__main__":
    unittest.main()
