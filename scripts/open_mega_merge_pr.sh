#!/usr/bin/env bash
set -Eeuo pipefail
LABEL="mega-merge"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --label)
      LABEL="$2"; shift 2;;
    *) shift;;
  esac
done

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI 'gh' not found. Please create PR manually." >&2
  exit 0
fi

current_branch=$(git rev-parse --abbrev-ref HEAD)
date_str=$(date +%F)
TITLE="Merge all active branches into main (integration $date_str)"
BODY=$(cat <<BODY
## Goal
Merge all active branches into main.

## Merged Branches
$(grep '^-' MERGE_PLAN.md || true)

## Conflict Rules
- theirs: infra/**, scripts/**, .github/workflows/**, docs/**, README.md
- ours: backend/**
- union: backend/config/urls.py, .env.prod.example, infra/docker-compose.prod.yml, infra/Caddyfile, scripts/install_debian12.sh

## Post merge checks
$(grep '^| ' MERGE_PLAN.md || true)

### Checklist
- [ ] CI зелёный
- [ ] Smoke-сборка прошла
- [ ] Проверен `/healthz`

BODY
)

if ! gh label list | grep -q "^$LABEL"; then
  gh label create "$LABEL" --color "#ededed" --description "Mega merge" >/dev/null 2>&1 || true
fi

pr_url=$(gh pr create --base main --head "$current_branch" --title "$TITLE" --body "$BODY" --label "$LABEL")
[ -n "$pr_url" ] && echo "$pr_url" > .pr_url
