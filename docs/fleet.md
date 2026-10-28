# 実機の構成管理

ホストが 1 台を超えたら、このリポジトリ(道具)とは別に、実機の構成を管理する非公開のリポジトリ(構成リポジトリ)を作る。
道具は公開してもよい汎用のもので、実機の情報(ホスト名、IP、LAN の範囲、公開鍵、通知先、秘密情報)は持たない。
構成リポジトリは、どのホストを、どの設定で、どの版の道具から作ったかを記録し、変更をレビューできるようにする。

ひな形は [examples/fleet/](../examples/fleet/) にある。

## 1. 役割分担

| | 道具(このリポジトリ) | 構成リポジトリ |
|---|---|---|
| 置く場所 | GitHub(公開してよい) | 非公開の Git リポジトリ(自前の Gitea、GitHub の private など) |
| 中身 | autoinstall、構成のスクリプト、手順書、just のレシピ | ホストごとの env.yaml、台帳、受け入れテストと変更の記録 |
| 版 | リリースのタグ(v0.1.0 など) | 構成リポジトリのコミット |
| 秘密情報 | 持たない | SOPS と age で値だけ暗号化して持つ |
| つながり | — | 道具を `tool/` に submodule で置き、リリースのタグに固定する |

置かないもの: ISO(秘密情報が入る。作ったら USB に書き込んで消す)、移行の書き出し(ログインの情報が入る。暗号化された別の場所に置く)、age の秘密鍵(各自の手元とパスワード管理に置く)。

## 2. 構成リポジトリの中身

```
tool/                    道具(submodule、リリースのタグに固定)
common.yaml              全台で共通の値
hosts/<ホスト>.yaml      ホストごとの値(common.yaml に重ねる)
facts/<ホスト>.yaml      just facts が書く、ホストの情報
docs/inventory.md        台帳
docs/hosts/<ホスト>.md   受け入れテストの結果と変更の記録
scripts/with-env.sh      復号して道具に渡し、終わったら消す
.sops.yaml               暗号化する値と、復号できる人
justfile                 just check / iso / update / status / facts など
```

env.yaml は、前から順に重ねて使う(道具の `render-autoinstall.py`)。後のファイルの値が勝つ。辞書(`network`、`notify` など)はキーごとに重なり、並び(`editors`、`lan_cidrs`、`users` など)と値は置き換わる。利用者(`users`)はホストごとに違うので、`hosts/<ホスト>.yaml` にそのホストの全員を書く。知らないキー(書き間違い)はエラーになる。

作ったホストの `/opt/agent-host/BUILD-INFO`(置いた版)と `/var/lib/agent-host/BUILD-INFO.ok`(構成が最後まで成功した版)には、道具の版、構成リポジトリの版(`AGENT_HOST_CONFIG_REV`)、使った env のファイル名、作った日時が残る。`just status` と `just facts` で見える。

## 3. 構成リポジトリを作る(最初に 1 回)

