#!/usr/bin/env bash
# shellcheck disable=SC2016
# Install real gh in Debian Trixie and Fedora containers, then check:
#   - a second install reports that gh is already present
#   - init.sh without a terminal stops at login instead of hanging
#   - Debian bookworm stops before installing gh
# Login itself stays interactive and is covered by tests/test_init.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if command -v podman >/dev/null 2>&1; then
  if podman info >/dev/null 2>&1; then
    RUNTIME=(podman)
  elif sudo podman info >/dev/null 2>&1; then
    RUNTIME=(sudo podman)
  fi
fi
if [[ -z "${RUNTIME+x}" ]] && command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then
    RUNTIME=(docker)
  elif sudo docker info >/dev/null 2>&1; then
    RUNTIME=(sudo docker)
  fi
fi
if [[ -z "${RUNTIME+x}" ]]; then
  printf 'error: podman or docker is required\n' >&2
  exit 1
fi

# fuse-overlayfs is not always available in this environment.
if ! "${RUNTIME[@]}" info >/dev/null 2>&1; then
  printf 'error: %s cannot talk to its engine\n' "${RUNTIME[*]}" >&2
  exit 1
fi

run_container() {
  local name="$1"
  shift
  printf '\n==== %s ====\n' "$name"
  "${RUNTIME[@]}" run --rm --name "$name" \
    -v "$ROOT:/src:ro" \
    "$@"
}

run_container "init-bookworm" debian:bookworm-slim \
  bash -c 'set -euo pipefail
    set +e
    bash /src/init.sh > /tmp/out 2>&1
    status=$?
    set -e
    cat /tmp/out
    if [[ "$status" -eq 0 ]]; then
      printf "bookworm should have failed\n" >&2
      exit 1
    fi
    if ! grep -q trixie /tmp/out; then
      printf "bookworm output did not mention trixie\n" >&2
      exit 1
    fi
    if command -v gh >/dev/null 2>&1; then
      printf "bookworm installed gh\n" >&2
      exit 1
    fi
    if [[ -e /etc/apt/sources.list.d/github-cli.list ]]; then
      printf "bookworm added the GitHub apt repo\n" >&2
      exit 1
    fi
    printf "bookworm stopped before installing gh\n"
  '

install_twice() {
  local image="$1"
  local name="$2"
  run_container "$name" "$image" bash -c 'set -euo pipefail
    bash -c "
      set -euo pipefail
      source /src/init.sh
      detect_os
      install_github_cli
      echo ---- second ----
      install_github_cli
    " | tee /tmp/install.log
    command -v gh
    gh --version
    if ! grep -q "already installed" /tmp/install.log; then
      printf "second install did not skip\n" >&2
      exit 1
    fi
    set +e
    timeout 60 bash /src/init.sh > /tmp/rerun.log 2>&1
    status=$?
    set -e
    cat /tmp/rerun.log
    if [[ "$status" -eq 0 ]]; then
      printf "rerun without a login should not succeed\n" >&2
      exit 1
    fi
    if ! grep -q -e terminal -e "Log in" -e "gh auth login" /tmp/rerun.log; then
      printf "rerun did not stop with a login message\n" >&2
      exit 1
    fi
    printf "gh install is idempotent and login stops without a terminal\n"
  '
}

install_twice debian:trixie init-debian-trixie
install_twice fedora:latest init-fedora

printf '\ncontainer checks passed\n'
