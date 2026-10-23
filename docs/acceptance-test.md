# 受け入れテスト

SPEC.md §7 の手順。まず仮想マシン(KVM/QEMU、Windows では VirtualBox)で通し、最後に実機で行う。各項目の結果(OK / NG と日付)を書き込む。

| # | 確認すること | 手順 | 合格の条件 | 結果 |
|---|---|---|---|---|
| 1 | 無人でインストールできる | USB(VM なら ISO)から起動して待つ | 確認画面なしでインストールが終わり、再起動し、agent で自動ログインする | OK(VirtualBox、2026-10-23。約 47 分) |
| 2 | 手作業を終えられる | docs/manual-steps.md の 5〜7 を行う | 各ログインが終わる | OK(VirtualBox + RDP、2026-10-24。Claude Code はブラウザ(Chrome)で、Codex はデバイスコード認証で。キーリングは自動で開いたままなので 3・4 は不要だった) |
| 3 | 停電から自動で復帰する | 電源ケーブルを抜き、挿し直す(VM なら強制停止 → 起動) | 何もしなくても起動し、agent で自動ログインする | OK(VirtualBox の強制電源オフ → 起動、2026-10-23。BIOS の設定は実機で確認) |
| 4 | 再起動後、何もせずに RDP がつながる | 3 のあと何も操作せず、手元の PC から `<ホスト>:3389` に RDP 接続する | env.yaml の `rdp` の認証情報で入れ、Orca が起動済みの画面が出る。Ctrl+Space で日本語入力(Mozc)に切り替えて日本語を打て、英字のときに記号(`@` `"` `:` など)がキーの刻印どおりに出る | OK(VirtualBox、2026-10-23 に再起動・強制電源オフ後の FreeRDP の NLA 認証、2026-10-24 に mstsc + 101 キーボードで画面・日本語入力・記号・Chrome を確認) |
| 5 | エージェントが動く | Orca から Claude Code と Codex で、それぞれ簡単なタスクを 1 本ずつ実行する | 両方とも最後まで終わる | OK(VirtualBox + RDP、2026-10-24。Claude が README.md、Codex が hello.py を作った) |
| 6 | 切断しても作業が続く | 5 のタスクを走らせたまま RDP を切断し、10 分後に再接続する | タスクが継続している(画面ロックで切れていない) | OK(VirtualBox + RDP、2026-10-24。約 12 分切断して再接続。ロックされず、端末のループも続いていた) |
| 7 | 社内LANの外から到達できない | lan_cidrs の外から `22` と `3389` に接続する | どちらも到達できない | |

4 がいちばん崩れやすい(HANDOVER.md)。最優先で確かめ、NG なら次を見る。

```
sudo cat /home/agent/.local/state/agent-host/first-login.log
sudo -u agent DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u agent)/bus grdctl status
sudo ss -tlnp | grep 33
```

## 構成の確認(1 のあとに SSH で)

| 確認すること | コマンド | 期待する結果 |
|---|---|---|
| 構成サービスが成功した | `systemctl status agent-host-provision.service` | `active (exited)` |
| 自動ログインの設定 | `grep -A3 '^\[daemon\]' /etc/gdm3/custom.conf` | `AutomaticLoginEnable=true` と `AutomaticLogin=agent` |
| スリープの無効化 | `systemctl is-enabled sleep.target` | `masked` |
| SSH | `sudo sshd -T \| grep -E 'passwordauthentication\|permitrootlogin'` | どちらも `no` |
| ufw | `sudo ufw status` | 22/tcp と 3389/tcp が lan_cidrs からだけ ALLOW |
| バージョンの固定 | `apt-mark showhold` | `claude-code`、`gh`、`orca-ide` |
| 既定のブラウザ | `sudo -u agent DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u agent)/bus xdg-settings get default-web-browser` | `google-chrome.desktop` |
| Chrome の自動更新 | `sudo unattended-upgrade --dry-run --debug 2>&1 \| grep -i 'Google LLC'` | 許可元に `o=Google LLC,a=stable` がある |
| ホームのフォルダー名 | `sudo ls /home/agent` | Desktop・Downloads などの英語名だけで、日本語名のフォルダーがない |
| ディスク | `df -h /; sudo vgs` | ルートがボリュームグループのほぼ全部を使っている(VFree がほぼ 0) |
| ネットワーク | `ip -4 addr; ip route; resolvectl status \| grep -A2 'DNS Servers'` | env.yaml の network どおり(static ならアドレス・ゲートウェイ・DNS) |
| 時刻同期 | `chronyc -N sources` | 同期している(`^*`)。ntp_servers を書いたらそれが並ぶ |
| agent の git | `sudo -u agent git config --global --list` | user.name・user.email・init.defaultbranch=main |
| inotify | `sysctl fs.inotify.max_user_watches` | 524288 |
| 確認画面を出さない | `grep ^enabled /etc/default/apport; sudo ls /home/agent/.config/autostart` | enabled=0。autostart に update-notifier.desktop(Hidden=true) |
| 各ツール | `node --version; codex --version; claude --version` | 60-devtools.sh に書いたバージョン |
| agent に sudo がない | `id agent` | sudo グループに入っていない |
