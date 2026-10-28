# 受け入れテスト

SPEC.md §7 の手順。まず仮想マシン(KVM/QEMU、Windows では VirtualBox)で通し、実機でも行う。

## 機械で確かめる

人が見なくても判定できるものは、手元の PC の just のレシピで確かめる。どれも ✗ が 1 つでもあれば失敗で終わる。

| レシピ | 確かめること | 要るもの |
|---|---|---|
| `just test` | env.yaml の検査(知らないキー、SOPS のまま、書き忘れ、値の形、組み合わせ)、重ね方、生成する env.sh と /opt/agent-host に置くものの形 | ホストは要らない |
| `just verify <ホスト>` | 下の「構成の確認」のうち、画面を見なくてよいもの(全体と、利用者ごとの節)。固定した版は、そのホストの `/opt/agent-host/post-install/` に書いてある値と比べる。何も変えない(ホストの上では `sudo /opt/agent-host/verify.sh`) | SSH と sudo のパスワード |
| `just verify-rdp <ホスト> [--ask <利用者>] [env.yaml...]` | 利用者ごとに、その人の port で RDP の認証(NLA)が通ること。仮のパスワード(`rdp.initial_password`)で通らなければ「未検証」(本人が変えていれば正常)、`--ask` でその人の今のパスワードを聞いて確かめる。つながらない・TLS のエラーは失敗。画面は開かない(FreeRDP の `+auth-only`)。ポートに足す数は環境変数 `AGENT_HOST_RDP_PORT_OFFSET` | 手元の Docker か `xfreerdp3` |
| `just vm-test [env.yaml...]` | VirtualBox の VM に今のスクリプトで作った ISO を入れなおし、下の 1・3・4(認証まで)・8 を人手なしで行い、その都度 `verify` と `verify-rdp` を通す。8 は 1 人目の gnome-shell を落とし、その人だけが戻り、2 人目の gnome-shell が続いていることを見る | VirtualBox、試験用の env.yaml(docs/release.md。users は 2 人以上、port は 3389〜3392)。1〜2 時間。VM の中身は消える |

`just vm-test` が通っても、人が確かめるものが残る: 2(各ログインと RDP のパスワードの変更)、4 のうち画面と日本語入力と記号、2 人で同時につなぐこと、5、6、7(LAN の外から)、9。

下の表の「結果」は、このリポジトリでの検証結果(参考)。自分のホストの結果は、構成リポジトリの `docs/hosts/<ホスト>.md`(docs/fleet.md)などに書く。

