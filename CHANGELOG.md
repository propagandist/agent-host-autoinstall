# 変更の記録

版は [Semantic Versioning](https://semver.org/lang/ja/) で付ける。
パッチは固定したバージョンの更新、修正、文書の直し、マイナーは機能や env.yaml の項目の追加、
メジャーは env.yaml の互換性がなくなる変更(既存の env.yaml を直さないと ISO を作れない変更)。0.x のあいだは、互換性がなくなる変更もマイナーを上げる。
リリースは VM での受け入れテストが通ったら出す(実機での確認は必須にしない)。実機で問題が出たら hotfix(パッチの版)で直す。しばらく運用して問題がないと判断するまでは 0.x とする。手順は [docs/release.md](docs/release.md)。

各版の「env.yaml の変更」には、構成リポジトリ(docs/fleet.md)で道具の版を上げるときに、各ホストの env.yaml で直すことを書く
(項目の追加・名前の変更・使えなくなった値。なければ「なし」)。

## [未リリース]

### env.yaml の変更
- `vm` を足した(true か false)。書かなければ今までどおり(false)

### 追加
- env.yaml の `vm` を `true` にすると、QEMU/KVM と UEFI のファームウェアを入れ、利用者全員を kvm に入れる(66-vm.sh)。エージェントがそのホストで `just vm-test` を回せる。`false` に戻すと kvm から外す。`just verify` も見る(#35)
- `just vm-test` が QEMU/KVM でも動く。VBoxManage があれば VirtualBox、なくて QEMU と `/dev/kvm` があれば QEMU を選ぶ(`AGENT_HOST_VM_BACKEND` で決められる)。kvm のグループが今のセッションに効いていなければ `sg kvm` で実行しなおす(26.04 では `sg` が util-linux-extra にあるので、66-vm.sh で入れる)。転送のポートを `AGENT_HOST_VM_SSH_PORT`・`AGENT_HOST_VM_RDP_PORT_OFFSET` で変えられ、使われていれば入れなおす前に止まる(#35)
- Mermaid CLI(`mmdc`)12.0.0 を既定で入れる。エージェントが Mermaid の図を SVG・PNG・PDF に描き出せる。peer の puppeteer も 25.16.0 に固定して `/opt/mermaid-cli-<版>` に入れ、ブラウザは Google Chrome を使う(chrome-headless-shell は取らない)(#28)
- git-flow(AVH 版、Ubuntu の apt)を既定で入れる。エージェントが `git flow feature start` / `finish` で GitFlow のブランチ運用を行える(#33)
- `just verify` が利用者ごとの rootless Docker で `hello-world` を動かす(手元になければ取得し、終わったら消す。取得できなければ未検証)。pasta の設定(passt と drop-in)、`/etc/subuid`・`/etc/subgid` の範囲(利用者ごとに 65536 個以上で、重ならない)、env.yaml から外した利用者の Docker が止まっていることも見る(#29)
- 構成リポジトリのひな形に `just check-age-key <鍵>` を足した。その age の鍵だけで、暗号化したすべてのファイルを復号できるかを確かめる(sops は `SOPS_AGE_KEY_FILE` を渡しても手元の `keys.txt` も読むので、そのままでは確かめにならない)
- 構成リポジトリのひな形の `with-env.sh` が、暗号化していないファイルに秘密の値(`encrypted_regex` と同じ名前で、空でない値)があると止まる(値は出さず、行の番号だけを出す)。sops がないときは入れ方の案内を出す(#34)
- docs/fleet.md: 回復用の age の鍵と SSH の鍵を足すこと(3)、Windows での sops・age の入れ方と `sops edit` の `EDITOR`(3)、暗号化していない値も sops を通して変えること(3)、足した人の鍵の確かめ方(8)、鍵やパスワードをなくしたときの戻し方(10)を書いた。手順書の「複数台を管理する」にも要点を足した
- 手順書に、手元の PC の Orca からホストの Orca につなぐ手順(Remote Orca Server、ベータ)を足した。公式の文書から書き、LAN の IP で 6768 を足してつながることを確かめた。2 人目以降のポートと、版が違うときは未確認(#37)

### 修正
- Linux の手元で `just verify-rdp` が試験用の VM につながらなかった(Docker の中の FreeRDP が `host.docker.internal` を引けない)。手元が Linux なら Docker を `--network host` で動かす。`vm-test.sh` に実行の権限がなく Linux の just から動かなかったので付けた(#35)
- 65-docker.sh の subuid/subgid のコメントが「手で決める」になっていた。実際は useradd が割り当てるので、そう直した(#29)
- README の「秘密情報が入るファイル」に、ホストの `/opt/agent-host/users/`(利用者ごとの値。RDP の仮のパスワードを含む)が抜けていた。足した(手順書には書いてあった)
- docs/notes.md の「運用上の注意」の秘密情報が入るファイルにも、`/opt/agent-host/users/` と `/opt/agent-host.prev/` を足した
- 手順書の「ファイルのやり取り(SFTP)」に、つなぐ人が手元の PC で鍵を作る手順(`ssh-keygen -t ed25519`)と、公開鍵を env.yaml に書いて反映するまでの流れを足した(#38)
- 構成リポジトリのひな形の `.sops.yaml` の `path_regex` が `/` 区切りだけを見ていて、Windows の sops では `hosts/<ホスト>.yaml` が `no matching creation rules found` で暗号化できず、RDP の仮のパスワードが平文で残った。`/` と `\` の両方を許す。Windows でひな形から構成リポジトリを作っていたら、`.sops.yaml` の `path_regex` を `(^|[/\\])(common|hosts[/\\][^/\\]+)\.yaml$` にして `hosts/*.yaml` を暗号化し、平文で履歴に入った仮のパスワードは、まだ変えていない人に変えてもらう(#34)
- `just rdp` が、どの利用者の接続ファイルにもユーザー名 `agent` を入れていた。3 つ目の引数で `rdp.username` を渡す(省くとユーザー名を書かない)

### 確認した環境
- エージェントのホスト(core)の QEMU/KVM の VM(CPU 2、メモリ 4GB、利用者 2 人の env)で `just vm-test`(ae54f66)の 9 項目がすべて通った。入れなおしから 2 人の RDP が待ち受けるまで人手なし、`just verify`(210 項目)・`just verify-rdp`(2 人)、電源を切ったあとの戻り、1 人目の gnome-shell を落としてその人だけ戻り 2 人目が続くこと
- 同じ VM の利用者 2 人で、`mmdc` の SVG・PNG・PDF(PNG の日本語は目視で文字化けなし)と、`git flow` の init・feature start・finish。2 回目の just update で Mermaid CLI を入れなおさないこと
- 未確認: 関数に寄せた vm-test の VirtualBox の版、PDF の日本語の目視

### 文書
- Windows のリモート デスクトップ接続(mstsc)で、手元の Windows Hello の PIN や指紋を求められたときの対処(「その他」→「別のアカウントを使用する」)と、「このアカウントを記憶する」で保存されないときに `cmdkey` で保存する方法を、手順書に書いた

## [0.3.2] - 2026-10-27 — 実機で固まるのを直す版

### env.yaml の変更
- なし

### 修正
- gnome-shell のメモリに上限(物理メモリの 30%、swap 512MB)を付けた。漏れて膨らむと、swap に逃げながら応答しなくなり、systemd-oomd も動かないまま 20〜40 分続いてから OOM で落ちた。上限で落とせばセッションがすぐ立ちなおる(Orca の端末とエージェントは残る)(#36)
- 日本語入力を IBus の Mozc から fcitx5 の Mozc に替えた。RDP の半角/全角キーは押しっぱなしで届いてリピートし続ける。IBus の Mozc では、そのたびに gnome-shell がメモリを漏らし、実機で 10GB を超えて応答しなくなり、OOM で落ちた。fcitx5 なら漏れない(実機で確認)。ibus-mozc を消し、IBus のデーモンを mask し、user の `agent-host-fcitx5.service` で fcitx5 を起動する。入力ソースは配列だけにし、Ctrl+Space は fcitx5 の切り替えに渡す。半角/全角キーは日本語にするだけ、無変換キーは英字にするだけにし、Mozc の割り当て(MS-IME)からは半角/全角を外す(押しっぱなしで届いても、切り替えを繰り返さない)。fcitx5 と Mozc の設定は、利用者のホームにないときだけ置く。just update で上げたホストでは、動いているセッションはその場で fcitx5 に替わり、入力ソースとキーの割り当ても直る(セッションが動いていなければ、次にセッションが立つとき)(#36・#21)

### 確認した環境
- 実機(AMD Renoir、RAM 約 15GB、v0.3.1 で構成したホスト)で、原因を確かめた。IBus の Mozc では、RDP の半角/全角の押しっぱなしで gnome-shell が漏れて固まり、OOM で落ちた(同じ日に 2 回)。漏れた gnome-shell は 11 秒ごとに約 0.6 秒止まり、立てなおすと止まらなくなった
- 同じ実機で、sudo なしで展開した fcitx5 5.1.19 と fcitx5-mozc 2.29 を動かし、同じ押しっぱなしで漏れないこと、日本語を変換できること、半角/全角で日本語のまま止まり、無変換で英字に戻ることを確かめた(このリポジトリの post-install を root で動かしたのではない)
- `just test`(Docker の中)と shellcheck、`just release-check`(手元の PC と実機)
- VirtualBox の VM(Windows、メモリ 4GB、CPU 1、利用者 2 人の env)で `just vm-test`。入れなおしから 2 人の RDP が待ち受けるまでと、電源を切ったあとの戻りは人手なしで通った。sudo のパスワードの入れ違いで検査が動かなかったので、同じ VM で `AGENT_HOST_VM_REUSE=1` でやりなおし、`just verify`(213 項目)・`just verify-rdp`(2 人)、電源を切ったあと、1 人目の gnome-shell を落としてその人だけ戻り 2 人目が続くことが通った
- VM(CPU 1)の RDP では、押していない文字が重複して入ることがあった。gnome-shell は漏れていなかったので CPU の不足と見ている(測ってはいない)。実機では起きていない
- 未確認: just update で上げたときにその場で fcitx5 に替わること、gnome-shell がメモリの上限で落ちたときに立ちなおること

## [0.3.1] - 2026-10-25 — 構成リポジトリのひな形を直す版

### env.yaml の変更
- なし。v0.3.0 のひな形で構成リポジトリを作っていたら、その `.sops.yaml` の `encrypted_regex` に `initial_password` を足し、`common.yaml` と `hosts/*.yaml` を復号してから暗号化しなおす(`sops --decrypt --in-place` のあと `sops --encrypt --in-place`)。仮のパスワードは平文で履歴に入っているので、まだ RDP のパスワードを変えていない人には変えてもらう

### 修正
- 構成リポジトリのひな形(examples/fleet/.sops.yaml)が `users[].rdp.initial_password` を暗号化の対象にしておらず、RDP の仮のパスワードが平文で構成リポジトリに入った。対象に足し、tests/test_render.py で、ひな形の秘密の値のキーがすべて対象に入っていることを確かめる(#27)

### 確認した環境
- `just test`(Docker の中)。ホストに置くものは変えていないので、VM での入れなおしは行っていない

## [0.3.0] - 2026-10-25 — 利用者ごとにセッションを分ける版

### env.yaml の変更
- **利用者を `users` の並びにした(互換性がなくなる変更。#15)。** `rdp`・`git_user_name`・`git_user_email`・`agent_ssh_authorized_keys` は使えなくなり、書くと書き換え先を出して止まる。0.2 のホストは次のように書き換えると、今の `agent` のホーム・ログイン・RDP の証明書をそのまま使える
  ```yaml
  users:
    - name: agent
      port: 3389
      rdp: {username: <rdp.username>, initial_password: <rdp.password>}
      git_user_name: <git_user_name>
      git_user_email: <git_user_email>
      ssh_authorized_keys: <agent_ssh_authorized_keys>
  ```
- `users[].port` は必須で、`dev_ports` と重ねられない。`dev_ports` に `"3000:3999"` などの 3389 を含む範囲を書いていたら狭める(例 `"3000:3099"`)
- `rdp.password` は `users[].rdp.initial_password`(初回だけの仮の値)になった。本人が最初の RDP で `grdctl --headless rdp set-credentials` で変え、RDP のデーモンを再起動する(manual-steps の 4)。just update は認証情報がまだないときだけ入れる
- 0.2 のホストに just update すると、途中で GDM を再起動して seat0 のセッション(自動ログイン)を終わらせ、ヘッドレスのセッションに移る。端末やエージェントは終わるので、作業していないときに行う

### 変更
- 利用者ごとに Linux のユーザー、ヘッドレスの GNOME のセッション、RDP のポートを分けた(#15)。1 台を複数の人で使っても、Claude Code・Codex などのログイン(サブスクリプション)が人ごとに分かれる。1 人の台も同じ作り
  - seat0 の自動ログイン、デスクトップ共有、セッションの見張り(20-autologin.sh、watchdog)をやめ、`gnome-headless-session@<名前>` と gnome-remote-desktop の headless にした(20-sessions.sh、88-start-sessions.sh)。ユニットのままでは立たず、落ちても戻らないので、drop-in で `DynamicUser=no`・`User=gdm`・`Restart=always` にした(VirtualBox で確かめた。notes.md「段 0」)
  - 画面ロックはセッションを立てる前に止める(立てた直後にロックされ、パスワードのない利用者は外せなかった)。HDMI のダミープラグは要らない
  - env.yaml から外した利用者は、ユーザーとホームを残したまま、期限切れ・`AllowUsers` から外す・セッション・linger・rootless Docker・ufw のポートを止める
  - `just verify-rdp` は利用者ごとに確かめ、仮のパスワードで通らなければ「未検証」と出す。`--ask <利用者>` で今のパスワードを確かめる。`just rdp <ホスト> <ポート>`
  - `just verify`・`status`・`facts`・`logs`、移行(全員のホームを書き出し、名前で合わせて取り込む)、通知(`[ホスト名/利用者名]`)、`just vm-test`(2 人の env で、片方のセッションを落としてもう片方が続くこと)を利用者ごとにした

### 追加
- `python` コマンド(python-is-python3)を入れた。`python tools/x.py` のように Windows や setup-python を前提に書かれた手順が `python: not found` で止まった。エージェント向けの説明の mise の例に `mise use -g just` を足した(説明がすでにあるホストには届かない)(#20)
- PDF ビューアー(Atril)を入れ、agent の PDF の既定のアプリにした。just verify に「Atril」の確認(#19)
- zram に合わせて、スワップの sysctl を vm.swappiness 180・vm.page-cluster 0 にした。just verify に 2 つの値の確認(#18)
- RDP の接続ファイルのひな形(just rdp)で、回線の自動検出(networkautodetect)を有効にした。遅延の大きい回線で、ホストが送る量を絞りすぎないため。色 24 ビットの説明を事実に合わせた(グラフィックス パイプラインではホストは 32 ビットで送る)(#17)
- メモリ不足のときに systemd-oomd が Orca ごと止めるかを VM で確かめた。Orca 1.4.237 は端末ごとに cgroup を分けるので、止まるのは暴走した端末だけだった。設定は変えず、技術メモに記録した(#16)
- 直下に Orca がプロジェクトを登録するときに拾うアイコン(icon.png、256×256 の PNG)を置いた。元の絵は docs/icon.svg。owner のアバターが入り、同じ owner のほかのリポジトリと見分けがつかなかった(#25)

### 修正
- 移行の書き出し(agent-host-backup)が root の tar でホームを読んでいたため、利用者が途中のディレクトリを root だけが読めるディレクトリへのリンクにしておくと、利用者に読めない root のファイルが書庫に入り、取り込みで利用者の持ち物になった。取り込み(agent-host-restore)も root で展開していたため、ホームに元からある相対パスのリンクをたどってホームの外に書けた。ホームの分は、書き出しも取り込みも利用者の権限で行う(書庫は root の tar のあとに利用者ごとの tar が続く形。v0.2.0 の書き出しも取り込める)。tests/test_backup.py で、どちらも起きないことを確かめる。利用者に読めないもの(rootless Docker のデータなど)は書き出さず、一覧を出す(#23)
- 入力ソースに Mozc が 2 つ並び、Ctrl+Space の切り替えに 2 つ出た。Ubuntu の gnome-settings-daemon が、初めてのセッションでロケールの mozc-jp を足していた。first-login で足させないようにし、すでに足されたものはセッションが立つときに外す。just verify に「入力ソースの Mozc は 1 つ」
- 80-agent-session.sh の古い設定(50-proxy-ca.conf)の削除が root のままで、途中のリンクでホームの外の同じ名前のファイルを消せた。利用者の権限で消す。tests/test_agent_home.py に、末端がディレクトリへのリンクのときの write_agent_file の試験を足した(#24)

### 確認した環境
- VirtualBox 7.2 の VM(UEFI、メモリ 4GB、CPU 1)、利用者 2 人の env。release ブランチの `just vm-test` で新しく入れなおし(`keyboard_layout` は us と jp の両方で通した)、人手なしで 2 人の RDP が待ち受けること、`just verify`(jp で 195 項目)・`just verify-rdp`(2 人)、電源を切ったあとの戻り、1 人目の gnome-shell を落としてその人だけ戻り 2 人目が続くことを確かめた
- 動いている VM に `just update` で反映する道も確かめた。RDP で 2 人が同時につなげること、互いのホームが読めないこと、本人が RDP のパスワードを変えられることを画面で確かめた
- 利用者 2 人で、片方がメモリを使い切ったとき、systemd-oomd がその人の単位だけを止め、もう 1 人のセッション・RDP・Orca が続くことを確かめた(docs/notes.md)
- 移行の書き出しと取り込みは `just test`(Docker の中)と、VM での書き出し・取り込み・再起動で確かめた(本人が変えた RDP のパスワードが残ること)。別の VM へ入れなおしての通しは確かめていない
- env.yaml の `users` から外した利用者が、古い鍵で SFTP にもシェルにも入れないことを VM で確かめた
- GPU による符号化は、VM に GPU がないので確かめていない
- 実機は未確認(モニターのないヘッドレスのセッション、電源が戻ったときの起動、LAN の外から届かないこと、プロキシ、Slack、クラウドへのログイン、実際の UPS、実機の GPU、Orca Mobile のペアリング、0.2 のホストから just update で上げること)。問題が出たら hotfix で直す

## [0.2.0] - 2026-10-25 — 機械で確かめる版

### env.yaml の変更
- `ups` を足した(UPS を NUT で見る。書かなければ使わない。項目は autoinstall/env.example.yaml)
- **`sysadmin.ssh_authorized_keys` と `sysadmin.password_hash` は、just update のたびにホストへ反映するようになった(#2)。** 版を上げて just update する前に、`ssh_authorized_keys` に今つないでいる鍵が入っているか、`password_hash` が今の sudo のパスワードと同じかを確かめる(ホストで passwd で替えていたら、env.yaml の値に戻る)
- 検査を強めた(#8)。これまで通っていた env.yaml が `just check-env` で止まることがある: 項目の型(並びの項目に文字列、文字列の項目に引用符のない数や true/false)、hostname(英数字と - の 63 文字以内。ドメインは付けない)、`sysadmin.password_hash`(`$6$`・`$5$`・`$y$`・`$2b$` などの形)、SSH の公開鍵の形(`from="..."` などのオプションの付いた行は書けない)、`dev_ports` の範囲の順、`notify.ipmsg_broadcast`(IPv4 だけ)

### 追加
- 機械で確かめる仕組み(docs/acceptance-test.md「機械で確かめる」)
  - `just test`: env.yaml の検査(知らないキー、SOPS のまま、書き忘れ、値の形、組み合わせ)、重ね方、env.sh と /opt/agent-host に置くものの形の試験(tests/)
  - `just verify <ホスト>`: ホストが仕様どおりかを 100 項目あまりで確かめる(読むだけ)。固定した版は、そのホストの post-install/ の値と比べる。ホストの上では `sudo /opt/agent-host/verify.sh`
  - `just verify-rdp <ホスト>[:ポート]`: env.yaml の rdp で RDP の認証(NLA)が通るか(FreeRDP の +auth-only。画面は開かない)
  - `just vm-test`: VirtualBox の VM に入れなおし、検査、電源を切ったあと、セッションが落ちたあとの戻りを通しで確かめる
- `just release-check` で `just test` も行う
- UPS への対応(env.yaml の ups、85-ups.sh): NUT で UPS を見て、バッテリーが少なくなったら(か NUT サーバーの指示で)正しく終了する。USB でつないだときは終了の最後に UPS の出力を止め、電源が戻ったら BIOS の設定で起動させる。停電・復電・まもなく終了を agent-notify で知らせる。just verify に「UPS」の確認
- RDP の画面の符号化を GPU に任せる(37-gpu.sh): Intel は VA-API の full 版(intel-media-va-driver-non-free)、Vulkan のドライバー、vainfo。NVIDIA は autoinstall の drivers でプロプライエタリ ドライバーをインストールの中で入れる。just verify に「GPU」の確認
- なぜ Orca で動かす専用の PC を用意するのか(手元の PC を閉じられない、並べて見比べる、任せる範囲を分ける、止まらない、同じものを作れる)と、なぜ Orca か(2026-10-24 に代替と比べた条件と結果)を README・SPEC・手順書・notes に書いた
- Orca Mobile(スマホから Orca を操作するアプリ)の使い方と注意を手順に書いた(LAN なら dev_ports に 6768、外からは VPN か Orca Relay)。設定の追加はなし

### 修正
- `just update` で root が agent のホームを書き換えるとき、agent の置いたシンボリックリンク(末端・途中のディレクトリ)をたどって、ホームの外の root のファイルを書き換えたり所有者を変えたりできた。agent のホームへの書き込みは、すべて agent の権限で行う(#1)
- `sysadmin.ssh_authorized_keys` と `sysadmin.password_hash` を替えて `just update` しても反映されず、退任した人の鍵とパスワードが残った。`just update` のたびに env.yaml に合わせる(手で足した鍵は消える。反映のあと入りなおせるかを確かめる)(#2)
- 移行の書き出しが名前だけ(dist、target、venv、.cache など)で除いていたため、~/work の同じ名前のディレクトリの中の未コミットの変更・未追跡のファイル、同じ名前のファイル、同じ名前のブランチが消えた。~/work の中で見つけた node_modules・__pycache__・.venv のパスと、Orca のキャッシュだけを除き、除いたものを取り込みの最後に出す(#4)
- 入れなおしたホストは SSH のホスト鍵が新しく、移行の手順どおりに進めると取り込みの前に「REMOTE HOST IDENTIFICATION HAS CHANGED」で止まった。取り込むまでは一時の known_hosts でつなぎ、指紋を新しいホストの画面で照らす手順を、手順書・manual-steps・fleet.md に書いた(#11)
- xrdp を採らなかった理由を、「Ubuntu 26.04 は Wayland だけで xrdp が使えない」から、「xrdp は別のセッションを作るので自動ログインした Orca が見えない。GNOME のセッションは 25.10 から Wayland だけで xrdp では動かない(Xfce などは動く)」に直した(#14)
- 移行の書き出しに、クラウドの CLI(~/.aws、~/.config/gcloud、~/.azure)、Gitea CLI(~/.config/tea)、mise の全体の設定(~/.config/mise)が入っていなかった。足した(gcloud の記録は除く)(#7)
- 独自の CA 証明書(ca_certs)を OS に入れても、構成の途中の npm(Node.js)はそれを使わず、TLS を検査するプロキシの下では止まった。provision.sh が NODE_EXTRA_CA_CERTS などを渡す。apt の取得元の更新は、プロキシと CA の設定のあとに行う(#6)
- just update が途中で失敗しても、`just status` が「構成: 済み」と新しい版を出し、成功と区別できなかった。provision.sh が実行中の印を置いて成功したら消し、成功した版を BUILD-INFO.ok に残す。status は「置いた版」「最後に適用に成功した版」と「前回の実行が最後まで終わっていない」を出し、verify も確かめる(#10)
- env.yaml のどの項目が just update で反映されるかが分からず、壁紙の色と Dock は first-login の一度きりで変わらなかった。項目ごとの線引き(update・セッション・インストールだけ)を render-autoinstall.py の UPDATE_SCOPE と文書の表に持ち、試験で漏れを確かめる。壁紙の色と Dock はログインのたびの自動起動(desktop-env.sh)が、変わったときだけ入れなおす(ログイン中ならその場で)(#13)
- UPS の netclient では nut の HOME(/var/lib/nut)が無く、停電などの通知が送られなかった。mode に関わらず作り、agent-notify は記録を書けなくても送る(#5)
- 手元の一時ファイル(build/.env など)と構成リポジトリのひな形の復号先(build/.dec/<ホスト>)を固定の名前で共有していたため、並行に動かすと別のホストの env.yaml が混ざったり、先に動いているほうの入力が消えたりした。実行ごとのディレクトリ(build/.run.XXXXXX、build/.dec/<ホスト>.XXXXXX)に分ける(#9)
- `/dev/dri` が無いと just verify が途中で終わり、集計まで届かなかった(#12)
- `rdp.password` を替えて `just update` しても、古い RDP の認証情報が有効なままだった。替えたら渡しなおし、ログイン中ならその場で、そうでなければ次のログインで入れ替える。移行の取り込みのあとも、このホストの認証情報を入れなおす(#3)
- 初回の構成のあいだ起動画面(plymouth)が出たままで CPU を使い、GDM の起動で異常終了して plymouth-start.service が failed で残った。構成の最初に起動画面を閉じ(進み具合はコンソールに出る)、GRUB でも splash を外した(just vm-test で見つかった)

### 変更
- リポジトリの作業の決まりに、複数のエージェントでのレビューと起票、Issue のトレーラー(Co-Authored-By)を足し、AGENTS.md(CLAUDE.md を参照する)を置いた
- 1 台を複数の人で共有する前提(デスクトップ共有に入る前に一声かける)をやめ、1 台は 1 人で使う(サブスクリプションを共有しない)前提に文書を直した。複数の人で使うときは人数分のホストを用意する
- リリースのワークフローの actions/checkout を v5 にした(Node.js 20 の廃止の警告への対応)
- Intel の VA-API を free 版から full 版にした(36-minimize.sh から 37-gpu.sh に移した)。動いているホストは just update で入れ替わる。NVIDIA の GPU があるホストでドライバーが無ければ、構成の記録に注意が出る(sudo ubuntu-drivers install のあとに再起動)

### 確認した環境
- VirtualBox 7.2 の VM(UEFI、メモリ 4GB、CPU 1)。`just vm-test` で新しく入れなおし、`just verify`・`just verify-rdp`、電源を切ったあと、gnome-shell を落としたあとの戻りを確かめた(結果は docs/notes.md)
- 動いている VM に `just update` で反映し、sysadmin の鍵とパスワード、RDP のパスワード、壁紙の色の入れ替え、更新の失敗と回復、UPS(NUT の dummy-ups)の停電・復電の通知と強制終了を確かめた
- GPU による符号化は、VM に GPU がないので確かめていない(verify は「対象外」と出す)
- 実機は未確認(ダミープラグでの RDP、電源が戻ったときの起動、LAN の外から届かないこと、プロキシと TLS を検査するプロキシ、Slack、クラウドへのログイン、実際の UPS、実機の GPU、Orca Mobile のペアリング)。問題が出たら hotfix で直す

## [0.1.0] - 2026-10-24 — 最初の版

### env.yaml の変更
- 最初の版なので、なし(項目は autoinstall/env.example.yaml)

### 追加
- Ubuntu Desktop 26.04 LTS の autoinstall で、USB メモリ 1 本から無人でインストールし、初回起動時に構成する
- GDM の自動ログイン、空パスワードのキーリング、GNOME のデスクトップ共有(RDP)を、再起動のあとも人手なしで戻す。セッションが落ちたら GDM を再起動する見張り
- SSH は鍵認証のみ、agent は SFTP 専用。ufw で LAN だけに許可
- Orca、Claude Code、Codex、CCManager、GitHub CLI、Gitea CLI、Node.js、uv、mise、rootless Docker、Google Chrome。追加のエージェント(OpenCode、Copilot CLI、Antigravity CLI)とエディター(VS Code、Neovim、Zed)は env.yaml で選ぶ
- クラウドの CLI(AWS CLI v2、Google Cloud CLI、Azure CLI)を env.yaml の clouds で選んで入れる
- VS Code の拡張機能を版を固定して入れる(基本、Python・JavaScript、GitHub Pull Requests、clouds に合わせたクラウド)。env.yaml の vscode_extensions で足せる。表示は日本語にする
- Zed の拡張機能を初めて起動したときに入れる(TOML、Docker、HTML、Make、SQL ほか)。env.yaml の zed_extensions で足せる
- env.yaml で、キーボード配列、ネットワーク(DHCP・固定 IP)、プロキシと CA 証明書、NTP、壁紙の色、開発用のポート、Gitea の URL を指定する
- 日本語入力(Mozc、Ctrl+Space)、Xfce Terminal、Clipboard Indicator、スクリーンショットのキー、英語のフォルダー名
- 要らないサービスを止め、snap・snapd・kdump と使わないパッケージ(画面の読み上げ、印刷のドライバー、AD・LDAP、VPN・モデム、Bluetooth、報告など)を消して最小化。zram、電源のプロファイル
- 承認待ち・エラー・完了を Slack と IP Messenger(名前で探す)に通知。ディスクの残りの監視
- 環境を入れ替えるときの書き出しと取り込み(agent-host-backup、agent-host-restore)
- 実機の構成を別のリポジトリで管理するための仕組み(docs/fleet.md、ひな形 examples/fleet/)。env.yaml を重ねて使う(共通 + ホスト)、知らないキーをエラーにする、リポジトリの外の env.yaml を扱う、作った版をホストの BUILD-INFO に残して just status に出す、台帳のための just facts
- ライセンスは Apache License 2.0(著作権者の表示は NOTICE)
- 手元の作業をまとめた justfile(ISO の作成、検査、状態・記録・更新・移行、RDP の接続ファイル、手順書の PDF)
- 技術メモ(docs/notes.md): 検証した環境、設計で決めたこと、調査と検証の記録、確認できていないこと
- 詳細な設定手順書(docs/setup-guide.tex)。表紙、色付きの囲み、図、チェックリスト付きの PDF を Docker の TeX Live で作る
- リリースの手順(docs/release.md)と、タグの push で手順書の PDF を GitHub Release に付けるワークフロー

### 確認した環境
- VirtualBox 7.2 の VM(UEFI、メモリ 4GB。Windows のホストで Hyper-V と共存させたため CPU 1)で、release/0.1.0 の ISO から新しく入れなおし、無人インストールから RDP の接続まで。受け入れテスト 1〜6・8 はこれまでの VM で確かめた(docs/notes.md)
- 実機は未確認(ダミープラグでの RDP、停電復帰、LAN の外から届かないこと、プロキシ、Slack、クラウドへのログイン、Zed での日本語入力)。問題が出たら hotfix で直す
