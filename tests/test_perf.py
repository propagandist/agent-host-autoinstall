"""agent-host-perf の試験。疑似の /sys・/proc と、匿名にした sadf・fio・sysbench の出力を使う(ホストは要らない)。"""
import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
import shutil
import stat
import tempfile
import time
import unittest
from unittest import mock

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOL = os.path.join(REPO, "scripts", "perf", "agent-host-perf")
_loader = importlib.machinery.SourceFileLoader("agent_host_perf", TOOL)
_spec = importlib.util.spec_from_loader("agent_host_perf", _loader)
perf = importlib.util.module_from_spec(_spec)
_loader.exec_module(perf)

DAY = 86400
SECRET_HOST = "secret-host-name"
FIO_JSON = json.dumps({"jobs": [{
    "error": 0,
    "read": {"iops": 131.5, "bw_bytes": 157286400, "clat_ns": {"percentile": {"99.000000": 25000000}}},
    "write": {"iops": 55.25, "bw_bytes": 104857600, "clat_ns": {"percentile": {"99.000000": 90624}}},
    "sync": {"total_ios": 10, "lat_ns": {"percentile": {"99.000000": 717225984}}},
}]})
SYSBENCH_CPU = "CPU speed:\n    events per second:  1136.72\n"
SYSBENCH_MEM = "42025.00 MiB transferred (20996.59 MiB/sec)\n"
DMIDECODE = """Handle 0x0040, DMI type 17
Memory Device
\tSize: 8 GB
\tSpeed: 1600 MT/s
\tSerial Number: SECRET-SERIAL
\tConfigured Memory Speed: 1333 MT/s

Handle 0x0041, DMI type 17
Memory Device
\tSize: No Module Installed
\tSpeed: Unknown
"""


def sadf_json(day, t_text="00:10:00", date_text=None):
    return json.dumps({"sysstat": {"hosts": [{
        "nodename": SECRET_HOST, "file-date": day,
        "statistics": [{
            "timestamp": {"date": date_text or day, "time": t_text, "tz": "UTC", "interval": 600},
            "cpu-load": [{"cpu": "all", "idle": 90.0, "iowait": 1.5}],
            "memory": {"avail": 2 * 1024**2, "swpused-percent": 3.0},
            "queue": {"ldavg-1": 0.5},
            "disk": [{"disk-device": "sda", "await": 20.0, "util-percent": 4.0},
                     {"disk-device": "zram0", "await": 0.0, "util-percent": 0.0},
                     {"disk-device": "dm-0", "await": 9.0, "util-percent": 4.0}],
            "psi": {"psi-cpu": {"some_avg": 0.3}, "psi-io": {"some_avg": 1.5}, "psi-mem": {"some_avg": 0.0}},
        }],
    }]}})


class PerfCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp)
        self.root = f"{self.tmp}/root"
        self.dir = f"{self.tmp}/data"
        self.sa = f"{self.tmp}/sa"
        self.bin = f"{self.tmp}/bin"
        for d in (self.root, self.sa, self.bin):
            os.makedirs(d)
        self.addCleanup(os.umask, os.umask(0o022))
        patcher = mock.patch.dict(os.environ, {"PATH": f"{self.bin}:{os.environ['PATH']}"})
        patcher.start()
        self.addCleanup(patcher.stop)

    def put(self, rel, text):
        path = f"{self.root}/{rel}"
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)

    def fake_cmd(self, name, script):
        path = f"{self.bin}/{name}"
        with open(path, "w", encoding="utf-8") as f:
            f.write("#!/bin/sh\n" + script + "\n")
        os.chmod(path, os.stat(path).st_mode | stat.S_IEXEC)

    def run_tool(self, *args):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = perf.main(["--root", self.root, "--dir", self.dir, "--sa-dir", self.sa, *args])
        return code, out.getvalue(), err.getvalue()

    def report(self, *args):
        code, out, _ = self.run_tool("report", "--json", *args)
        self.assertEqual(code, 0)
        return json.loads(out)

    def write_samples(self, rows):
        os.makedirs(self.dir, exist_ok=True)
        day = time.strftime("%Y-%m-%d")
        with open(f"{self.dir}/samples-{day}.jsonl", "a", encoding="utf-8") as f:
            for row in rows:
                f.write(json.dumps(row) + "\n")

    def write_bench(self, rows):
        os.makedirs(self.dir, exist_ok=True)
        with open(f"{self.dir}/bench.jsonl", "a", encoding="utf-8") as f:
            for row in rows:
                f.write(json.dumps(row) + "\n")

    def bench_rows(self):
        return perf.load_jsonl(f"{self.dir}/bench.jsonl")

    def idle_host(self):
        self.put("proc/loadavg", "0.01 0.02 0.03 1/100 1\n")
        self.put("proc/pressure/io", "some avg10=0.00 avg60=1.00 avg300=0.00 total=1\n")
        self.put("proc/pressure/memory", "some avg10=0.00 avg60=0.00 avg300=0.00 total=1\n")

    def fake_bench_tools(self):
        self.fake_cmd("sysbench", f"""case "$1" in
--version) echo 'sysbench 1.0.20' ;;
cpu) echo '{SYSBENCH_CPU}' ;;
memory) echo '{SYSBENCH_MEM}' ;;
esac""")
        fio_json = f"{self.tmp}/fio.json"
        with open(fio_json, "w", encoding="utf-8") as f:
            f.write(FIO_JSON)
        # 測定のあいだ一時ファイルがあることを、作って確かめる(本物の fio と同じく --filename に書く)
        self.fake_cmd("fio", f"""for a in "$@"; do case "$a" in
--version) echo fio-3.41; exit 0 ;;
--filename=*) : > "${{a#--filename=}}" ;;
esac; done
echo 'note: a line before the JSON'
cat {fio_json}""")
        dmi = f"{self.tmp}/dmi.txt"
        with open(dmi, "w", encoding="utf-8") as f:
            f.write(DMIDECODE)
        self.fake_cmd("dmidecode", f"cat {dmi}")
        self.fake_cmd("findmnt", "echo /dev/mapper/vg-lv")
        self.fake_cmd("powerprofilesctl", "echo balanced")
        self.set_disk("ACME HDD", True)

    def set_disk(self, model, rota):
        self.fake_cmd("lsblk", "echo '" + json.dumps({"blockdevices": [{
            "type": "lvm", "rota": rota, "model": None, "tran": None,
            "children": [{"type": "part", "rota": rota, "model": None, "tran": None, "children": [
                {"type": "disk", "rota": rota, "model": model, "tran": "sata", "serial": "SECRET-SERIAL"}]}],
        }]}) + "'")


