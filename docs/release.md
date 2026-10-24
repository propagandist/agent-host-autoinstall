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

リリースは実機での受け入れテストが通ってから出す(最初は v0.1.0)。しばらく運用して問題がないと判断するまでは 0.x とし、GitHub では pre-release にする。

## 成果物

- 詳細な設定手順書の PDF(`agent-host-setup-guide-v<版>.pdf`)。表紙とフッターに日付とタグが入る
- ソース(GitHub が zip と tar.gz を自動で付ける)
- **ISO は成果物にしない。** env.yaml のパスワードのハッシュ、RDP のパスワード、Webhook の URL が入るため。使う人が自分の env.yaml で `just iso` を実行して作る

## 初めて行うときの準備

git-flow のタグに `v` を付ける(手元の設定で、リポジトリには入らない)。

```sh
git config gitflow.prefix.versiontag v
```

## 手順

例は v0.1.0。

1. 入れたい feature を develop にマージしておく(`git flow feature finish --no-ff <名前>`)
2. release ブランチを作る
   ```sh
   git checkout develop && git pull
   git flow release start 0.1.0
   ```
3. 版の内容を書く(このブランチでは版の記録と文書の手直しだけを行い、機能は足さない)
   - `CHANGELOG.md` の `## [未リリース]` を `## [0.1.0] - <日付>` にし、上に空の `## [未リリース]` を足す。「確認した環境」に、VM と実機で確かめた範囲を書く
   - 手順書(docs/setup-guide.tex)の付録「固定しているバージョン」の日付と値を、スクリプトの先頭の値に合わせる
   - docs/HANDOVER.md の「現状」を直す
   - コミットする
4. リリースの前の確認
   ```sh
   just release-check    # コミット済みか、CHANGELOG の節、lint、PDF の作成
   ```
5. release ブランチから作った ISO で、VM に新しく入れなおし、受け入れテスト(docs/acceptance-test.md)を行う。直したら release ブランチにコミットし、4 からやりなおす
6. 仕上げる(main へのマージ、タグ、develop への戻し)
   ```sh
   git flow release finish -m "v0.1.0" 0.1.0
   git push origin main develop --tags
   ```
7. GitHub の Actions で `release` が通り、Releases に v0.1.0 と PDF ができたことを確かめる。PDF を開き、表紙の版が `v0.1.0` になっていること

## うまくいかなかったとき

- **Actions が失敗した:** 直したものを develop から hotfix(`git flow hotfix start 0.1.1`)として出す。タグは付けなおさない
- **CHANGELOG の節がないと言われた:** 見出しが `## [0.1.0]` で始まっているか(タグの `v` は付けない)
- **PDF だけ作りなおしたい:** Actions の画面から、失敗した実行を再実行する。Release が先にできていれば、手元で `just guide` を実行し `gh release upload v0.1.0 <PDF> --clobber` で差し替える
