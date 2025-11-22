#!/usr/bin/env bash
set -euo pipefail

# create_image_for_flashing.sh
# Download and prepare the openSUSE MicroOS image for flashing.
# - Downloads the raw.xz (configurable URL)
# - Optionally decompresses it
# - Optionally runs `flash_and_apply_overlays.sh` in EXTRACT_ONLY mode to extract overlays
# - Supports running those steps either on host or inside a container (podman/docker) using aarch64 image if desired

IMG_URL="https://download.opensuse.org/ports/aarch64/tumbleweed/appliances/openSUSE-MicroOS.aarch64-16.0.0-ContainerHost-RaspberryPi-Snapshot20251121.raw.xz"
WORKDIR=$(pwd)
IMG_XZ="$WORKDIR/openSUSE-MicroOS.raw.xz"
IMG_RAW="$WORKDIR/openSUSE-MicroOS.raw"
RUN_IN_CONTAINER=0
ENGINE="auto"
DECOMPRESS=1
EXTRACT_ONLY=1
YES=0

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --url URL             image URL to download (default: MicroOS aarch64 raw.xz)
  --no-decompress       skip decompress step
  --container           run decompress/extract inside an aarch64 container (uses podman/docker)
  --engine NAME         container engine to prefer (podman or docker)
  --help                show this help

Examples:
  $0
  $0 --container --engine podman

After preparing the image this script will leave the raw image in the current directory
and, if EXTRACT_ONLY behavior is triggered, will run `flash_and_apply_overlays.sh` in a mode
that simulates mounts (no flashing) and extracts overlays into `boot-sim/overlays`.
EOF
}

while [[ ${#} -gt 0 ]]; do
  case "$1" in
    --url) IMG_URL="$2"; shift 2 ;;
    --no-decompress) DECOMPRESS=0; shift 1 ;;
    --container) RUN_IN_CONTAINER=1; shift 1 ;;
    --engine) ENGINE="$2"; shift 2 ;;
    --yes|-y) YES=1; shift 1 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

echo "Image URL: $IMG_URL"

if [[ ! -f "$IMG_XZ" ]]; then
  echo "Downloading $IMG_URL -> $IMG_XZ"
  curl -L -o "$IMG_XZ" "$IMG_URL"
else
  echo "$IMG_XZ already exists; skipping download"
fi

if [[ "$DECOMPRESS" -eq 1 ]]; then
  if [[ ! -f "$IMG_RAW" ]]; then
    echo "Decompressing $IMG_XZ -> $IMG_RAW"
    xz -d -k "$IMG_XZ"
  else
    echo "$IMG_RAW already exists; skipping decompress"
  fi
else
  echo "Skipping decompression as requested"
fi

if [[ "$RUN_IN_CONTAINER" -eq 1 ]]; then
  # run flash_and_apply_overlays.sh in container in EXTRACT_ONLY=1 mode
  ENGINE_CMD="$ENGINE"
  if [[ "$ENGINE_CMD" == "auto" ]]; then
    if command -v podman >/dev/null 2>&1; then
      ENGINE_CMD=podman
    elif command -v docker >/dev/null 2>&1; then
      ENGINE_CMD=docker
    else
      echo "No container engine found (podman/docker)" >&2
      exit 1
    fi
  fi
  echo "Running extraction inside container via $ENGINE_CMD"
  tar -C . -cf - . | $ENGINE_CMD run --rm --platform linux/arm64 -i docker.io/library/python:3.12-slim-bullseye bash -lc '
    set -euo pipefail
    mkdir -p /work
    tar -C /work -xf -
    cd /work
    # make the script executable then run in extract-only mode
    EXTRACT_ONLY=1 ./flash_and_apply_overlays.sh "$IMG_RAW"
  '
else
  echo "Running extract-only on host: EXTRACT_ONLY=1 ./flash_and_apply_overlays.sh $IMG_RAW"
  EXTRACT_ONLY=1 YES=${YES} ./flash_and_apply_overlays.sh "$IMG_RAW"
fi

echo "Done. Prepared image: $IMG_RAW"