class TestSample(PerfCase):
    def test_no_gpu_no_cgroup(self):
        self.assertEqual(self.run_tool("sample")[0], 0)
        day = time.strftime("%Y-%m-%d")
        row = perf.load_jsonl(f"{self.dir}/samples-{day}.jsonl")[0]
        self.assertEqual(row["gpus"], {})
        self.assertEqual(row["users"], {})

    def add_gpu(self, card, pci, status="active"):
        dev = f"sys/class/drm/{card}/device"
        self.put(f"{dev}/uevent", f"DRIVER=amdgpu\nPCI_SLOT_NAME={pci}\n")
        self.put(f"{dev}/power/runtime_status", status + "\n")
        self.put(f"{dev}/gpu_busy_percent", "12\n")
        self.put(f"{dev}/mem_info_vram_used", "1048576\n")
        self.put(f"{dev}/hwmon/hwmon3/power1_input", "20000000\n")
        self.put(f"{dev}/hwmon/hwmon3/temp1_input", "45000\n")
        self.put(f"{dev}/hwmon/hwmon3/freq1_input", "1200000000\n")

    def test_gpu_by_pci_address(self):
        self.add_gpu("card1", "0000:01:00.0")
        self.put("sys/class/drm/card1-DP-1/device/uevent", "DRIVER=amdgpu\nPCI_SLOT_NAME=0000:09:00.0\n")
        self.put("sys/class/drm/card2/device/uevent", "DRIVER=i915\nPCI_SLOT_NAME=0000:00:02.0\n")
        gpus = perf.sample_gpus(self.root)
        self.assertEqual(list(gpus), ["0000:01:00.0"])
        g = gpus["0000:01:00.0"]
        self.assertEqual((g["busy"], g["power_w"], g["temp_c"], g["sclk_mhz"]), (12, 20.0, 45.0, 1200))

    def test_suspended_gpu_is_not_read(self):
        self.add_gpu("card0", "0000:02:00.0", status="suspended")
        self.assertEqual(perf.sample_gpus(self.root), {"0000:02:00.0": {"suspended": True}})

    def test_user_and_shell(self):
        uid = os.getuid()
        s = f"sys/fs/cgroup/user.slice/user-{uid}.slice"
        self.put(f"{s}/memory.current", "1000\n")
        self.put(f"{s}/cpu.stat", "usage_usec 500\nuser_usec 1\n")
        self.put(f"{s}/memory.pressure", "some avg10=0.00 avg60=0.00 avg300=0.00 total=7\nfull avg10=0.00 avg60=0.00 avg300=0.00 total=3\n")
        self.put(f"{s}/memory.events", "low 0\noom_kill 2\n")
        self.put(f"{s}/user@{uid}.service/session.slice/org.gnome.Shell@ubuntu.service/memory.current", "400\n")
        self.put(f"{s}/user@{uid}.service/session.slice/org.gnome.Shell@ubuntu.service/memory.peak", "900\n")
        users = perf.sample_users(self.root)
        self.assertEqual(len(users), 1)
        row = next(iter(users.values()))
        self.assertEqual((row["mem"], row["cpu_usec"], row["psi_mem_us"], row["oom_kill"]), (1000, 500, 7, 2))
        self.assertEqual((row["shell_mem"], row["shell_peak"]), (400, 900))

    def test_old_files_are_removed(self):
        os.makedirs(self.dir)
        old = time.strftime("%Y-%m-%d", time.localtime(time.time() - 40 * DAY))
        recent = time.strftime("%Y-%m-%d", time.localtime(time.time() - 30 * DAY))
        for day in (old, recent):
            open(f"{self.dir}/samples-{day}.jsonl", "w", encoding="utf-8").close()
        open(f"{self.dir}/bench.jsonl", "w", encoding="utf-8").close()
        self.run_tool("sample")
        self.assertFalse(os.path.exists(f"{self.dir}/samples-{old}.jsonl"))
        self.assertTrue(os.path.exists(f"{self.dir}/samples-{recent}.jsonl"))
        self.assertTrue(os.path.exists(f"{self.dir}/bench.jsonl"))


