#!/usr/bin/env bash
set -Eeuo pipefail
DRY_RUN=0
if [[ ${1-} == "--dry-run" ]]; then
  DRY_RUN=1
fi

log() { echo "[resolve] $*"; }

conflicts=$(git ls-files -u | cut -f2 | sort -u)
if [[ -z "$conflicts" ]]; then
  log "No conflicts to resolve"
  exit 0
fi

handle_file() {
  local file="$1"
  if [[ $file == infra/* || $file == scripts/* || $file == .github/workflows/* || $file == docs/* || $file == README.md ]]; then
    log "Theirs for $file"
    if (( DRY_RUN )); then return 0; fi
    git checkout --theirs -- "$file"
  elif [[ $file == backend/* ]]; then
    if [[ $file == backend/config/urls.py ]]; then
      log "Union for $file"
      if (( DRY_RUN )); then return 0; fi
      ours=$(git show :2:"$file" 2>/dev/null || true)
      theirs=$(git show :3:"$file" 2>/dev/null || true)
      content=$(printf "%s\n%s\n" "$ours" "$theirs" | awk 'NF' | awk '!seen[$0]++')
      if ! grep -q "healthz" <<<"$content"; then
        cat >>"$file" <<PYEOF
from django.http import JsonResponse

def healthz(request):
    return JsonResponse({"status": "ok"})

urlpatterns += [path('healthz', healthz)]
PYEOF
      else
        printf "%s" "$content" > "$file"
      fi
    else
      log "Ours for $file"
      if (( DRY_RUN )); then return 0; fi
      git checkout --ours -- "$file"
    fi
  elif [[ $file == .env.prod.example ]]; then
    log "Union for $file"
    if (( DRY_RUN )); then return 0; fi
    ours=$(git show :2:"$file" 2>/dev/null || true)
    theirs=$(git show :3:"$file" 2>/dev/null || true)
    printf "%s\n%s\n" "$ours" "$theirs" | awk '!a[$0]++' > "$file"
  elif [[ $file == infra/docker-compose.prod.yml || $file == infra/Caddyfile || $file == scripts/install_debian12.sh ]]; then
    log "Theirs with normalization for $file"
    if (( DRY_RUN )); then return 0; fi
    git checkout --theirs -- "$file"
    if [[ $file == *.yml ]]; then
      if command -v yq >/dev/null 2>&1; then yq -P -i "$file"; fi
    else
      if command -v shfmt >/dev/null 2>&1; then shfmt -w "$file"; fi
    fi
  else
    log "Default ours for $file"
    if (( DRY_RUN )); then return 0; fi
    git checkout --ours -- "$file"
  fi
}

for f in $conflicts; do
  handle_file "$f"
  if (( ! DRY_RUN )); then git add "$f"; fi
done

if (( ! DRY_RUN )); then
  git add -A
  git commit --no-edit
else
  log "Dry run complete"
fi