| # | 確認すること | 手順 | 合格の条件 | 結果(このリポジトリでの検証) |
|---|---|---|---|---|
| 1 | 無人でインストールできる | USB(VM なら ISO)から起動して待つ | 確認画面なしでインストールが終わり、再起動し、利用者全員のセッションが立ち、それぞれの port で RDP が待ち受ける | OK(0.2 の 1 人の作りで VirtualBox、2026-10-23。約 47 分)。2 人の作りは下の vm-test |
| 2 | 手作業を終えられる | 利用者ごとに docs/manual-steps.md の初回の手作業(RDP のパスワードの変更と各ログイン)を行う | RDP のパスワードを変えたあと、新しい値で入れる。各ログインが終わる | 各ログインは OK(0.2 の作りで VirtualBox + RDP、2026-10-24。Claude Code はブラウザ(Chrome)で、Codex はデバイスコード認証で)。パスワードの変更は OK(2 人の作りで VirtualBox + mstsc、2026-10-25。デーモンの再起動のあと新しい値で入れ、just update のあとも残った) |
| 3 | 電源が切れても自動で戻る | 電源ケーブルを抜き、挿し直す(VM なら強制停止 → 起動) | 何もしなくても起動し、利用者全員のセッションが立つ | 0.2 の作りで OK(VirtualBox の強制電源オフ → 起動、2026-10-23)。2 人の作りは段 0 の手での再起動で OK(2026-10-25。約 25 秒でセッション、約 60 秒で RDP)。BIOS の設定は実機で確認 |
| 4 | 再起動後、何もせずに RDP がつながる | 3 のあと何も操作せず、手元の PC から利用者ごとに `<ホスト>:<その人の port>` に RDP 接続する。2 人で同時につなぐ | その人の RDP の認証情報で入れ、Orca が起動済みの画面が出る。2 人が同時につながり、それぞれ操作できる。Ctrl+Space で日本語入力(fcitx5 の Mozc)に切り替えて日本語を打て、半角/全角キーを押すと日本語になったまま止まり(表示が切り替わり続けず、ホストが重くならない)、無変換キーで英字に戻り、英字のときに記号(`@` `"` `:` など)がキーの刻印どおりに出る | OK(VirtualBox、2026-10-23 に再起動・強制電源オフ後の FreeRDP の NLA 認証、2026-10-24 に mstsc + 101 キーボードで画面・日本語入力・記号・Chrome を確認)。2 人の作りでは、2 人が同時に mstsc でつながり、それぞれロックされていないデスクトップが出た(VirtualBox、2026-10-25) |
| 5 | エージェントが動く | Orca から Claude Code と Codex で、それぞれ簡単なタスクを 1 本ずつ実行する | 両方とも最後まで終わる | OK(VirtualBox + RDP、2026-10-24。Claude が README.md、Codex が hello.py を作った) |
| 6 | 切断しても作業が続く | 5 のタスクを走らせたまま RDP を切断し、10 分後に再接続する | タスクが継続している(画面ロックで切れていない) | OK(VirtualBox + RDP、2026-10-24。約 12 分切断して再接続。ロックされず、端末のループも続いていた) |
| 7 | LAN の外から到達できない | lan_cidrs の外から `22` と利用者の RDP のポートに接続する | どれも到達できない | |
| 8 | セッションが落ちても戻る | SSH で `sudo pkill -SEGV -u <1 人目> -x gnome-shell` を実行し、3 分待つ | 何もしなくてもその人のセッションと RDP が戻る。ほかの利用者のセッションは続いている | 段 0 の手での確認で OK(VirtualBox、2026-10-25。約 15 秒で戻り、もう 1 人の gnome-shell は変わらなかった) |
| 9 | 利用者どうしが分かれている | 2 人がそれぞれ RDP で入り、端末で `ls /home/<相手>` と、相手の port に自分の認証情報で RDP する。env.yaml から 1 人を外して `just update` し、外した人の鍵で `sftp`・`ssh` する | 相手のホームは読めない(Permission denied)。相手の port には入れない。外した人は SFTP もシェルも入れず、`just verify` の「外した利用者」が ✓、残った人の port は変わらない | 相手の port に入れないこと(段 0 の FreeRDP)と、相手のホームを読めないこと(2 人の作りで RDP の端末から)は OK(VirtualBox、2026-10-25)。外した人の確認は未確認 |

4 がいちばん崩れやすい(notes.md)。最優先で確かめ、NG なら次を見る。

```
sudo cat /home/<名前>/.local/state/agent-host/first-login.log
systemctl status gnome-headless-session@<名前>
sudo -u <名前> XDG_RUNTIME_DIR=/run/user/$(id -u <名前>) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u <名前>)/bus grdctl --headless status
sudo ss -tlnp | grep gnome-remote
```

## 構成の確認(1 のあとに SSH で)

`just verify <ホスト>` が、下の表のうち画面を見なくてよいものの多くをまとめて確かめる。対象外は、ディスク、ネットワーク、NTP の同期先、VS Code のメニュー、コンテナからの `wget`、pnpm と `ulimit -n` の実際の値、SFTP、開発用のポート、移行、Zed の拡張機能の中身、Chrome の自動更新の許可元。✗ が出たら、該当する行のコマンドで詳しく見る。

