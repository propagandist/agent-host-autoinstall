# 実機の構成管理(ひな形)

agent-host-autoinstall で作るホストの、実機の構成(ホストごとの env.yaml、台帳、記録)を管理するリポジトリのひな形。
このディレクトリの中身を、非公開の Git リポジトリ(自前の Gitea、GitHub の private など)の新しいリポジトリにコピーして使う。手順は tool/docs/fleet.md。

```
tool/                  agent-host-autoinstall(submodule。リリースのタグに固定する)
common.yaml            全台で共通の値(秘密情報は SOPS で暗号化)
hosts/<ホスト>.yaml    ホストごとの値(common.yaml に重ねる)
facts/<ホスト>.yaml    just facts が書く、ホストの情報(機種、シリアル、MAC、鍵の指紋、置いた版)
docs/inventory.md      台帳
docs/hosts/<ホスト>.md 受け入れテストの結果と変更の記録
scripts/with-env.sh    復号して道具に渡し、終わったら消す
.sops.yaml             暗号化する値と、復号できる人(age の公開鍵)
justfile               just check / iso / update / status / facts など
```

要るもの: just、Git Bash(Windows)、Docker Desktop、sops、age。

```
just setup                    # 道具を取得する(clone したあとに 1 回)
just check agent-host-01      # env.yaml を検査する
just iso agent-host-01        # build/agent-host-01.iso を作る
just update agent-host-01     # 設定とスクリプトの変更を反映する
just status agent-host-01     # 状態と、置いた版・最後に適用に成功した版を見る
just verify agent-host-01     # 仕様どおりかを確かめる
just facts agent-host-01      # facts/agent-host-01.yaml を書く
```
