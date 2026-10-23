# HANDOVER.md

## これまでの経緯(設計段階で決めたこと)

1. オンプレPCへの Ubuntu 自動構成は、公式の autoinstall を使う。Server 専用ではなく Desktop でも使える
2. 常時稼働させたいが、AI エージェントを動かすためにデスクトップが必要 → Desktop 版に常時稼働の設定を足す方針
3. エージェントの作業環境は Orca(stablyai/orca。Claude Code や Codex を git worktree ごとに並列実行する ADE)。Codex も併用する
4. 遠隔操作は当初 xrdp を検討したが、以下の理由で GNOME 標準の「デスクトップ共有」(RDP)に変更
   - Ubuntu 26.04 LTS は Wayland のみで、xrdp が使えない
   - xrdp やリモートログインは別セッションを作るため、再起動後に誰かがログインするまで Orca が起動しない
   - デスクトップ共有は物理セッションを共有するので、自動ログイン + Orca 自動起動と両立する
5. 自動ログインではキーリングが開かず、デスクトップ共有の認証情報が読めない問題がある → `agent` ユーザーのキーリングを空パスワードにする(専用ユーザー・秘密情報なしが前提)

詳細は SPEC.md §8 を参照。

## 現状

- 仕様(SPEC.md)と作業ルール(CLAUDE.md)のみ。実装は未着手

## 次にやること(この順で)

1. SPEC.md §9 の未確定事項を調査し、結果を本ファイルに追記する
   - 特に「26.04 Desktop の autoinstall の対応範囲」と「grdctl によるデスクトップ共有の有効化可否」
2. `autoinstall/autoinstall.yaml` と `env.example.yaml` を作成
3. `scripts/post-install/` を順に実装
4. `scripts/first-login/` を実装(agent 初回ログイン時の gsettings)
5. 仮想マシンでインストールを通す
6. `docs/manual-steps.md` と `docs/acceptance-test.md` を作成
7. 実機で受け入れテスト(SPEC.md §7)

## 注意点

- Codex のログインはデバイスコード認証(`codex login --device-auth`)。ChatGPT 側の設定で事前に有効化しておかないと、エラーにならず止まって見える
- Codex の認証情報は `~/.codex/auth.json` に平文で保存される。`agent` のホームの権限を絞る
- Orca は初期状態で自動更新する。常時稼働機では手動更新にする
- デスクトップ共有とリモートログインを両方有効にすると、デスクトップ共有が 3390 番に移る。リモートログインは有効にしない
- いちばん崩れやすいのは受け入れテスト4(再起動後、何もせずに RDP がつながるか)。ここを最優先で検証する
