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

env.yaml は、前から順に重ねて使う(道具の `render-autoinstall.py`)。後のファイルの値が勝つ。辞書(`network`、`notify` など)はキーごとに重なり、並び(`editors`、`lan_cidrs` など)と値は置き換わる。知らないキー(書き間違い)はエラーになる。

作ったホストの `/opt/agent-host/BUILD-INFO` には、道具の版、構成リポジトリの版(`AGENT_HOST_CONFIG_REV`)、使った env のファイル名、作った日時が残る。`just status` と `just facts` で見える。

## 3. 構成リポジトリを作る(最初に 1 回)

要るもの(作業する人の手元): just、Git Bash(Windows)、Docker Desktop、[sops](https://github.com/getsops/sops)、[age](https://github.com/FiloSottile/age)。

1. 非公開の Git リポジトリ(自前の Gitea、GitHub の private など)に、非公開の空のリポジトリを作る
2. ひな形をコピーし、道具を submodule で足して、使う版に固定する
   ```
   cp -r <道具>/examples/fleet/. <構成リポジトリ>/
   cd <構成リポジトリ>
   git init
   git submodule add https://github.com/<組織>/agent-host-autoinstall.git tool
   git -C tool checkout v0.1.0
   just setup
   ```
3. 作業する人ごとに age の鍵を作る(秘密鍵は手元とパスワード管理に置き、リポジトリには入れない)
   ```
   age-keygen -o ~/.config/sops/age/keys.txt     # Windows では %AppData%\sops\age\keys.txt
   ```
   表示された公開鍵(`age1…`)を `.sops.yaml` の `age:` に並べる
4. `common.yaml` に全台で共通の値を、`hosts/<ホスト>.yaml` にホストだけの値を書き、秘密情報を暗号化する
   ```
   sops --encrypt --in-place common.yaml
   sops --encrypt --in-place hosts/agent-host-01.yaml   # ホストのファイルに秘密情報を書いたときだけ
   just check agent-host-01
   ```
   暗号化したファイルは `sops common.yaml` で開くと、復号して編集し、保存するときに暗号化しなおす
5. コミットして push する

## 4. ホストを足す

1. `hosts/<ホスト>.yaml` を作る(ファイル名はホスト名と同じ)。IP と壁紙の色を、ほかのホストと変える
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
   just status agent-host-01                 # 作った版に、いまの構成の版が出る
   just verify agent-host-01                 # 仕様どおりかを確かめる(✗ がないこと)
   ```
4. `docs/hosts/<ホスト>.md` の変更の記録に、理由と手でしたことを書く

ufw の許可は足すだけなので、`lan_cidrs` や `dev_ports` から外したものは手で消す(道具の手順書の「設定やバージョンを変える」)。

## 6. 道具の版を上げる

1. 道具の CHANGELOG を読む。特に「env.yaml の変更」の欄(項目の追加・名前の変更・使えなくなった値)
2. submodule を新しいタグにし、すべてのホストの env.yaml を検査する
   ```
   git -C tool fetch --tags
   git -C tool checkout v0.2.0
   just check-all
   ```
   止まったら、CHANGELOG に従って `common.yaml` や `hosts/` を直す
3. 1 台で試す。反映し、`just verify` と、受け入れテストの 4・5(RDP と、エージェントが動くこと)を行う
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
3. 取り込み、再起動する
   ```
   just restore agent-host-01 <暗号化された場所>/agent-host-01-<日付>.tar.zst
   just ssh agent-host-01            # sudo systemctl reboot
   ```
4. `just verify` と受け入れテストの 4・5 を行い、`just facts` と記録を更新する。書き出したファイルは消す

ホスト鍵と RDP の証明書も移るので、手元の known_hosts と RDP の「今後確認しない」は、そのまま使える。

## 8. 作業する人が増える・減る

増える:
1. 新しい人が age の鍵を作り、公開鍵を渡す
2. `.sops.yaml` に公開鍵を足し、すべての暗号化したファイルに反映する
   ```
   sops updatekeys common.yaml
   for f in hosts/*.yaml; do grep -q '^sops:' "$f" && sops updatekeys "$f"; done
   ```

減る:
1. `.sops.yaml` から公開鍵を外し、上と同じように `sops updatekeys` する
2. その人が知っている秘密情報を替える(過去のコミットは、その人の鍵で復号できるため)
   - RDP のパスワード: `rdp.password` を替えて、すべてのホストに `just update`
   - sysadmin のパスワード: `sysadmin.password_hash` を替えて `just update`(sudo のパスワードは、ホストで `sudo passwd sysadmin` でも替える)
   - Slack の Webhook: Slack で作りなおして `notify.slack_webhook_url` を替える
   - SSH の公開鍵: `sysadmin.ssh_authorized_keys` と `agent_ssh_authorized_keys` から外して `just update`

## 9. 記録の決まり

- **台帳(docs/inventory.md)**: ホストごとに 1 行。置き場所、機種、IP、道具の版、入れた日、使う人・用途
- **ホストの情報(facts/)**: `just facts` が書く。入れたとき、入れなおしたとき、道具の版を上げたときに更新してコミットする
- **ホストの記録(docs/hosts/)**: 受け入れテストの結果(日付、道具の版、行った人)と、変更の理由・手でしたこと
- **コミット**: env.yaml の変更、submodule の更新、台帳と記録は、それぞれ何のための変更か分かるメッセージにする
