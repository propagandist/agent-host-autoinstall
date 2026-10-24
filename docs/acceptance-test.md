# 受け入れテスト

SPEC.md §7 の手順。まず仮想マシン(KVM/QEMU、Windows では VirtualBox)で通し、実機でも行う。

## 機械で確かめる

人が見なくても判定できるものは、手元の PC の just のレシピで確かめる。どれも ✗ が 1 つでもあれば失敗で終わる。

| レシピ | 確かめること | 要るもの |
|---|---|---|
| `just test` | env.yaml の検査(知らないキー、SOPS のまま、書き忘れ、値の形、組み合わせ)、重ね方、生成する env.sh と /opt/agent-host に置くものの形 | ホストは要らない |
| `just verify <ホスト>` | 下の「構成の確認」のうち、画面を見なくてよいもの(約 100 項目)。固定した版は、そのホストの `/opt/agent-host/post-install/` に書いてある値と比べる。何も変えない(ホストの上では `sudo /opt/agent-host/verify.sh`) | SSH と sudo のパスワード |
| `just verify-rdp <ホスト>[:ポート] [env.yaml...]` | env.yaml の `rdp` の認証情報で RDP の認証(NLA)が通ること。画面は開かない(FreeRDP の `+auth-only`) | 手元の Docker か `xfreerdp3` |
| `just vm-test [env.yaml...]` | VirtualBox の VM に今のスクリプトで作った ISO を入れなおし、下の 1・3・4(認証まで)・8 を人手なしで行い、その都度 `verify` と `verify-rdp` を通す | VirtualBox、試験用の env.yaml(docs/release.md)。1〜2 時間。VM の中身は消える |

`just vm-test` が通っても、人が確かめるものが残る: 2(各ログイン)、4 のうち画面と日本語入力と記号、5、6、7(LAN の外から)。

下の表の「結果」は、このリポジトリでの検証結果(参考)。自分のホストの結果は、構成リポジトリの `docs/hosts/<ホスト>.md`(docs/fleet.md)などに書く。

| # | 確認すること | 手順 | 合格の条件 | 結果(このリポジトリでの検証) |
|---|---|---|---|---|
| 1 | 無人でインストールできる | USB(VM なら ISO)から起動して待つ | 確認画面なしでインストールが終わり、再起動し、agent で自動ログインする | OK(VirtualBox、2026-10-23。約 47 分) |
| 2 | 手作業を終えられる | docs/manual-steps.md の初回の手作業(各ログイン)を行う | 各ログインが終わる | OK(VirtualBox + RDP、2026-10-24。Claude Code はブラウザ(Chrome)で、Codex はデバイスコード認証で。キーリングとデスクトップ共有は自動で済み、手作業は要らなかった) |
| 3 | 電源が切れても自動で戻る | 電源ケーブルを抜き、挿し直す(VM なら強制停止 → 起動) | 何もしなくても起動し、agent で自動ログインする | OK(VirtualBox の強制電源オフ → 起動、2026-10-23。BIOS の設定は実機で確認) |
| 4 | 再起動後、何もせずに RDP がつながる | 3 のあと何も操作せず、手元の PC から `<ホスト>:3389` に RDP 接続する | env.yaml の `rdp` の認証情報で入れ、Orca が起動済みの画面が出る。Ctrl+Space で日本語入力(Mozc)に切り替えて日本語を打て、英字のときに記号(`@` `"` `:` など)がキーの刻印どおりに出る | OK(VirtualBox、2026-10-23 に再起動・強制電源オフ後の FreeRDP の NLA 認証、2026-10-24 に mstsc + 101 キーボードで画面・日本語入力・記号・Chrome を確認) |
| 5 | エージェントが動く | Orca から Claude Code と Codex で、それぞれ簡単なタスクを 1 本ずつ実行する | 両方とも最後まで終わる | OK(VirtualBox + RDP、2026-10-24。Claude が README.md、Codex が hello.py を作った) |
| 6 | 切断しても作業が続く | 5 のタスクを走らせたまま RDP を切断し、10 分後に再接続する | タスクが継続している(画面ロックで切れていない) | OK(VirtualBox + RDP、2026-10-24。約 12 分切断して再接続。ロックされず、端末のループも続いていた) |
| 7 | LAN の外から到達できない | lan_cidrs の外から `22` と `3389` に接続する | どちらも到達できない | |
| 8 | セッションが落ちても戻る | SSH で `sudo pkill -SEGV -u agent -x gnome-shell` を実行し、3 分待つ | 何もしなくても agent のセッションと RDP が戻り、「セッションを復旧した」が通知される | OK(VirtualBox、2026-10-24。約 1 分 20 秒で戻った) |

