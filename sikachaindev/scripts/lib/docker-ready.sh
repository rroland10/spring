#!/usr/bin/env bash
# Return 0 when the Docker daemon responds within DOCKER_READY_TIMEOUT seconds.
docker_ready() {
  local timeout="${DOCKER_READY_TIMEOUT:-20}"
  if ! command -v docker >/dev/null 2>&1; then
    echo "error: docker not found — install Docker Desktop" >&2
    return 1
  fi

  docker info >/dev/null 2>&1 &
  local pid=$!
  local waited=0
  while kill -0 "${pid}" 2>/dev/null; do
    if (( waited >= timeout )); then
      kill "${pid}" 2>/dev/null || true
      wait "${pid}" 2>/dev/null || true
      echo "error: Docker daemon not responding within ${timeout}s — open or restart Docker Desktop" >&2
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done

  wait "${pid}"
}

# Run `docker compose up -d` with a wall-clock timeout (compose can hang when daemon is wedged).
# Usage: docker_compose_up -f compose.yml [ -f other.yml ] [--build] [services...]
docker_compose_up() {
  local timeout="${DOCKER_COMPOSE_TIMEOUT:-180}"
  local build=0
  local compose_args=()
  local services=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --build) build=1; shift ;;
      -f|--file) compose_args+=("$1" "$2"); shift 2 ;;
      -*) compose_args+=("$1"); shift ;;
      *) services+=("$1"); shift ;;
    esac
  done

  local cmd=(docker compose "${compose_args[@]}" up -d)
  if (( build )); then
    cmd+=(--build)
  fi
  if ((${#services[@]} > 0)); then
    cmd+=("${services[@]}")
  fi

  "${cmd[@]}" &
  local pid=$!
  local waited=0
  while kill -0 "${pid}" 2>/dev/null; do
    if (( waited >= timeout )); then
      kill "${pid}" 2>/dev/null || true
      wait "${pid}" 2>/dev/null || true
      echo "error: docker compose timed out after ${timeout}s — restart Docker Desktop" >&2
      echo "  docker compose ${compose_args[*]} ps" >&2
      return 1
    fi
    sleep 2
    waited=$((waited + 2))
  done

  wait "${pid}"
}
