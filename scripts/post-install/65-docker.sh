#!/usr/bin/env bash
# Docker を公式 apt リポジトリから固定バージョンで入れ、利用者ごとの rootless Docker にする。
# 利用者を docker グループに入れると実質 root になるので使わない(SPEC.md §4 の「sudo なし」を保つ)。
set -euo pipefail
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"
load_env

# --- 固定するバージョン(上げるときはここと手順書の付録「固定しているバージョン」を直す) ---
# 公式リポジトリには過去の版も残るので、版を指定して入れ、apt-mark hold する
DOCKER_VERSION="5:29.9.2-1~ubuntu.26.04~resolute"
CONTAINERD_VERSION="2.4.2-3~ubuntu.26.04~resolute"
BUILDX_VERSION="0.38.1-1~ubuntu.26.04~resolute"
COMPOSE_VERSION="5.6.1-1~ubuntu.26.04~resolute"
DOCKER_KEY_FPR=9DC858229FC7DD38854AE2D88D81803C0EBFCD88

# rootless に要るもの(newuidmap/newgidmap と、ユーザーの D-Bus)
apt-get install -y uidmap dbus-user-session

# --- リポジトリ ---
keyring=/etc/apt/keyrings/docker.gpg
if [ ! -f "$keyring" ]; then
    install -d -m 755 /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor >"$keyring.part"
    fpr="$(gpg --show-keys --with-colons "$keyring.part" | awk -F: '/^fpr/ {print $10; exit}')"
    if [ "$fpr" != "$DOCKER_KEY_FPR" ]; then
        rm -f "$keyring.part"
        log "Docker の署名鍵の fingerprint が一致しない: $fpr"
        exit 1
    fi
    mv "$keyring.part" "$keyring"
fi
# shellcheck source=/dev/null
codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"
echo "deb [arch=amd64 signed-by=$keyring] https://download.docker.com/linux/ubuntu $codename stable" \
    >/etc/apt/sources.list.d/docker.list
apt-get update

# --- パッケージ ---
# rootlesskit 用の AppArmor プロファイルは、deb で入れれば apparmor パッケージに含まれる(Docker の公式文書)
pkgs=(
    "docker-ce=$DOCKER_VERSION"
    "docker-ce-cli=$DOCKER_VERSION"
    "docker-ce-rootless-extras=$DOCKER_VERSION"
    "containerd.io=$CONTAINERD_VERSION"
    "docker-buildx-plugin=$BUILDX_VERSION"
    "docker-compose-plugin=$COMPOSE_VERSION"
)
apt-get install -y --allow-downgrades --allow-change-held-packages "${pkgs[@]}"
apt-mark hold "${pkgs[@]%%=*}"
log "Docker $DOCKER_VERSION を入れて hold した"

# root で動く通常のデーモンと containerd は使わない(rootless は agent の中に自分の containerd を持つ)
systemctl disable --now docker.service docker.socket
systemctl mask --now containerd.service
rm -f /var/run/docker.sock

# 通信の中継を pasta にする(既定の gvisor-tap-vsock より速い。Docker の文書の推奨)
apt-get install -y passt

# --- 利用者ごとの rootless Docker ---
setup_rootless_docker() {
    local agent_uid runtime_dir
    # subuid/subgid は useradd が割り当てる。無ければ止める(範囲の重なりを避けるため手で決める)
    if ! grep -q "^$AGENT_USER:" /etc/subuid || ! grep -q "^$AGENT_USER:" /etc/subgid; then
        log "$AGENT_USER の /etc/subuid か /etc/subgid が無い。usermod --add-subuids/--add-subgids で 65536 個割り当てる"
        exit 1
    fi

    # セッションがなくても利用者の systemd(ユーザー)を動かし、再起動後に Docker が自動で上がるようにする
    # (20-sessions.sh でも有効にしている)
    loginctl enable-linger "$AGENT_USER"
    agent_uid="$(id -u "$AGENT_USER")"
    runtime_dir="/run/user/$agent_uid"
    for _ in $(seq 1 30); do
        [ -S "$runtime_dir/bus" ] && break
        sleep 1
    done
    [ -S "$runtime_dir/bus" ] || { log "$runtime_dir/bus ができない(linger が効いていない)"; exit 1; }

    if [ ! -f "$AGENT_HOME/.config/systemd/user/docker.service" ]; then
        # docker.service(ユーザー)と CLI のコンテキスト rootless を作り、rootless を既定にする
        agent_bus_run dockerd-rootless-setuptool.sh install
    fi
    # pasta で通信し、公開したポートも pasta に任せる(implicit)
    write_agent_file 644 "$AGENT_HOME/.config/systemd/user/docker.service.d/agent-host.conf" <<'EOF'
# agent-host-autoinstall が置いた設定
[Service]
Environment=DOCKERD_ROOTLESS_ROOTLESSKIT_NET=pasta
Environment=DOCKERD_ROOTLESS_ROOTLESSKIT_PORT_DRIVER=implicit
EOF
    # コンテナのログは 1 つあたり 10MB × 3 まで(json-file は既定で上限がない)。既にある設定には手を入れない
    if [ ! -f "$AGENT_HOME/.config/docker/daemon.json" ]; then
        write_agent_file 644 "$AGENT_HOME/.config/docker/daemon.json" <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
EOF
    fi
    # 週 1 回、使われていないイメージ(タグのないもの)と 7 日より古いビルドのキャッシュを消す
    write_agent_file 644 "$AGENT_HOME/.config/systemd/user/docker-prune.service" <<'EOF'
[Unit]
Description=使われていない Docker のイメージとビルドのキャッシュを消す(agent-host-autoinstall)
[Service]
Type=oneshot
ExecStart=/usr/bin/docker image prune -f
ExecStart=/usr/bin/docker builder prune -f --filter until=168h
EOF
    write_agent_file 644 "$AGENT_HOME/.config/systemd/user/docker-prune.timer" <<'EOF'
[Unit]
Description=週 1 回 Docker を掃除する(agent-host-autoinstall)
[Timer]
OnCalendar=weekly
Persistent=true
[Install]
WantedBy=timers.target
EOF
    agent_bus_run systemctl --user daemon-reload
    agent_bus_run systemctl --user enable --now docker.service docker-prune.timer
    agent_bus_run systemctl --user restart docker.service

    # コンテキストを見ないツール(Testcontainers など)のために DOCKER_HOST も入れる。
    # environment.d は systemd(ユーザー)と GNOME のセッションに入り、Orca や端末に引き継がれる
    printf 'DOCKER_HOST=unix://%s/docker.sock\n' "$runtime_dir" |
        write_agent_file 644 "$AGENT_HOME/.config/environment.d/60-docker.conf"
    log "$AGENT_USER の rootless Docker を有効にした"
}
for_each_user setup_rootless_docker
