#!/usr/bin/env bash
set -Eeuo pipefail

log() { echo "[post-check] $*"; }

run_tests() {
  if [[ -f Makefile ]]; then
    log "Running make lint"
    make lint || log "make lint failed (non-fatal)"
    log "Running make test"
    make test
    return
  fi
  if [[ -f pytest.ini || -f pyproject.toml || -d tests ]]; then
    log "Running pytest"
    pytest -q
    return
  fi
  log "No tests to run"
}

validate_compose() {
  if [[ -f infra/docker-compose.prod.yml ]]; then
    log "Validating docker compose"
    docker compose -f infra/docker-compose.prod.yml config -q
  fi
}

shell_lint() {
  if command -v shellcheck >/dev/null 2>&1; then
    log "Running shellcheck"
    shellcheck scripts/*.sh || log "shellcheck warnings"
  fi
}

run_tests
validate_compose
shell_lint
