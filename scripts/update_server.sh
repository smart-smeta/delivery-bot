#!/usr/bin/env bash
set -Eeuo pipefail
BRANCH="${1:-main}"
cd "$(dirname "$0")/.."
source .env.prod

git fetch --all
git checkout "$BRANCH"
git pull --rebase

docker compose -f infra/docker-compose.prod.yml pull

docker compose -f infra/docker-compose.prod.yml up -d --build

docker compose -f infra/docker-compose.prod.yml exec -T web python manage.py migrate --noinput
docker compose -f infra/docker-compose.prod.yml exec -T web python manage.py collectstatic --noinput

curl -sf "$APP_BASE_URL/healthz" >/dev/null