class TestBench(PerfCase):
    def setUp(self):
        super().setUp()
        self.idle_host()
        self.fake_bench_tools()

    def test_measures_and_cleans_up(self):
        code, out, _ = self.run_tool("bench")
        self.assertEqual(code, 0, out)
        row = self.bench_rows()[0]
        self.assertEqual(row["status"], "ok")
        r = row["results"]
        self.assertEqual((r["cpu_1t_events_s"], r["mem_mib_s"]), (1136.72, 20996.59))
        self.assertEqual((r["randread_iops"], r["randread_p99_ms"]), (131.5, 25.0))
        self.assertEqual((r["syncwrite_iops"], r["syncwrite_p99_ms"]), (55.2, 717.226))
        self.assertEqual(r["seqread_mib_s"], 150.0)
        self.assertFalse(os.path.exists(f"{self.dir}/bench-tmp"))

    def test_context_has_no_serial(self):
        self.put("sys/class/dmi/id/bios_version", "P1.40\n")
        self.put("sys/class/dmi/id/product_serial", "SECRET-SERIAL\n")
        self.run_tool("bench")
        ctx = self.bench_rows()[0]["context"]
        self.assertEqual(ctx["bios"], "P1.40")
        self.assertEqual(ctx["memory"], {"count": 1, "speed_mts": [1333], "rated_mts": [1600]})
        self.assertEqual(ctx["disks"], [{"model": "ACME HDD", "rotational": True, "transport": "sata"}])
        with open(f"{self.dir}/bench.jsonl", encoding="utf-8") as f:
            self.assertNotIn("SECRET-SERIAL", f.read())

    def test_busy_host_is_skipped(self):
        self.put("proc/loadavg", f"99 {os.cpu_count()} 99 1/100 1\n")
        code, _, err = self.run_tool("bench")
        self.assertEqual(code, 1)  # 手で測るときは分かるように失敗で終わる
        self.assertIn("load average", err)
        self.assertEqual(self.bench_rows()[0]["status"], "skipped")
        self.assertEqual(self.run_tool("bench", "--if-due")[0], 0)  # タイマーからは失敗にしない
        self.assertEqual(self.run_tool("bench", "--force")[0], 0)
        self.assertEqual(self.bench_rows()[-1]["status"], "ok")
        self.assertTrue(self.bench_rows()[-1]["forced"])

    def test_pressure_is_busy(self):
        self.put("proc/pressure/io", "some avg10=0.00 avg60=6.00 avg300=0.00 total=1\n")
        self.assertEqual(self.run_tool("bench")[0], 1)
        self.assertIn("io", self.bench_rows()[0]["reason"])

    def test_low_disk_skips_even_with_force(self):
        usage = mock.Mock(free=1024**3)
        with mock.patch.object(perf.shutil, "disk_usage", return_value=usage):
            self.assertEqual(self.run_tool("bench", "--force")[0], 1)
        self.assertEqual(self.bench_rows()[0]["status"], "skipped")

    def test_if_due_waits_seven_days(self):
        now = int(time.time())
        self.write_bench([{"t": now - 6 * DAY, "status": "ok", "results": {}, "context": {}}])
        self.assertEqual(self.run_tool("bench", "--if-due")[0], 0)
        self.assertEqual(len(self.bench_rows()), 1)  # 測らず、記録もしない
        self.write_bench([{"t": now - 8 * DAY, "status": "skipped", "reason": "x"}])
        self.assertEqual(len(self.bench_rows()), 2)
        self.assertEqual(self.run_tool("bench")[0], 0)  # 手で測るときは 7 日を待たない
        self.assertEqual(self.bench_rows()[-1]["status"], "ok")

    def test_if_due_runs_after_seven_days(self):
        self.write_bench([{"t": int(time.time()) - 7 * DAY, "status": "ok", "results": {}, "context": {}}])
        self.assertEqual(self.run_tool("bench", "--if-due")[0], 0)
        self.assertEqual(len(self.bench_rows()), 2)

    def test_tool_failure_is_recorded_and_cleans_up(self):
        self.fake_cmd("fio", 'for a in "$@"; do [ "$a" = --version ] && exit 1; done; echo boom >&2; exit 3')
        code, _, err = self.run_tool("bench")
        self.assertEqual(code, 1)
        self.assertIn("boom", err)
        self.assertEqual(self.bench_rows()[0]["status"], "failed")
        self.assertFalse(os.path.exists(f"{self.dir}/bench-tmp"))

    def test_others_cpu_is_noisy_but_own_slice_is_not(self):
        self.put("proc/self/cgroup", "0::/user.slice/user-1000.slice/session-1.scope\n")
        self.put("sys/fs/cgroup/user.slice/user-1000.slice/cpu.stat", "usage_usec 100\n")
        self.put("sys/fs/cgroup/user.slice/user-1001.slice/cpu.stat", "usage_usec 50\n")
        self.assertEqual(perf.others_cpu_usec(self.root), 50)
        with mock.patch.object(perf, "others_cpu_usec", side_effect=[0, 60_000_000]), \
                mock.patch.object(perf.time, "time", side_effect=[1000.0, 1000.0, 1100.0]):
            self.run_tool("bench", "--force")
        self.assertTrue(self.bench_rows()[-1]["noisy"])


