#!/usr/bin/env bash
# ホストの性能を定期的に記録する(docs/SPEC.md、docs/notes.md「性能の記録」)。
#   負荷の履歴: システム全体は sysstat(sar)。sar にない値(GPU、利用者ごとの cgroup)は 5 分ごとのタイマー
#   速さの測定: 毎晩のタイマーが、直近の成功から 7 日以上経っていて、ホストが空いているときだけ測る
# 結果は agent-host-perf report(手元からは just perf <ホスト>)で見る。
set -euo pipefail
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"

apt-get install -y sysstat fio sysbench dmidecode

# --- sysstat ---
# 28 日を超えると sa ファイルの置き方を変える設定が要る(/etc/sysstat/sysstat のコメント)。
# sadf が圧縮したファイルを読めるかは確かめていないので、圧縮しない(1 日約 500KB。1 回の大きさからの推定)
sed -i -E 's/^HISTORY=.*/HISTORY=28/; s/^COMPRESSAFTER=.*/COMPRESSAFTER=31/' /etc/sysstat/sysstat
sed -i -E 's/^ENABLED=.*/ENABLED="true"/' /etc/default/sysstat
systemctl enable --now sysstat.service sysstat-collect.timer sysstat-summary.timer sysstat-rotate.timer
# 反映の直後でも記録があるように 1 回取る(just verify が見る)
/usr/libexec/sysstat/sa1 1 1 || log "注意: sar の記録を取れなかった"

# --- 負荷の記録と速さの測定 ---
install -m 755 "$AH_ROOT/perf/agent-host-perf" /usr/local/bin/agent-host-perf
install -d -m 755 /var/lib/agent-host/perf
# どちらも利用者のホームには触らない(ProtectHome)
cat >/etc/systemd/system/agent-host-perf-sample.service <<'UNIT'
[Unit]
Description=sar にない負荷の値を記録する(agent-host-autoinstall)
[Service]
Type=oneshot
ExecStart=/usr/local/bin/agent-host-perf sample
Nice=10
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
NoNewPrivileges=yes
ReadWritePaths=/var/lib/agent-host/perf
CapabilityBoundingSet=
UNIT
cat >/etc/systemd/system/agent-host-perf-sample.timer <<'UNIT'
[Unit]
Description=5 分ごとに負荷の値を記録する(agent-host-autoinstall)
[Timer]
OnCalendar=*:00/5
AccuracySec=30s
[Install]
WantedBy=timers.target
UNIT
cat >/etc/systemd/system/agent-host-perf-bench.service <<'UNIT'
[Unit]
Description=CPU・メモリ・ディスクの速さを測る(agent-host-autoinstall)
[Service]
Type=oneshot
ExecStart=/usr/local/bin/agent-host-perf bench --if-due
ExecStopPost=/usr/bin/rm -rf /var/lib/agent-host/perf/bench-tmp
TimeoutStartSec=20min
Nice=19
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
NoNewPrivileges=yes
ReadWritePaths=/var/lib/agent-host/perf
UNIT
cat >/etc/systemd/system/agent-host-perf-bench.timer <<'UNIT'
[Unit]
Description=毎晩、測る時期でホストが空いていれば速さを測る(agent-host-autoinstall)
[Timer]
OnCalendar=*-*-* 04:30:00
RandomizedDelaySec=15min
[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
systemctl enable --now agent-host-perf-sample.timer agent-host-perf-bench.timer
/usr/local/bin/agent-host-perf sample
log "性能の記録を設定した(sar を 28 日、負荷の値を 5 分ごと、速さの測定を週 1 回)"
