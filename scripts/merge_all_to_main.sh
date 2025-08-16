#!/usr/bin/env bash
set -Eeuo pipefail

TARGET="main"
DRY_RUN=0
OPEN_PR=0
LABEL="mega-merge"

usage() {
  echo "Usage: $0 [--target <branch>] [--dry-run] [--open-pr] [--label <name>]" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      TARGET="$2"; shift 2;;
    --dry-run)
      DRY_RUN=1; shift;;
    --open-pr)
      OPEN_PR=1; shift;;
    --label)
      LABEL="$2"; shift 2;;
    *)
      usage;;
  esac
done

log() { echo "[merge-all] $*"; }

ensure_clean() {
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "Working tree is dirty. Commit or stash changes." >&2
    exit 1
  fi
}

fetch_remotes() {
  log "Fetching remotes"
  git fetch --all --prune
}

list_active_branches() {
  git branch -r --format='%(refname:strip=2)' \
    | grep -vE "^(origin/)?(main|HEAD|gh-pages)$" \
    | grep -vE '^origin/dependabot/' \
    | grep -vE '^origin/deprecated/' \
    | sed 's|origin/||'
}

sort_branches() {
  while read -r b; do
    p=99
    case "$b" in
      release/*) p=1;;
      hotfix/*) p=2;;
      codex/*) p=3;;
      feature/*) p=4;;
      chore/*) p=5;;
      docs/*) p=6;;
    esac
    printf "%02d %s\n" "$p" "$b"
  done | sort -n | cut -d' ' -f2
}

create_integration_branch() {
  local base="integration/merge-all-$(date +%Y%m%d-%H%M)"
  local branch="$base"
  local i=2
  while git rev-parse --verify --quiet "$branch" >/dev/null; do
    branch="${base}-${i}"
    ((i++))
  done
  log "Creating integration branch $branch from origin/$TARGET"
  git checkout -b "$branch" "origin/$TARGET"
  INTEGRATION_BRANCH="$branch"
}

run_merge() {
  local b="$1"
  log "Merging $b"
  if (( DRY_RUN )); then
    if git merge --no-commit --no-ff "origin/$b"; then
      scripts/post_merge_check.sh || { git merge --abort; RESULT="check failed"; return 1; }
      git merge --abort
      RESULT="merged"
      return 0
    else
      scripts/resolve_conflicts.sh --dry-run || true
      git merge --abort
      RESULT="conflicts"
      return 1
    fi
  else
    if git merge --no-ff --no-edit "origin/$b"; then
      scripts/post_merge_check.sh && { RESULT="merged"; return 0; }
      git reset --hard HEAD~1
      RESULT="check failed"
      return 1
    else
      if scripts/resolve_conflicts.sh; then
        scripts/post_merge_check.sh && { RESULT="merged"; return 0; }
      fi
      git reset --hard HEAD~1
      RESULT="conflicts"
      return 1
    fi
  fi
}

update_merge_plan() {
  {
    echo "# Mega Merge Plan"
    echo
    echo "## Remote branches snapshot"
    git branch -r
    echo
    echo "## Merge order"
    for b in ${ORDERED_BRANCHES}; do
      echo "- $b"
    done
    echo
    echo "## Results"
    echo "| Branch | Result |"
    echo "|--------|--------|"
    printf "%s" "$REPORT"
    if [[ -n "$PR_URL" ]]; then
      echo
      echo "## Pull Request"
      echo "$PR_URL"
    fi
  } > MERGE_PLAN.md
}

open_pr() {
  if (( OPEN_PR )); then
    scripts/open_mega_merge_pr.sh --label "$LABEL" && PR_URL=$(cat .pr_url 2>/dev/null || true)
  fi
}

main() {
  ensure_clean
  fetch_remotes
  BRANCHES=$(list_active_branches)
  ORDERED_BRANCHES=$(printf "%s\n" "$BRANCHES" | sort_branches)
  create_integration_branch
  REPORT=""
  for b in $ORDERED_BRANCHES; do
    if run_merge "$b"; then
      REPORT+="| $b | $RESULT |\n"
    else
      REPORT+="| $b | $RESULT |\n"
      break
    fi
  done
  update_merge_plan
  if (( ! DRY_RUN )); then
    log "Pushing $INTEGRATION_BRANCH"
    git push -u origin "$INTEGRATION_BRANCH"
    open_pr
  fi
}

main "$@"
