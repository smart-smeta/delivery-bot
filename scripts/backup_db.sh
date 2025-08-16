#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."
source .env.prod
BACKUP_DIR="backups"
mkdir -p "$BACKUP_DIR"
FILE="$BACKUP_DIR/foodbot-$(date +%Y%m%d-%H%M).sql.gz"
docker compose -f infra/docker-compose.prod.yml exec -T db pg_dump -U foodbot foodbot | gzip > "$FILE"
find "$BACKUP_DIR" -type f -mtime +7 -delete
