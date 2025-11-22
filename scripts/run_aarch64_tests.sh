#!/usr/bin/env bash
set -euo pipefail

# run_aarch64_tests.sh
# Run the repository's tests inside an aarch64 container using podman or docker.
# Features:
# - automatic choose of podman/docker (prefers podman)
# - optional image pull/caching
# - optional installation of `dtc` in the container for dtc-related tests
# - runs only the tests directory by default and sets PYTHONPATH so local package imports work

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --engine NAME         container engine to use: podman or docker (default: auto-detect podman then docker)
  --image IMAGE         container image to use (default: docker.io/library/python:3.12-slim-bullseye)
  --pull                force pull of the image before running
  --with-dtc            install dtc (device-tree-compiler) inside the container before running tests
  --tests PATH          path to tests to run inside container (default: /work/tests)
  --help                show this help

Examples:
  $0 --pull --with-dtc
  $0 --engine docker --image python:3.11-slim

This script copies the current workspace into the container (avoids host mount permission issues)
and runs pytest there. It will use qemu transparently if the engine supports running aarch64 images
on the host.
EOF
}

ENGINE="auto"
IMAGE="docker.io/library/python:3.12-slim-bullseye"
PULL=0
WITH_DTC=0
TESTS_PATH="/work/tests"

while [[ ${#} -gt 0 ]]; do
  case "$1" in
    --engine) ENGINE="$2"; shift 2 ;;
    --image) IMAGE="$2"; shift 2 ;;
    --pull) PULL=1; shift 1 ;;
    --with-dtc) WITH_DTC=1; shift 1 ;;
    --tests) TESTS_PATH="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

find_engine() {
  if [[ "$ENGINE" != "auto" ]]; then
    echo "$ENGINE"
    return
  fi
  if command -v podman >/dev/null 2>&1; then
    echo podman
  elif command -v docker >/dev/null 2>&1; then
    echo docker
  else
    echo "" # none
  fi
}

ENGINE_CMD=$(find_engine)
if [[ -z "$ENGINE_CMD" ]]; then
  echo "Error: neither podman nor docker found on PATH" >&2
  exit 1
fi

echo "Using container engine: $ENGINE_CMD"

if [[ "$PULL" -eq 1 ]]; then
  echo "Pulling image: $IMAGE"
  $ENGINE_CMD pull --platform linux/arm64 "$IMAGE"
fi

# Build the container command. We'll copy the repo into the container via tar to avoid
# permission issues with volume mounts and rootless containers.

CONTAINER_CMD=(bash -lc)
CONTAINER_CMD+=($(cat <<'BASH'
  set -euo pipefail
  mkdir -p /work
  tar -C /work -xf -
  python -m venv /tmp/venv
  /tmp/venv/bin/pip install --quiet pytest
  if [ "${WITH_DTC}" = "1" ]; then
    # try apt-get/dnf/zypper depending on image. attempt apt first.
    if command -v apt-get >/dev/null 2>&1; then
      apt-get update && apt-get install -y --no-install-recommends device-tree-compiler || true
    elif command -v dnf >/dev/null 2>&1; then
      dnf install -y dtc || true
    elif command -v zypper >/dev/null 2>&1; then
      zypper --non-interactive install dtc || true
    else
      echo "Unable to install dtc automatically inside container; continuing without it" >&2
    fi
  fi
  PYTHONPATH=/work /tmp/venv/bin/pytest -q "$TESTS_PATH"
BASH
))

echo "Starting container to run tests (image=$IMAGE) ..."

# Use platform linux/arm64 to force arm64 image and qemu emulation if necessary
tar -C . -cf - . | $ENGINE_CMD run --rm --platform linux/arm64 -i "$IMAGE" "${CONTAINER_CMD[@]}"
