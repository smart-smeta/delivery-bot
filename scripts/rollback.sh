#!/usr/bin/env bash
set -Eeuo pipefail
TO=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --to) TO="$2"; shift 2;;
    *) echo "Usage: rollback.sh --to <git-ref>" >&2; exit 1;;
  esac
done

if [[ -z "$TO" ]]; then
  echo "--to ref required" >&2
  exit 1
fi

cd "$(dirname "$0")/.."

git fetch --all
git checkout "$TO"

docker compose -f infra/docker-compose.prod.yml up -d --build
docker compose -f infra/docker-compose.prod.yml exec -T web python manage.py migrate --noinput
docker compose -f infra/docker-compose.prod.yml exec -T web python manage.py collectstatic --noinput

echo "Rolled back to $TO"
