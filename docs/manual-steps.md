# 手作業の手順

autoinstall とスクリプトで自動化できない作業と、自動化が効かなかったときの手順。SPEC.md §5.3 に対応する。

## 0. インストール用 USB を作る(作業用の PC で)

Linux か WSL で行う。xorriso と python3-yaml が要る。

1. `autoinstall/env.example.yaml` を `autoinstall/env.yaml` にコピーし、実値を入れる
   - `keyboard_layout` は RDP で使う人のキーボードに合わせる(101/104 の英字配列なら `us`、106/109 なら `jp`)
   - `sysadmin.password_hash` は `mkpasswd -m sha-512` で作る
2. Ubuntu Desktop 26.04 LTS の ISO を用意し、次を実行する
   ```
   scripts/build-usb.sh ubuntu-26.04-desktop-amd64.iso agent-host.iso
   ```
3. できた `agent-host.iso` を USB メモリに書き込む(Rufus なら「DD イメージ」モード)

できた ISO と USB メモリには、パスワードハッシュと RDP のパスワードが入る。使い終わったら消す。

**注意:** この USB から起動すると、確認なしでディスク全体を消してインストールが始まる。対象以外の PC に挿したまま起動しない。インストールが終わって再起動したら、すぐに USB を抜く。

## 1. BIOS

- Restore on AC Power Loss(名称は機種による)を **Power On** にする
- HDMI ダミープラグを挿す

## 2. インストール

1. USB から起動する。確認画面は出ずにインストールが進む
2. 再起動後、初回起動時の構成(agent-host-provision.service)がネットワークから Node.js・Orca・Claude Code などを取得する。終わるまで GDM は起動しない
3. 構成が終わると agent で自動ログインし、first-login がデスクトップ共有を有効にする

構成の結果は SSH で確かめる。

```
journalctl -u agent-host-provision.service      # 構成の記録
sudo cat /home/agent/.local/state/agent-host/first-login.log   # first-login の記録
```

構成が失敗したときは、原因を直してから `sudo /opt/agent-host/provision.sh` で再実行する。

## 3. agent のログインキーリング(自動で効かなかったときだけ)

80-agent-session.sh は空パスワードのキーリングを最初から置く。first-login.log に `set-credentials` の失敗が出ていたら、これが効いていない。そのときは手でパスワードを空にする。

1. 物理画面(または一時的に別の手段)で agent のデスクトップを開く
2. 「パスワードと鍵」(seahorse。無ければ `sudo apt install seahorse`)を起動する
3. 「ログイン」キーリングを右クリック → パスワードの変更 → 新しいパスワードを空にする(平文で保存する警告には「続ける」)
4. ターミナルで `/opt/agent-host/first-login/first-login.sh` を実行する

## 4. デスクトップ共有(first-login が失敗したときだけ)

first-login が成功していれば不要。失敗していたら、agent のデスクトップで次を行う。

- 設定 → システム → リモートデスクトップ → 「デスクトップ共有」をオン、「リモート操作」をオン
- 認証情報(ユーザー名・パスワード)を env.yaml の `rdp` の値にする
- 「リモートログイン」は**オンにしない**(デスクトップ共有が 3390 番に移る)

## 5. Claude Code のログイン

RDP で agent のデスクトップに入り、ターミナルで `claude` を起動してログインする。

## 6. Codex のログイン

1. 事前に ChatGPT のセキュリティ設定(Workspace なら管理者の権限設定)でデバイスコード認証を有効にする。有効でないと、エラーにならずに止まって見える
2. ターミナルで `codex login --device-auth` を実行し、表示されたコードを手元の PC のブラウザで入力する

## 7. Orca の初回起動

1. Orca は自動起動している。初回の案内に従う
2. `~/.claude` / `~/.codex` の設定を取り込む
3. 自動更新の設定があればオフにする。.deb 版は更新を自分では適用しないが、更新の通知は出る。通知を止める設定は見つかっていない(HANDOVER.md)
