#!/usr/bin/env bash
set -euo pipefail

# Rebind the RP1 DSI driver if the panel is not connected at boot.
# Uses --quiesce mode by default: turns backlight off before unbind
# and restores after bind to prevent kernel OOPS (data abort) during
# DMA state transitions. See docs/dsi-rebind-testing.md.
DEV_DRIVER="/sys/bus/platform/drivers/drm-rp1-dsi"
BL_PATH="/sys/class/backlight/backlight@0/brightness"
RETRIES=3
SLEEP=2

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
  echo "uconsole-dsi-rebind: attempting quiesce rebind of $DEV (try $i)"

  # Quiesce: turn off backlight before unbind to prevent OOPS
  [ -w "$BL_PATH" ] && echo 0 > "$BL_PATH" 2>/dev/null || true

  sudo sh -c "echo -n $DEV > $DEV_DRIVER/unbind" || true
  sleep $SLEEP
  sudo sh -c "echo -n $DEV > $DEV_DRIVER/bind" || true
  sleep $SLEEP

  # Restore backlight
  [ -w "$BL_PATH" ] && echo 5 > "$BL_PATH" 2>/dev/null || true

  # Check for OOPS — abort if detected
  if journalctl -k --since "-10s" 2>/dev/null | grep -qi "oops\|data abort\|translation fault"; then
    echo "uconsole-dsi-rebind: OOPS detected after rebind, aborting"
    exit 1
  fi
done

exit 0
