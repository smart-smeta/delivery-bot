#!/usr/bin/env bash
# Installer for Debian 12 production deployment of Delivery Bot
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage: install_debian12.sh [options]
  --repo <git_url>          Git repository to clone if project not present
  --branch <name>           Git branch to checkout (default: main)
  --path <dir>              Installation directory (default: /opt/foodbot)
  --domain <domain>         Domain name for the application
  --bot-token <token>       Telegram bot token
  --admin-ids "1,2"         Comma separated admin ids
  --app-base-url <url>      Public base URL (https://example.com)
  --db-password <pass>      PostgreSQL password
  --non-interactive         Do not prompt for any input
  --help                    Show this help
USAGE
}

# defaults
REPO=""
BRANCH="main"
INSTALL_PATH="/opt/foodbot"
DOMAIN=""
BOT_TOKEN=""
ADMIN_IDS=""
APP_BASE_URL=""
DB_PASSWORD=""
NON_INTERACTIVE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2;;
    --branch) BRANCH="$2"; shift 2;;
    --path) INSTALL_PATH="$2"; shift 2;;
    --domain) DOMAIN="$2"; shift 2;;
    --bot-token) BOT_TOKEN="$2"; shift 2;;
    --admin-ids) ADMIN_IDS="$2"; shift 2;;
    --app-base-url) APP_BASE_URL="$2"; shift 2;;
    --db-password) DB_PASSWORD="$2"; shift 2;;
    --non-interactive) NON_INTERACTIVE=true; shift;;
    --help) usage; exit 0;;
    *) echo "Unknown option: $1" >&2; usage; exit 1;;
  esac
 done

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root" >&2
    exit 1
  fi
}

require_debian12() {
  . /etc/os-release
  if [[ "$ID" != "debian" || "$VERSION_ID" != "12" ]]; then
    echo "Debian 12 (bookworm) required" >&2
    exit 1
  fi
}

check_vars() {
  if [[ -z "$DOMAIN" ]]; then echo "--domain required" >&2; exit 1; fi
  if [[ -z "$BOT_TOKEN" ]]; then echo "--bot-token required" >&2; exit 1; fi
  if [[ -z "$APP_BASE_URL" ]]; then echo "--app-base-url required" >&2; exit 1; fi
  if [[ ! "$APP_BASE_URL" =~ ^https:// ]]; then
    echo "APP_BASE_URL must start with https://" >&2; exit 1
  fi
  if [[ -z "$DB_PASSWORD" ]]; then echo "--db-password required" >&2; exit 1; fi
  if [[ -z "$ADMIN_IDS" ]]; then echo "--admin-ids required" >&2; exit 1; fi
  if [[ ! "$BOT_TOKEN" =~ ^[0-9]+:.*$ ]]; then
    echo "BOT_TOKEN format invalid" >&2; exit 1
  fi
}

install_packages() {
  apt-get update
  apt-get install -y curl git jq ufw ca-certificates gnupg lsb-release
}

install_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    install_packages
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  fi
}

clone_repo() {
  if [[ ! -d "$INSTALL_PATH" ]]; then
    git clone --branch "$BRANCH" "$REPO" "$INSTALL_PATH"
  fi
}

copy_repo_contents() {
  if [[ "$PWD" != "$INSTALL_PATH" ]]; then
    rsync -a --exclude='.git' ./ "$INSTALL_PATH"/
  fi
}

create_env_file() {
  cd "$INSTALL_PATH"
  if [[ ! -f .env.prod ]]; then
    cp .env.prod.example .env.prod
  fi
  sed -i "s|ALLOWED_HOSTS=.*|ALLOWED_HOSTS=$DOMAIN|" .env.prod
  sed -i "s|APP_BASE_URL=.*|APP_BASE_URL=$APP_BASE_URL|" .env.prod
  sed -i "s|BOT_TOKEN=.*|BOT_TOKEN=$BOT_TOKEN|" .env.prod
  sed -i "s|BOT_ADMIN_IDS=.*|BOT_ADMIN_IDS=$ADMIN_IDS|" .env.prod
  sed -i "s|DATABASE_URL=postgresql://foodbot:STRONGPASS@db:5432/foodbot|DATABASE_URL=postgresql://foodbot:$DB_PASSWORD@db:5432/foodbot|" .env.prod
  # generate secrets if empty
  if ! grep -q '^DJANGO_SECRET_KEY=[A-Za-z0-9]' .env.prod; then
    local DJANGO_SECRET=$(python3 - <<'PY'
import secrets;print(secrets.token_urlsafe(64))
PY
)
    sed -i "s|DJANGO_SECRET_KEY=.*|DJANGO_SECRET_KEY=$DJANGO_SECRET|" .env.prod
  fi
  if ! grep -q '^WEBHOOK_SECRET=[A-Za-z0-9]' .env.prod; then
    local WEBHOOK_SECRET=$(python3 - <<'PY'
import secrets;print(secrets.token_urlsafe(32))
PY
)
    sed -i "s|WEBHOOK_SECRET=.*|WEBHOOK_SECRET=$WEBHOOK_SECRET|" .env.prod
  fi
}

configure_firewall() {
  ufw allow 22/tcp
  ufw allow 80/tcp
  ufw allow 443/tcp
  ufw --force enable || true
}

create_networks() {
  docker network create foodbot_net >/dev/null 2>&1 || true
}

bring_up_compose() {
  docker compose -f infra/docker-compose.prod.yml up -d --build
}

wait_for_web() {
  for i in {1..30}; do
    if curl -sf "https://$DOMAIN/healthz" >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
  done
  echo "Web service did not become healthy" >&2
  exit 1
}

post_migrate() {
  docker compose -f infra/docker-compose.prod.yml exec -T web python manage.py migrate --noinput
  docker compose -f infra/docker-compose.prod.yml exec -T web python manage.py collectstatic --noinput
}

create_superuser() {
  docker compose -f infra/docker-compose.prod.yml exec -T web python manage.py createsuperuser --noinput --username admin --email admin@$DOMAIN || true
}

register_webhook() {
  docker compose -f infra/docker-compose.prod.yml run --rm web python scripts/register_webhook.py || true
}

setup_systemd() {
  cat >/etc/systemd/system/foodbot.service <<SERVICE
[Unit]
Description=FoodBot service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
WorkingDirectory=$INSTALL_PATH
ExecStart=/usr/bin/docker compose -f $INSTALL_PATH/infra/docker-compose.prod.yml up -d
ExecStop=/usr/bin/docker compose -f $INSTALL_PATH/infra/docker-compose.prod.yml down
RemainAfterExit=yes
Restart=on-failure

[Install]
WantedBy=multi-user.target
SERVICE
  systemctl daemon-reload
  systemctl enable --now foodbot.service
}

summary() {
  cat <<SUM
Deployment complete.
Domain: https://$DOMAIN
Check: curl -I https://$DOMAIN/healthz
To see logs: docker compose -f $INSTALL_PATH/infra/docker-compose.prod.yml logs -f
SUM
}

main() {
  require_root
  require_debian12
  check_vars
  install_docker
  clone_repo
  copy_repo_contents
  create_env_file
  configure_firewall
  create_networks
  bring_up_compose
  wait_for_web
  post_migrate
  create_superuser
  register_webhook
  setup_systemd
  summary
}

main "$@"