4 がいちばん崩れやすい(notes.md)。最優先で確かめ、NG なら次を見る。

```
sudo cat /home/agent/.local/state/agent-host/first-login.log
sudo -u agent DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u agent)/bus grdctl status
sudo ss -tlnp | grep 33
```

## 構成の確認(1 のあとに SSH で)

`just verify <ホスト>` が、下の表のうち画面を見なくてよいものをまとめて確かめる(VS Code のメニュー、`hello-world` や `wget` の実行、SFTP、開発用のポート、移行、Zed の拡張機能の中身は対象外)。✗ が出たら、該当する行のコマンドで詳しく見る。

| 確認すること | コマンド | 期待する結果 |
|---|---|---|
| 作った版 | 手元の PC で `just status <ホスト>` | 「作った版」に、ISO を作った道具の版(と構成の版)が出る |
| 構成サービスが成功した | `systemctl status agent-host-provision.service` | `active (exited)` |
| 自動ログインの設定 | `grep -A3 '^\[daemon\]' /etc/gdm3/custom.conf` | `AutomaticLoginEnable=true` と `AutomaticLogin=agent` |
| スリープの無効化 | `systemctl is-enabled sleep.target` | `masked` |
| SSH | `sudo sshd -T \| grep -E 'passwordauthentication\|permitrootlogin'` | どちらも `no` |
| ufw | `sudo ufw status` | 22/tcp と 3389/tcp が lan_cidrs からだけ ALLOW |
| バージョンの固定 | `apt-mark showhold` | `claude-code`、`containerd.io`、`docker-*`(5 つ)、`gh`、`orca-ide`。選んだときは `code`、`google-cloud-cli`、`azure-cli` も |
| 既定のブラウザ | `sudo -u agent DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u agent)/bus xdg-settings get default-web-browser` | `google-chrome.desktop` |
| Chrome の自動更新 | `sudo unattended-upgrade --dry-run --debug 2>&1 \| grep -i 'Google LLC'` | 許可元に `o=Google LLC,a=stable` がある |
| ホームのフォルダー名 | `sudo ls /home/agent` | Desktop・Downloads などの英語名だけで、日本語名のフォルダーがない |
| ディスク | `df -h /; sudo vgs` | ルートがボリュームグループのほぼ全部を使っている(VFree がほぼ 0) |
| ネットワーク | `ip -4 addr; ip route; resolvectl status \| grep -A2 'DNS Servers'` | env.yaml の network どおり(static ならアドレス・ゲートウェイ・DNS) |
| 時刻同期 | `chronyc -N sources` | 同期している(`^*`)。ntp_servers を書いたらそれが並ぶ |
| agent の git | `sudo -u agent git config --global --list` | user.name・user.email・init.defaultbranch=main |
| inotify | `sysctl fs.inotify.max_user_watches` | 524288 |
| 確認画面を出さない | `grep ^enabled /etc/default/apport; sudo ls /home/agent/.config/autostart` | enabled=0。autostart に update-notifier.desktop(Hidden=true) |
| Docker(rootless) | `sudo -u agent XDG_RUNTIME_DIR=/run/user/$(id -u agent) docker info --format '{{.SecurityOptions}}'` と、RDP の端末で `docker run --rm hello-world` | `rootless` を含む。hello-world が動く。`systemctl is-active docker` は inactive |
| SFTP(agent) | 鍵を登録した人が `sftp agent@<ホスト>` と `ssh agent@<ホスト>` | SFTP は入れる。ssh のシェルは「This service allows sftp connections only.」で入れない |
| 開発用のポート | 手元の PC から `<ホスト>:<dev_ports のポート>` | 開発サーバーが見える(lan_cidrs の中からだけ) |
| エディター | `code --version; nvim --version; zed --version`(選んだものだけ) | 入っている。VS Code は `apt-mark showhold` に code |
| VS Code の拡張機能と日本語 | RDP の端末で `code --list-extensions --show-versions`。VS Code を開く | 72-editors.sh の VSCODE_EXTENSIONS(と clouds・vscode_extensions の分)が並ぶ。メニューが日本語(「ファイル」「編集」) |
| Zed の拡張機能 | Zed を一度起動して閉じたあと `ls ~/.local/share/zed/extensions/installed` | 72-editors.sh の ZED_EXTENSIONS(と clouds・zed_extensions の分)が並ぶ |
| Gitea CLI | RDP の端末で `tea --version` と `echo $GITEA_SERVER_URL` | 60-devtools.sh の版。gitea_url を書いたらその URL |
| クラウドの CLI | RDP の端末で `aws --version; gcloud --version; az version`(選んだものだけ) | 63-clouds.sh の版。`echo $AWS_PAGER` は空 |
| 開発の道具 | RDP の端末で `mise --version; uv --version; pnpm --version; ccmanager --version; ulimit -n` | それぞれ動く。ulimit -n は 65536 |
| エージェントへの説明 | `sudo cat /home/agent/.claude/CLAUDE.md` | 「このホストについて」が置かれている |
| Orca のテレメトリ | RDP の端末で `echo $ORCA_TELEMETRY_DISABLED` | 1 |
| サービスの最小化 | `systemctl list-units --type=service --state=running`、`command -v snap orca` | cups・avahi・ModemManager・bluetooth・root の containerd・rsyslog が動いていない。snap と(読み上げの)orca がない |
| メモリ | `swapon --show; cat /proc/cmdline` | zram がある。crashkernel がない |
| GPU による符号化 | `vainfo --display drm --device /dev/dri/renderD128 \| grep EncSlice`、RDP でつないだあと `journalctl -b _UID=$(id -u agent) \| grep HWAccel` | Intel・AMD は `VAProfileH264High` に `VAEntrypointEncSlice`(か `EncSliceLP`)があり、`[HWAccel.VAAPI] Successfully initialized` が出る。NVIDIA は `lsmod \| grep nvidia` と `ldconfig -p \| grep libnvidia-encode`。VM では対象外 |
| Docker の通信 | RDP の端末で `docker run --rm alpine:3 wget -qO- http://example.com` | 取得できる(pasta) |
| UPS(ups を書いたとき) | ホストで `upsc <name>@localhost`(netclient なら `<name>@<server>`)。UPS の電源プラグを抜いて数十秒で挿しなおす | `ups.status` が `OL`。抜くと「停電: UPS のバッテリーで動いている」、挿すと「UPS: 電源が戻った」が届く。バッテリーが少なくなるまで待つと終了し、電源が戻ると起動する(usb のとき) |
| ディスクの監視 | `systemctl is-enabled agent-host-diskcheck.timer` | enabled |
| 移行 | 書き出し → 消す → 取り込み(docs/manual-steps.md の 16。just backup → 消す → just restore) | ログインと ~/work が戻る |
| 各ツール | `node --version; codex --version; claude --version` | 60-devtools.sh に書いたバージョン |
| agent に sudo がない | `id agent` | sudo グループに入っていない |
