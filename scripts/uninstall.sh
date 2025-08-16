#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."

systemctl disable --now foodbot 2>/dev/null || true
docker compose -f infra/docker-compose.prod.yml down -v || true
