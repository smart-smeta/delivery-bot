#!/usr/bin/env bash
set -euo pipefail
BACKUP_DIR=/opt/foodbot/backups
mkdir -p "$BACKUP_DIR"
find "$BACKUP_DIR" -type f -mtime +14 -delete
FILE="$BACKUP_DIR/foodbot-$(date +%Y%m%d-%H%M%S).sql.gz"

docker compose -f infra/docker-compose.prod.yml exec -T db pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" | gzip > "$FILE"

if [[ -n "${GPG_RECIPIENT:-}" ]]; then
  gpg --batch --yes --encrypt -r "$GPG_RECIPIENT" "$FILE" && rm "$FILE"
fi
