#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "Error on line $LINENO" >&2' ERR

DOMAIN=""
APP_BASE_URL=""
BOT_TOKEN=""
ACME_EMAIL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain)
      DOMAIN="$2"; shift 2;;
    --app-base-url)
      APP_BASE_URL="$2"; shift 2;;
    --bot-token)
      BOT_TOKEN="$2"; shift 2;;
    --acme-email)
      ACME_EMAIL="$2"; shift 2;;
    *)
      echo "Unknown option $1" >&2; exit 1;;
  esac
done

# basic validations
[[ -n "$DOMAIN" ]] || { echo "--domain required"; exit 1; }
[[ "$APP_BASE_URL" =~ ^https:// ]] || { echo "--app-base-url must start with https://"; exit 1; }
[[ "$BOT_TOKEN" =~ ^[0-9]+:.+ ]] || { echo "--bot-token format invalid"; exit 1; }

if ! grep -q 'Debian GNU/Linux 12' /etc/os-release; then
  echo "This script supports only Debian 12"; exit 1
fi

if [[ $EUID -ne 0 ]]; then
  echo "Run as root"; exit 1
fi

SERVER_IP=$(curl -4 -s https://api.ipify.org)
DNS_IP=$(getent ahosts "$DOMAIN" | awk '{print $1}' | head -n1)
if [[ "$SERVER_IP" != "$DNS_IP" ]]; then
  echo "DNS A record for $DOMAIN does not point to this server ($SERVER_IP)"; exit 1
fi

if ss -tulpn | grep -q ':80 '; then
  echo "Port 80 is already in use"; exit 1
fi

if ! command -v docker >/dev/null; then
  apt-get update
  apt-get install -y docker.io docker-compose-plugin
fi

if command -v ufw >/dev/null; then
  ufw allow 22/tcp || true
  ufw allow 80/tcp || true
  ufw allow 443/tcp || true
fi

mkdir -p /opt/foodbot
cd /opt/foodbot

if [ ! -d .git ]; then
  git init . >/dev/null
fi

cp -n .env.prod.example .env.prod || true
sed -i "s/APP_DOMAIN=.*/APP_DOMAIN=$DOMAIN/" .env.prod
sed -i "s#APP_BASE_URL=.*#APP_BASE_URL=$APP_BASE_URL#" .env.prod
sed -i "s/BOT_TOKEN=.*/BOT_TOKEN=$BOT_TOKEN/" .env.prod

export APP_DOMAIN="$DOMAIN"
export ACME_EMAIL="$ACME_EMAIL"

docker compose -f infra/docker-compose.prod.yml up -d --pull always

echo "Waiting for web healthcheck..."
until [ "$(docker inspect -f '{{.State.Health.Status}}' delivery-bot-web-1 2>/dev/null || echo starting)" = "healthy" ]; do
  sleep 5
done

docker compose -f infra/docker-compose.prod.yml exec -T web python manage.py createsuperuser --noinput || true

if [ -f scripts/register_webhook.py ]; then
  docker compose -f infra/docker-compose.prod.yml exec -T web python scripts/register_webhook.py || true
fi