class TestReport(PerfCase):
    def test_no_history(self):
        code, out, _ = self.run_tool("report")
        self.assertEqual(code, 0)
        self.assertGreaterEqual(out.count("履歴なし"), 4)

    def test_sar_without_hostname(self):
        now = time.time()
        day = time.strftime("%Y-%m-%d", time.gmtime(now))
        self.fake_cmd("sadf", f"cat {self.sa}/fixture.json")
        with open(f"{self.sa}/fixture.json", "w", encoding="utf-8") as f:
            f.write(sadf_json(time.strftime("%Y-%m-%d"), time.strftime("%H:%M:%S", time.gmtime(now - 60)), day))
        open(f"{self.sa}/sa{time.strftime('%d')}", "w", encoding="utf-8").close()
        code, out, _ = self.run_tool("report", "--json")
        self.assertEqual(code, 0)
        self.assertNotIn(SECRET_HOST, out)
        system = json.loads(out)["system"]
        self.assertEqual(system["cpu_busy_pct"]["p50"], 10.0)
        self.assertEqual(system["psi_io_pct"]["worst"], 1.5)
        self.assertEqual(system["mem_avail_gib"]["worst"], 2.0)
        self.assertIn("disk_sda_await_ms", system)
        self.assertFalse([k for k in system if "zram" in k or "dm-" in k])
        _, text, _ = self.run_tool("report")
        self.assertNotIn(SECRET_HOST, text)
        self.assertIn("cpu_busy_pct", text)

    def test_sar_file_of_another_month_is_ignored(self):
        self.fake_cmd("sadf", f"cat {self.sa}/fixture.json")
        with open(f"{self.sa}/fixture.json", "w", encoding="utf-8") as f:
            f.write(sadf_json("2020-01-01"))
        open(f"{self.sa}/sa{time.strftime('%d')}", "w", encoding="utf-8").close()
        self.assertEqual(self.report()["system"], {})

    def test_broken_sadf_is_ignored(self):
        self.fake_cmd("sadf", "echo broken; exit 1")
        open(f"{self.sa}/sa{time.strftime('%d')}", "w", encoding="utf-8").close()
        self.assertEqual(self.report()["system"], {})

    def test_counters_reset_is_dropped_and_broken_lines_skipped(self):
        now = int(time.time())
        rows = [{"t": now - 900 + 300 * i, "oom_kill": kills,
                 "users": {"a": {"mem": 1024**3, "cpu_usec": usec, "oom_kill": kills}}, "gpus": {}}
                for i, (usec, kills) in enumerate([(300_000_000, 1), (600_000_000, 2), (1000, 0)])]
        self.write_samples(rows)
        with open(f"{self.dir}/samples-{time.strftime('%Y-%m-%d')}.jsonl", "a", encoding="utf-8") as f:
            f.write('{"t": 12, "broken\nnot json\n[1, 2]\n')
        per = self.report()["per_sample"]
        self.assertEqual(per["samples"], 3)
        self.assertEqual(per["oom_kills"], 1)
        user = per["users"]["a"]
        self.assertEqual(user["cpu_cores"]["n"], 1)  # 戻った区間は捨てる
        self.assertEqual(user["cpu_cores"]["worst"], 1.0)
        self.assertEqual(user["oom_kills"], 1)
        self.assertEqual(user["mem_gib"]["p50"], 1.0)

    def test_gpu_suspended_count(self):
        now = int(time.time())
        self.write_samples([
            {"t": now - 600, "gpus": {"0000:01:00.0": {"suspended": True}}, "users": {}},
            {"t": now - 300, "gpus": {"0000:01:00.0": {"busy": 40, "vram_used": 1024**2}}, "users": {}},
        ])
        gpu = self.report()["per_sample"]["gpus"]["0000:01:00.0"]
        self.assertEqual((gpu["samples"], gpu["suspended_samples"]), (2, 1))
        self.assertEqual(gpu["busy"]["worst"], 40)
        self.assertEqual(gpu["vram_used_mib"]["worst"], 1.0)

    def test_gpu_always_suspended_is_printed(self):
        # 期間の記録がすべて休止中の GPU があっても、文字の出力が止まらない
        now = int(time.time())
        self.write_samples([{"t": now - 300, "gpus": {"0000:01:00.0": {"suspended": True}}, "users": {}}])
        code, out, _ = self.run_tool("report")
        self.assertEqual(code, 0)
        self.assertIn("休止していた記録 1 / 1", out)

    def test_old_samples_are_out_of_range(self):
        self.write_samples([{"t": int(time.time()) - 10 * DAY, "gpus": {}, "users": {"a": {"mem": 1}}}])
        self.assertEqual(self.report("--days", "7")["per_sample"]["samples"], 0)
        self.assertEqual(self.report("--days", "11")["per_sample"]["samples"], 1)

    def bench_row(self, days_ago, value, disk="HDD", kernel="7.0", **extra):
        return {"t": int(time.time()) - days_ago * DAY, "status": "ok",
                "results": {"randread_iops": value}, "context": {"kernel": kernel, "disks": [{"model": disk}]}, **extra}

    def test_bench_compares_within_same_context(self):
        self.write_bench([
            self.bench_row(30, 900, disk="SSD"),  # 条件が違うので比べない
            self.bench_row(21, 100),
            self.bench_row(14, 120, kernel="7.1"),  # カーネルが違っても比べる
            self.bench_row(10, 5000, noisy=True),  # ほかの負荷があった回は比べない
            self.bench_row(7, 110),
        ])
        bench = self.report()["bench"]
        r = bench["latest"]["results"]["randread_iops"]
        self.assertEqual(r["value"], 110)
        self.assertEqual(r["median_same_context"], 110)  # 100 と 120 の中央値
        self.assertEqual(r["diff_pct"], 0.0)
        self.assertEqual(bench["latest"]["compared_with"], 2)
        self.assertEqual(bench["days_since_last_ok"], 7)

    def test_bench_marks_context_change(self):
        self.write_bench([self.bench_row(14, 130), self.bench_row(7, 130, kernel="7.1"),
                          self.bench_row(1, 90000, disk="SSD", kernel="7.1")])
        bench = self.report()["bench"]
        self.assertEqual([c["comparable"] for c in bench["changes"]], [True, False])
        self.assertEqual(bench["changes"][1]["changed"]["disks"]["to"], [{"model": "SSD"}])
        self.assertIsNone(bench["latest"]["results"]["randread_iops"]["median_same_context"])
        _, text, _ = self.run_tool("report")
        self.assertIn("条件が変わった", text)
        self.assertIn("カーネルだけ変わった", text)

    def test_not_measured_is_listed(self):
        now = int(time.time())
        self.write_bench([{"t": now - DAY, "status": "skipped", "reason": "忙しい"},
                          {"t": now - 40 * DAY, "status": "failed", "reason": "古い"}])
        bench = self.report()["bench"]
        self.assertEqual([r["reason"] for r in bench["not_measured"]], ["忙しい"])
        self.assertIsNone(bench["latest"])
        self.assertIn("忙しい", self.run_tool("report")[1])

    def test_days_range(self):
        for bad in ("0", "36"):
            with self.assertRaises(SystemExit), contextlib.redirect_stderr(io.StringIO()):
                self.run_tool("report", "--days", bad)


if __name__ == "__main__":
    unittest.main()
