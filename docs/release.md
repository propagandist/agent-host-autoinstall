# リリースの手順

GitFlow の release ブランチで版を決め、確かめてから main に入れる。
タグを push すると GitHub Actions(`.github/workflows/release.yml`)が手順書の PDF を作り、GitHub Release に付ける。

## 版の付け方

[Semantic Versioning](https://semver.org/lang/ja/) で、タグは `v<メジャー>.<マイナー>.<パッチ>`。

| 上げる桁 | 変更 |
|---|---|
| パッチ | 固定したバージョンの更新、修正、文書の直し |
| マイナー | 機能や env.yaml の項目の追加(既存の env.yaml はそのまま使える) |
| メジャー | env.yaml の互換性がなくなる変更(既存の env.yaml を直さないと ISO を作れない) |

0.x のあいだは、env.yaml の互換性がなくなる変更もマイナーを上げる(例: 0.2.0 → 0.3.0)。互換性の約束は 1.0.0 からで、そこからは上の表のとおりメジャーを上げる。どの版でも、互換性がなくなる変更は CHANGELOG の「env.yaml の変更」に、各ホストの env.yaml で直すことを書く。

リリースは VM での受け入れテストが通ったら出す(最初は v0.1.0)。実機での確認は必須にせず、実機で問題が出たら hotfix で直す(下の「実機で問題が出たとき」)。しばらく運用して問題がないと判断するまでは 0.x とし、GitHub では pre-release にする。

## 成果物

- 詳細な設定手順書の PDF(`agent-host-setup-guide-v<版>.pdf`)。表紙とフッターに日付とタグが入る
- ソース(GitHub が zip と tar.gz を自動で付ける)
- **ISO は成果物にしない。** env.yaml のパスワードのハッシュ、RDP のパスワード、Webhook の URL が入るため。使う人が自分の env.yaml で `just iso` を実行して作る

## 初めて行うときの準備

git-flow のタグに `v` を付ける(手元の設定で、リポジトリには入らない)。

```sh
git config gitflow.prefix.versiontag v
```

`just vm-test` のための試験用の env.yaml を `build/test/env.yaml` に作る(build/ はコミットされない)。

- `lan_cidrs` に VirtualBox の NAT の `10.0.2.0/24` を入れる(VM の 22 と 3389 は、手元の PC の 127.0.0.1:2222 と 127.0.0.1:13389 に転送する)
- 試験用の鍵を作り(`ssh-keygen -t ed25519 -f build/test/id_ed25519 -N ""`)、公開鍵を `sysadmin.ssh_authorized_keys` に入れる
- sudo のパスワードは、実行したときに聞かれる(環境変数 `AGENT_HOST_SUDO_PASSWORD` でも渡せる)
- `editors`・`agents`・`clouds` などは、確かめたいものをすべて選んでおく
- VM の名前・CPU・メモリなどは環境変数で変えられる(`scripts/local/vm-test.sh` の先頭)。Windows で Hyper-V(Docker Desktop)と共存させると、CPU 2 つ以上でゲストが止まった(docs/notes.md)ので、既定は CPU 1

## 手順

例は v0.1.0。

1. 入れたい feature を develop にマージしておく(`git flow feature finish --no-ff <名前>`)
2. release ブランチを作る
   ```sh
   git checkout develop && git pull
   git flow release start 0.1.0
   ```
3. 版の内容を書く(このブランチでは版の記録と文書の手直しだけを行い、機能は足さない)
   - `CHANGELOG.md` の `## [未リリース]` を `## [0.1.0] - <日付> — <位置づけ>` にし(位置づけは日本語 4〜27 字。例: 最初の版。Release の名前「v0.1.0 — 最初の版」になる)、上に空の `## [未リリース]` を足す。「確認した環境」に、VM と実機で確かめた範囲を書く
   - 「env.yaml の変更」の欄に、構成リポジトリの各ホストの env.yaml で直すこと(項目の追加・名前の変更・使えなくなった値)を書く。なければ「なし」。互換性がなくなる変更ならメジャーを上げる(0.x のあいだはマイナー)
   - 手順書(docs/setup-guide.tex)の付録「固定しているバージョン」の日付と値を、スクリプトの先頭の値に合わせる
   - docs/notes.md の「検証した環境」と「確認できていないこと」を直す
   - コミットする
4. リリースの前の確認
   ```sh
   just release-check    # コミット済みか、CHANGELOG の節、lint、just test、PDF の作成
   ```
5. release ブランチのスクリプトで VM に新しく入れなおし、受け入れテスト(docs/acceptance-test.md)を行う。直したら release ブランチにコミットし、4 からやりなおす
   ```sh
   just vm-test          # 入れなおし → verify・verify-rdp → 電源を切って戻るか → セッションが落ちて戻るか
   ```
   通ったら、残りの人が確かめるもの(RDP の画面と日本語入力、エージェントが動くこと、切断しても続くこと)を RDP で行う
6. 仕上げる(main へのマージ、タグ、develop への戻し)
   ```sh
   git flow release finish -m "v0.1.0" 0.1.0
   git push origin main develop --tags
   ```
7. GitHub の Actions で `release` が通り、Releases に v0.1.0 と PDF ができたことを確かめる。PDF を開き、表紙の版が `v0.1.0` になっていること

## うまくいかなかったとき

- **Actions が失敗した:** 直したものを hotfix(下と同じ手順。main から `git flow hotfix start 0.1.1`)として出す。タグは付けなおさない
- **CHANGELOG の節がないと言われた:** 見出しが `## [0.1.0] - <日付> — <位置づけ>` の形か(タグの `v` は付けない。` — ` は前後に空白のある em dash)
- **PDF だけ作りなおしたい:** Actions の画面から、失敗した実行を再実行する。Release が先にできていれば、手元で `just guide` を実行し `gh release upload v0.1.0 <PDF> --clobber` で差し替える

## 実機で問題が出たとき(hotfix)

リリースした版で、実機(や VM)で問題が見つかったら、main から hotfix ブランチを作り、パッチの版を出す。例は v0.1.1。

1. hotfix ブランチを作る
   ```sh
   git checkout main && git pull
   git flow hotfix start 0.1.1
   ```
2. 直してコミットする。`CHANGELOG.md` に `## [0.1.1] - <日付>` を足し、直したこと、確認した環境(実機か VM か)、「env.yaml の変更」(なければ「なし」)を書く。docs/notes.md にも、何が起きてどう直したかを書く
3. 確かめる
   ```sh
   just release-check    # hotfix ブランチでも使える
   ```
   VM で確かめられることは VM で(`just vm-test`)、実機でしか起きない問題は、その実機に `just update` して直ったことを確かめる(`just verify <ホスト>`)
4. 仕上げる(main と develop へのマージ、タグ)。タグの push で Actions が Release と PDF を作る
   ```sh
   git flow hotfix finish -m "v0.1.1" 0.1.1
   git push origin main develop --tags
   ```
5. 構成リポジトリ(docs/fleet.md)で、submodule を新しいタグにして、問題の出たホストから反映する

## 公開するとき

リポジトリを Public にするときに行う。

- GitHub の secret scanning と push protection を有効にする
- `git log --all --format='%ae %ce' | sort -u` で、作成者のメールアドレスが noreply などの公開してよいものだけであることを確かめる
- main と develop に、強制 push と削除を禁止する保護を入れる(Private のリポジトリでは、契約によっては設定できない)
- 既定ブランチを main にする(開いた人がリリース済みの状態を見る)。マージ済みのブランチを自動で消す設定(`delete_branch_on_merge`)が入っていることを確かめる
- About 欄の description(日本語 1 文、60〜80 字)と topics(6 個)が入っていることを確かめる。Zenn などの紹介記事を公開したら、Website にその URL を入れる
- 公開したあとで、`gh api repos/<owner>/<repo>/license --jq .license.spdx_id` が `Apache-2.0` になること、右柱に `v0.1.0 — 最初の版` のような Release が出ていることを確かめる