要るもの(作業する人の手元): just、Git Bash(Windows)、Docker Desktop、[sops](https://github.com/getsops/sops)、[age](https://github.com/FiloSottile/age)。

Windows では、sops は Scoop(`scoop install sops`)で、age は winget(`winget install FiloSottile.age`。Scoop の main バケットにはない)で入れる。
winget が足した PATH は、新しく開いたターミナルから効く。sops は age を内蔵しているので、age の CLI は鍵を作るときだけ使う。
`sops edit` は環境変数 `EDITOR` のエディターで開き、なければ vim・nano・vi を探して、見つからないと `no editor available` で止まる。
VS Code なら `EDITOR` を `code --wait` にする(編集して保存し、タブを閉じると、sops が暗号化しなおして書き戻す)。

1. 非公開の Git リポジトリ(自前の Gitea、GitHub の private など)に、非公開の空のリポジトリを作る
2. ひな形をコピーし、道具を submodule で足して、使う版に固定する
   ```
   cp -r <道具>/examples/fleet/. <構成リポジトリ>/
   cd <構成リポジトリ>
   git init
   git submodule add https://github.com/<組織>/agent-host-autoinstall.git tool
   git -C tool checkout v0.2.0
   just setup
   ```
3. 作業する人ごとに age の鍵を作る(秘密鍵は手元とパスワード管理に置き、リポジトリには入れない)
   ```
   age-keygen -o ~/.config/sops/age/keys.txt     # Windows では %AppData%\sops\age\keys.txt
   ```
   表示された公開鍵(`age1…`)を `.sops.yaml` の `age:` に並べる。あわせて回復用の鍵を 1 つ作り、その公開鍵も並べる。
   回復用の秘密鍵は、パスワード管理の、管理する人だけが見られる共有の保管庫にだけ置き、普段は使わない。
   受け手が作業する人の鍵 1 つだけだと、その鍵をなくしたときに誰も復号できなくなる(10 を見る)。
   sysadmin の SSH の鍵(`sysadmin.ssh_authorized_keys`)も同じく、回復用の鍵を 1 つ足しておく
4. `common.yaml` に全台で共通の値を、`hosts/<ホスト>.yaml` にホストだけの値を書き、秘密情報を暗号化する
   ```
   sops --encrypt --in-place common.yaml
   sops --encrypt --in-place hosts/agent-host-01.yaml   # ホストのファイルに秘密情報を書いたときだけ
   just check agent-host-01
   ```
   暗号化したファイルは `sops edit common.yaml` で開くと、復号して編集し、保存するときに暗号化しなおす。
   暗号化していない値(SSH の公開鍵など)も、エディターで直接書き換えない。sops はファイル全体の改ざん検知の値(MAC)を
   持っているので、直接書き換えると `MAC mismatch` で復号できなくなる(`sops edit` か `sops set` で変える)。
   暗号化していないファイルに秘密の値が残っていると、`just check` などは止まる(暗号化に失敗したまま気づかずにコミットしないように)
5. コミットして push する

## 4. ホストを足す

1. `hosts/<ホスト>.yaml` を作る(ファイル名はホスト名と同じ)。IP と壁紙の色を、ほかのホストと変える。`users` にそのホストを使う人を書く(`port` は人に固定する。`rdp.initial_password` は仮の値なので、`sops` で暗号化する)
2. 検査して ISO を作る
   ```
   just check agent-host-02
   just iso agent-host-02          # build/agent-host-02.iso(秘密情報が入る)
   ```
3. USB に書き込み、ISO を消す。インストールし、初回の手作業と受け入れテストを行う(道具の手順書)
4. 台帳と記録を書く
   ```
   just facts agent-host-02        # facts/agent-host-02.yaml
   ```
   `docs/inventory.md` に 1 行足し、`docs/hosts/agent-host-02.md` に受け入れテストの結果を書く
5. コミットして push する

## 5. 設定を変える

1. `common.yaml` か `hosts/<ホスト>.yaml` を直す(暗号化したファイルは `sops <ファイル>` で開く)
2. 検査し、レビューを受けてから main に入れる
   ```
   just check-all
   ```
3. 反映する(OS は入れなおさない)
   ```
   just update agent-host-01                 # 名前で引けないときは: just update agent-host-01 192.0.2.10
   just status agent-host-01                 # 置いた版と最後に適用に成功した版に、いまの構成の版が出る
   just verify agent-host-01                 # 仕様どおりかを確かめる(✗ がないこと)
   ```
4. `docs/hosts/<ホスト>.md` の変更の記録に、理由と手でしたことを書く

ufw の許可は足すだけなので、`lan_cidrs` や `dev_ports` から外したものは手で消す(道具の手順書の「設定やバージョンを変える」)。利用者の RDP のポートは、外した人の分を `just update` が消す。

### 利用者を足す・外す

1. `hosts/<ホスト>.yaml` の `users` に足すか、外す(ほかの人の `port` は変えない)
2. `just check <ホスト>` → レビュー → `just update <ホスト>`
3. 足したとき: 本人に接続先(`<ホスト>:<port>`。`just rdp <ホスト> <port> <rdp.username>` で接続ファイルを作れる)と仮のパスワードを渡し、最初の RDP で自分のパスワードに変えてもらう(道具の manual-steps の 4)。`just verify-rdp <ホスト>` で、その人が仮のパスワードで通ることを確かめる
4. 外したとき: ユーザーとホームは残り、ログイン・セッション・ポートが止まる。`just verify <ホスト>` の「外した利用者」で確かめる。ホームの中を消すなら、本人に確かめてから手で消す
5. 台帳の「使う人・用途」を直す

`just verify-rdp <ホスト>` は、仮のパスワードで通らなかった人を「未検証」と出す(本人が変えていれば正常で、失敗にはしない)。今のパスワードで確かめるなら、本人に `just verify-rdp <ホスト> ask=<名前>` を実行してもらう。

## 6. 道具の版を上げる

1. 道具の CHANGELOG を読む。特に「env.yaml の変更」の欄(項目の追加・名前の変更・使えなくなった値)
2. submodule を新しいタグにし、すべてのホストの env.yaml を検査する
   ```
   git -C tool fetch --tags
   git -C tool checkout v0.3.0
   just check-all
   ```
   止まったら、CHANGELOG に従って `common.yaml` や `hosts/` を直す

   0.2 から 0.3 に上げるときは、`rdp`・`git_user_name`・`git_user_email`・`agent_ssh_authorized_keys` を `users` に書き換える。
   今の `agent` のホームと RDP の証明書をそのまま使うなら、1 人目を `name: agent`・`port: 3389` にする。
   `dev_ports` に `3000:3999` のような 3389 を含む範囲があれば、`port` と重なって止まるので狭める。
   `just update` は途中で GDM を再起動するので、seat0 のセッション(端末やエージェントの作業)は終わる。作業していない時間に行う
3. 1 台で試す。反映し、`just verify` と、受け入れテストの 4・5(RDP と、エージェントが動くこと)を行う(`just verify-rdp` は、パスワードを変えた人を「未検証」と出す)
   ```
   just update agent-host-01
   just verify agent-host-01
   just verify-rdp agent-host-01
   ```
4. 問題がなければ、残りのホストに反映する。台帳の「道具の版」を直す
5. submodule の更新と台帳を、1 つのコミットにして push する

## 7. 入れなおす・機種を替える

1. 書き出す(構成リポジトリの外の、暗号化された場所に)
   ```
   just backup agent-host-01 <暗号化された場所>/agent-host-01-<日付>.tar.zst
   ```
2. 同じ `hosts/<ホスト>.yaml` で `just iso` を作り、入れなおす(機種を替えるときは、台帳の機種・MAC も直す)
3. 取り込み、再起動する。入れなおしたホストはホスト鍵が新しいので、取り込むまでは一時の known_hosts でつなぎ、
   最初に出る指紋を新しいホストの画面の `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` と照らす(道具の手順書の「環境を入れ替える」)
   ```
   export AGENT_HOST_SSH_OPTS="-o UserKnownHostsFile=$PWD/build/known_hosts.migrate"
   just restore agent-host-01 <暗号化された場所>/agent-host-01-<日付>.tar.zst
   unset AGENT_HOST_SSH_OPTS; rm -f build/known_hosts.migrate
   just ssh agent-host-01            # sudo systemctl reboot
   ```
4. `just verify` と受け入れテストの 4・5 を行い、`just facts` と記録を更新する。書き出したファイルは消す

ホスト鍵と、利用者ごとの RDP の証明書と認証情報(本人が変えたパスワード)も移るので、取り込んだあとは、手元の known_hosts と RDP の「今後確認しない」をそのまま使える(取り込むまでは使えない。known_hosts の古い鍵は消さない)。

## 8. 作業する人が増える・減る

増える:
1. 新しい人が age の鍵を作り、公開鍵を渡す
2. `.sops.yaml` に公開鍵を足し、すべての暗号化したファイルに反映する
   ```
   sops updatekeys common.yaml
   for f in hosts/*.yaml; do grep -q '^sops:' "$f" && sops updatekeys "$f"; done
   ```
3. 新しい人が、自分の鍵だけで復号できるかを確かめる。sops は `SOPS_AGE_KEY_FILE` を渡しても手元の `keys.txt` も読むので、
   ほかの鍵を持っている人が `sops --decrypt` を試しても確かめにならない。`just check-age-key` は、渡した鍵だけを使わせる
   ```
   just check-age-key ~/.config/sops/age/keys.txt     # Windows では "$env:APPDATA\sops\age\keys.txt"
   ```
4. SSH の公開鍵を `sysadmin.ssh_authorized_keys` に足して `just update` する(いま入れる人が行う)

減る:
1. `.sops.yaml` から公開鍵を外し、上と同じように `sops updatekeys` する
2. その人が知っている秘密情報を替える(過去のコミットは、その人の鍵で復号できるため)
   - RDP のパスワード: 利用者が自分で変えたものは、ほかの人には知られていない。仮のパスワード(`rdp.initial_password`)のままの人には、変えてもらう
   - sysadmin のパスワード: `sysadmin.password_hash` を替えて `just update`(ホストのパスワードもこの値に置き換わる)
   - Slack の Webhook: Slack で作りなおして `notify.slack_webhook_url` を替え、`just update`
   - UPS の監視用のパスワード(netclient のとき): NUT サーバーの側で替えて `ups.password` を替え、`just update`
   - SSH の公開鍵: `sysadmin.ssh_authorized_keys` と `users[].ssh_authorized_keys` から外して `just update`(どちらも env.yaml の内容に置き換わる。sysadmin の鍵は、今つないでいる鍵を外さない順で行う。just update は最後に入りなおせるかを確かめる)
   - 回復用の鍵(その人が共有の保管庫を見られたとき): age と SSH の回復用の鍵を作りなおし、`.sops.yaml` と `sysadmin.ssh_authorized_keys` の古いものと入れ替えて、`sops updatekeys` と `just update`

PC をなくした・盗まれたときは、その PC の鍵が漏れたものとして「減る」と同じことをする。壊れただけなら、鍵を外すだけでよい。

## 9. 記録の決まり

- **台帳(docs/inventory.md)**: ホストごとに 1 行。置き場所、機種、IP、道具の版、入れた日、使う人・用途
- **ホストの情報(facts/)**: `just facts` が書く。入れたとき、入れなおしたとき、道具の版を上げたときに更新してコミットする
- **ホストの記録(docs/hosts/)**: 受け入れテストの結果(日付、道具の版、行った人)と、変更の理由・手でしたこと
- **コミット**: env.yaml の変更、submodule の更新、台帳と記録は、それぞれ何のための変更か分かるメッセージにする

## 10. 鍵やパスワードをなくしたとき

どの鍵も 2 本以上(作業する人の鍵と回復用の鍵)にしておけば、1 本なくしても下の 10.1・10.3 で戻せる。
回復用の鍵は、使うときだけパスワード管理から `build/`(Git に入らない)に書き出し、終わったら消す。
年に 1 回ほど、回復用の鍵で実際に復号とログインができるかを試す(`just check-age-key build/<回復用の鍵>` と、
`ssh -i build/<回復用の SSH の鍵> -o IdentitiesOnly=yes sysadmin@<ホスト> true`)。

| 症状 | 手順 |
|---|---|
| `sops: command not found`、`no editor available` | 3 の「要るもの」 |
| `Failed to get the data key required to decrypt the SOPS file.` | 10.1(受け手の鍵が手元にない) |
| 受け手の鍵が 1 つも残っていない | 10.2 |
| `MAC mismatch` | 暗号化したファイルを sops を通さずに書き換えた。コミットしていなければ `git checkout -- <ファイル>` で戻し、`sops edit` でやりなおす |
| `Permission denied (publickey)`(sysadmin に入れない) | 10.3 |
| sysadmin のパスワードが分からない | 10.4 |

### 10.1 自分の age の鍵がない

1. 新しい鍵を作る(3 の 3)。`.sops.yaml` の `age:` で、なくした鍵の公開鍵を新しい公開鍵に置き換える
2. 復号できる鍵で `sops updatekeys` する(8 の 2)。ほかに作業する人がいなければ回復用の鍵を使う
   ```
   SOPS_AGE_KEY_FILE=build/age-recovery.txt sops updatekeys -y common.yaml
   for f in hosts/*.yaml; do grep -q '^sops:' "$f" && SOPS_AGE_KEY_FILE=build/age-recovery.txt sops updatekeys -y "$f"; done
   rm build/age-recovery.txt
   just check-age-key ~/.config/sops/age/keys.txt     # 新しい自分の鍵で復号できること
   ```
3. なくした PC が人の手に渡ったかもしれないなら、その鍵で読めた秘密を替える(8 の「減る」の 2)

### 10.2 受け手の鍵が 1 つも残っていない

暗号化した値は誰にも復号できない。新しい鍵で暗号化しなおし、値を入れ直す。暗号化していない値とコメントはそのまま残る。

1. 作業する人の鍵と回復用の鍵を作りなおし、`.sops.yaml` の `age:` をその公開鍵だけにする
2. 暗号化した値を `CHANGE_ME` にして、新しい鍵で暗号化しなおす(`sops:` の節はファイルの最後にある)
   ```
   for f in common.yaml hosts/*.yaml; do
       grep -q '^sops:' "$f" || continue
       sed -i -e '/^sops:/,$d' -e 's/ENC\[[^]]*\]/CHANGE_ME/g' "$f"
       sops --encrypt --in-place "$f"
   done
   ```
3. `sops edit <ファイル>` で `CHANGE_ME` を本当の値に替える
   - `sysadmin.password_hash`: いまのホストの sysadmin のパスワードから作る(`openssl passwd -6`)。`just update` は
     ホストのパスワードをこの値に置き換えるので、違うパスワードにすると、ホストのパスワードも変わる
   - `users[].rdp.initial_password`: RDP の認証情報がまだない利用者にだけ入る(本人が変えた値は上書きしない)ので、新しい値でよい
   - `notify.slack_webhook_url`、`ups.password`: 元の値を入れるか、作りなおす
4. `CHANGE_ME` が残っていないことを確かめてから(`sops --decrypt <ファイル> | grep CHANGE_ME`)、`just check-all` する。
   残したまま `just update` や `just iso` をすると、それがそのままパスワードになる

### 10.3 sysadmin に SSH で入れない

sysadmin の `~/.ssh/authorized_keys` は、`just update` のたびに `sysadmin.ssh_authorized_keys` に置き換わる。
手でホストに鍵を足しても、env.yaml に書いていなければ次の `just update` で消える。先に、この PC の公開鍵を env.yaml に足しておく。

1. 回復用の SSH の鍵があれば、それで `just update` する。道具のレシピは `tool/` で動くので、鍵は絶対パスで渡す
   (`AGENT_HOST_SSH_OPTS` は空白で分けるので、パスに空白があると使えない)
   ```
   export AGENT_HOST_SSH_OPTS="-i $PWD/build/recovery_ed25519 -o IdentitiesOnly=yes"
   just update agent-host-01
   unset AGENT_HOST_SSH_OPTS; rm build/recovery_ed25519
   ```
   PowerShell では `$env:AGENT_HOST_SSH_OPTS = "-i $($PWD.Path -replace '\\', '/')/build/recovery_ed25519 -o IdentitiesOnly=yes"`
2. 回復用の鍵もなければ、利用者として RDP で入り(コンソールに入れるならコンソールで)、`su - sysadmin` で
   `~/.ssh/authorized_keys` にこの PC の公開鍵を足す。sysadmin のパスワードが要る。そのあと `just update` で env.yaml に合わせる
3. RDP にもコンソールにも入れなければ、入れなおす(7)。書き出し(`just backup`)にも SSH が要るので、ホームのデータは移せない

### 10.4 sysadmin のパスワードが分からない

`just update` も sudo を使うので、`sysadmin.password_hash` を替えてもホストには入らない。構成では sysadmin のほかに sudo できる人を
作らないので、入れなおす(7)。sysadmin のパスワードは、パスワード管理の共有の保管庫に置いておく。
