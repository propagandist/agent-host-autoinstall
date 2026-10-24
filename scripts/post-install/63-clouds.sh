#!/usr/bin/env bash
# env.yaml の clouds で選んだクラウドの CLI を入れる(aws / gcp / azure)。
# 選ばなくなったものは消さない。認証情報は agent のホーム(~/.aws、~/.config/gcloud、~/.azure)に残るので、
# 短い時間だけ有効なログイン(SSO、デバイスコード)と、権限を絞ったアカウントで使う(手順書)。
# Terraform・OpenTofu・kubectl・Helm などはプロジェクトごとに版が違うので入れない(エージェントが mise で入れる)。
set -euo pipefail
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"
load_env

# --- 固定するバージョン(上げるときはここと手順書の付録「固定しているバージョン」を直す) ---
# AWS CLI v2: 公式の zip。SHA256 は、AWS の PGP 署名(.sig)が正しいことを確かめたうえで自分で計算した値
AWSCLI_VERSION=2.38.5
AWSCLI_SHA256=5def7d1b7e55d892f9a381bb2cb2081a685712464be0d36d5d706af0ac48d0d3
# Google Cloud CLI: Google の公式 apt リポジトリ(過去の版も残る)から版を指定して入れ、hold する
GCLOUD_VERSION=590.0.1-0
GOOGLE_CLOUD_KEY_FPR=35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3
# Azure CLI: Microsoft の公式 apt リポジトリ(26.04 向け)から版を指定して入れ、hold する
AZURE_CLI_VERSION=2.91.0-1~resolute
MICROSOFT_KEY_FPR=BC528686B50D79E339D3721CEB3E94ADBE1229CF

selected() { [[ " ${AH_CLOUDS:-} " == *" $1 "* ]]; }
env_d="$AGENT_HOME/.config/environment.d"

# apt の署名鍵を置く(fingerprint が一致したときだけ)
install_apt_key() {
    local url="$1" fpr_want="$2" keyring="$3" fpr
    [ -f "$keyring" ] && return 0
    install -d -m 755 /etc/apt/keyrings
    curl -fsSL "$url" | gpg --dearmor >"$keyring.part"
    fpr="$(gpg --show-keys --with-colons "$keyring.part" | awk -F: '/^fpr/ {print $10; exit}')"
    if [ "$fpr" != "$fpr_want" ]; then
        rm -f "$keyring.part"
        log "署名鍵の fingerprint が一致しない($url): $fpr"
        exit 1
    fi
    mv "$keyring.part" "$keyring"
}

# --- AWS CLI v2 ---
if selected aws; then
    if [ "$(/usr/local/bin/aws --version 2>/dev/null | awk '{print $1}')" != "aws-cli/$AWSCLI_VERSION" ]; then
        zip="$AH_CACHE/awscli-exe-linux-x86_64-$AWSCLI_VERSION.zip"
        download_verified "https://awscli.amazonaws.com/awscli-exe-linux-x86_64-$AWSCLI_VERSION.zip" \
            "$AWSCLI_SHA256" "$zip"
        tmp="$(mktemp -d)"
        unzip -q "$zip" -d "$tmp"
        "$tmp/aws/install" --install-dir /opt/aws-cli --bin-dir /usr/local/bin --update
        rm -rf "$tmp"
    fi
    # 出力を less に渡さない(エージェントが端末で止まらないように)
    printf 'AWS_PAGER=\n' | write_agent_file 644 "$env_d/63-aws.conf"
    log "AWS CLI $AWSCLI_VERSION を入れた"
fi

# --- Google Cloud CLI ---
if selected gcp; then
    install_apt_key https://packages.cloud.google.com/apt/doc/apt-key.gpg \
        "$GOOGLE_CLOUD_KEY_FPR" /etc/apt/keyrings/google-cloud.gpg
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-cloud.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
        >/etc/apt/sources.list.d/google-cloud-agent-host.list
    apt-get update
    if [ "$(dpkg-query -W -f='${Version}' google-cloud-cli 2>/dev/null || true)" != "$GCLOUD_VERSION" ]; then
        apt-get install -y --allow-downgrades --allow-change-held-packages "google-cloud-cli=$GCLOUD_VERSION"
    fi
    apt-mark hold google-cloud-cli
    # 利用状況の送信と、更新の確認を止める(版は apt で固定している)
    write_agent_file 644 "$env_d/63-gcloud.conf" <<'EOF'
CLOUDSDK_CORE_DISABLE_USAGE_REPORTING=true
CLOUDSDK_COMPONENT_MANAGER_DISABLE_UPDATE_CHECK=true
EOF
    log "Google Cloud CLI $GCLOUD_VERSION を入れて hold した"
fi

# --- Azure CLI ---
if selected azure; then
    # VS Code と同じ Microsoft の鍵(72-editors.sh と同じ場所に置く)
    install_apt_key https://packages.microsoft.com/keys/microsoft.asc \
        "$MICROSOFT_KEY_FPR" /etc/apt/keyrings/microsoft.gpg
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli resolute main" \
        >/etc/apt/sources.list.d/azure-cli-agent-host.list
    apt-get update
    if [ "$(dpkg-query -W -f='${Version}' azure-cli 2>/dev/null || true)" != "$AZURE_CLI_VERSION" ]; then
        apt-get install -y --allow-downgrades --allow-change-held-packages "azure-cli=$AZURE_CLI_VERSION"
    fi
    apt-mark hold azure-cli
    # 利用状況の送信を止める
    printf 'AZURE_CORE_COLLECT_TELEMETRY=false\n' | write_agent_file 644 "$env_d/63-azure.conf"
    log "Azure CLI $AZURE_CLI_VERSION を入れて hold した"
fi