| 確認すること | コマンド | 期待する結果 |
|---|---|---|
| 置いた版 | 手元の PC で `just status <ホスト>` | 「置いた版」と「最後に適用に成功した版」に、ISO を作った道具の版(と構成の版)が出る。「構成: 済み」で、「前回の実行が最後まで終わっていない」が出ない |
| 構成サービスが成功した | `systemctl status agent-host-provision.service` | `active (exited)` |
| 利用者ごとのセッション | `systemctl status 'gnome-headless-session@*'`、`grep -A3 '^\[daemon\]' /etc/gdm3/custom.conf` | 利用者全員の分が `active (running)`。`AutomaticLoginEnable=false` |
| スリープの無効化 | `systemctl is-enabled sleep.target` | `masked` |
| SSH | `sudo sshd -T \| grep -E 'passwordauthentication\|permitrootlogin'` | どちらも `no` |
| ufw | `sudo ufw status` | 22/tcp と利用者ごとの RDP のポート(コメント `agent-host-rdp:<名前>`)(と dev_ports、IP Messenger を使うときの 2425/udp)が lan_cidrs からだけ ALLOW |
| SSH に入れる人 | `sudo sshd -T \| grep allowusers` | sysadmin と利用者だけ |
| sysadmin の鍵とパスワード | `sudo cmp /opt/agent-host/sysadmin_authorized_keys ~sysadmin/.ssh/authorized_keys` | 同じ(env.yaml の `sysadmin` と同じ鍵だけ) |
| RDP の認証情報 | 手元の `just verify-rdp <ホスト>` | パスワードを変える前は、利用者全員が仮のパスワードで通る。変えた人は「未検証」になり、`--ask <名前>` で今の値を入れると通る |
| 壁紙の色と Dock | RDP で見る。`sudo cat /home/<名前>/.config/agent-host/desktop.applied` | env.yaml の desktop_color の色。入っているエディターが Dock に並ぶ |
| バージョンの固定 | `apt-mark showhold` | `claude-code`、`containerd.io`、`docker-*`(5 つ)、`gh`、`orca-ide`。選んだときは `code`、`google-cloud-cli`、`azure-cli` も |
| 既定のブラウザ | `sudo -u <名前> DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u <名前>)/bus xdg-settings get default-web-browser` | `google-chrome.desktop` |
| PDF の既定のアプリ | `sudo -u <名前> xdg-mime query default application/pdf`。RDP で日本語を含む PDF を Files でダブルクリックする | `atril.desktop`。Atril で開き、日本語が表示される |
| Chrome の自動更新 | `sudo unattended-upgrade --dry-run --debug 2>&1 \| grep -i 'Google LLC'` | 許可元に `o=Google LLC,a=stable` がある |
| ホームのフォルダー名 | `sudo ls /home/<名前>` | Desktop・Downloads などの英語名だけで、日本語名のフォルダーがない |
| ディスク | `df -h /; sudo vgs` | ルートがボリュームグループのほぼ全部を使っている(VFree がほぼ 0) |
| ネットワーク | `ip -4 addr; ip route; resolvectl status \| grep -A2 'DNS Servers'` | env.yaml の network どおり(static ならアドレス・ゲートウェイ・DNS) |
| 時刻同期 | `chronyc -N sources` | 同期している(`^*`)。ntp_servers を書いたらそれが並ぶ |
| 利用者の git | `sudo -u <名前> git config --global --list` | user.name・user.email・init.defaultbranch=main |
| inotify | `sysctl fs.inotify.max_user_watches` | 524288 |
| 確認画面を出さない | `grep ^enabled /etc/default/apport; sudo ls /home/<名前>/.config/autostart` | enabled=0。autostart に update-notifier.desktop(Hidden=true) |
| Docker(rootless) | `sudo -u <名前> XDG_RUNTIME_DIR=/run/user/$(id -u <名前>) docker info --format '{{.SecurityOptions}}'` と、RDP の端末で `docker run --rm hello-world`。`cat /etc/subuid /etc/subgid` | `rootless` を含む。hello-world が動く(just verify も利用者ごとに動かす。取得できなければ未検証)。`systemctl is-active docker` は inactive。subuid・subgid は利用者ごとに 65536 個以上で、範囲が重ならない |
| SFTP(利用者) | 鍵を登録した人が `sftp <名前>@<ホスト>` と `ssh <名前>@<ホスト>` | SFTP は入れる。ssh のシェルは「This service allows sftp connections only.」で入れない |
| 開発用のポート | 手元の PC から `<ホスト>:<dev_ports のポート>` | 開発サーバーが見える(lan_cidrs の中からだけ) |
| エディター | `code --version; nvim --version; zed --version`(選んだものだけ) | 入っている。VS Code は `apt-mark showhold` に code |
| VS Code の拡張機能と日本語 | RDP の端末で `code --list-extensions --show-versions`。VS Code を開く | 72-editors.sh の VSCODE_EXTENSIONS(と clouds・vscode_extensions の分)が並ぶ。メニューが日本語(「ファイル」「編集」) |
| Zed の拡張機能 | Zed を一度起動して閉じたあと `ls ~/.local/share/zed/extensions/installed` | 72-editors.sh の ZED_EXTENSIONS(と clouds・zed_extensions の分)が並ぶ |
| Gitea CLI | RDP の端末で `tea --version` と `echo $GITEA_SERVER_URL` | 60-devtools.sh の版。gitea_url を書いたらその URL |
| クラウドの CLI | RDP の端末で `aws --version; gcloud --version; az version`(選んだものだけ) | 63-clouds.sh の版。`echo $AWS_PAGER` は空 |
| 開発の道具 | RDP の端末で `mise --version; uv --version; python --version; pnpm --version; ccmanager --version; git flow version; ulimit -n` | それぞれ動く。git flow は 1.12.3(AVH)。python は Python 3。ulimit -n は 65536 |
| Mermaid CLI | RDP の端末で `printf 'flowchart LR\n  A[開始] --> B[日本語のラベル]\n' >/tmp/t.mmd; for f in svg png pdf; do mmdc -i /tmp/t.mmd -o /tmp/t.$f; done` | 3 つとも出る。PNG・PDF の日本語が文字化けしない。sandbox のエラーが出ない |
| エージェントへの説明 | `sudo cat /home/<名前>/.claude/CLAUDE.md` | 「このホストについて」が置かれ、「あなたは <名前> ユーザーで」になっている |
| Orca のテレメトリ | RDP の端末で `echo $ORCA_TELEMETRY_DISABLED` | 1 |
| サービスの最小化 | `systemctl list-units --type=service --state=running`、`command -v snap orca` | cups・avahi・ModemManager・bluetooth・root の containerd・rsyslog が動いていない。snap と(読み上げの)orca がない |
| メモリ | `swapon --show; cat /proc/cmdline` | zram がある。crashkernel がない |
| GPU による符号化 | `vainfo --display drm --device /dev/dri/renderD128 \| grep EncSlice`、RDP でつないだあと `journalctl -b _UID=$(id -u <名前>) \| grep HWAccel` | Intel・AMD は `VAProfileH264High` に `VAEntrypointEncSlice`(か `EncSliceLP`)があり、`[HWAccel.VAAPI] Successfully initialized` が出る。NVIDIA は `lsmod \| grep nvidia` と `ldconfig -p \| grep libnvidia-encode`。VM では対象外 |
| Docker の通信 | 利用者全員が、RDP の端末で `docker run --rm alpine:3 wget -qO- http://example.com` | 全員が取得できる(pasta。just verify は pasta の設定までを見る) |
| UPS(ups を書いたとき) | ホストで `upsc <name>@localhost`(netclient なら `<name>@<server>`)。UPS の電源プラグを抜いて数十秒で挿しなおす | `ups.status` が `OL`。抜くと「停電: UPS のバッテリーで動いている」、挿すと「UPS: 電源が戻った」が届く。バッテリーが少なくなるまで待つと終了し、電源が戻ると起動する(usb のとき) |
| ディスクの監視 | `systemctl is-enabled agent-host-diskcheck.timer` | enabled |
| 移行 | 書き出し → 消す → 取り込み(docs/manual-steps.md の 16。just backup → 消す → just restore) | 利用者全員のログインと ~/work、本人が変えた RDP のパスワードが戻る |
| 各ツール | `node --version; codex --version; claude --version` | 60-devtools.sh に書いたバージョン |
| 利用者に sudo がない | `id <名前>` | sudo グループに入っていない。ホームは 700(`stat -c %a /home/<名前>`) |
