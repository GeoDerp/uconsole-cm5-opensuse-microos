#!/usr/bin/env bash
set -euo pipefail

# Rebind the RP1 DSI driver if the panel is not connected at boot.
# Safe to run multiple times.
DEV_DRIVER="/sys/bus/platform/drivers/drm-rp1-dsi"
RETRIES=3
SLEEP=1

for i in $(seq 1 $RETRIES); do
  if [ ! -d "$DEV_DRIVER" ]; then
    exit 0
  fi
  DEV=$(ls "$DEV_DRIVER" 2>/dev/null | grep -E 'dsi|1f00' || true)
  if [ -z "$DEV" ]; then
    exit 0
  fi
  # If connector already connected, nothing to do
  if grep -q connected /sys/class/drm/*-DSI-*/status 2>/dev/null; then
    exit 0
  fi
  echo "uconsole-dsi-rebind: attempting rebind of $DEV (try $i)"
  sudo sh -c "echo -n $DEV > $DEV_DRIVER/unbind" || true
  sleep $SLEEP
  sudo sh -c "echo -n $DEV > $DEV_DRIVER/bind" || true
  sleep $SLEEP
done

exit 0
