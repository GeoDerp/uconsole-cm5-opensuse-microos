#!/usr/bin/env bash
set -euo pipefail

usage(){
  cat <<EOF
Usage: $0 <device_ip> <ssh_user> <ssh_key> --preload overlay1 [overlay2 ...] --test overlayA overlayB ... [--reboot-wait 60]

Runs a one-by-one overlay re-introduction test.
--preload overlays will always be enabled (e.g., rp1-i2c1-fix, clockworkpi-uconsole).
--test overlays will be reintroduced one-by-one on top of the preload; the script reboots and runs diagnostics for each.
Outputs logs to ./test-results/<overlay>.log and a summary file ./test-results/summary.txt

Example:
  ./scripts/reintroduce_overlay_test.sh 192.168.1.100 myuser ~/.ssh/id_rsa --preload rp1-i2c1-fix clockworkpi-uconsole --test i2c1 i2c1-pi5 rpi-display --reboot-wait 60

EOF
}

if [ "$#" -lt 6 ]; then
  usage; exit 1
fi

DEST_HOST="$1"
DEST_USER="$2"
SSH_KEY="$3"
shift 3

PRELOAD=()
TEST_OVERLAYS=()
REBOOT_WAIT=60
DISABLE_CONFLICTS=false
KEEP_DISABLED=false
MODE=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --preload) MODE="preload"; shift; ;;
    --test) MODE="test"; shift; ;;
    --reboot-wait) REBOOT_WAIT="$2"; shift 2; ;;
    --help|-h) usage; exit 0 ;;
    --disable-conflicts) DISABLE_CONFLICTS=true; shift; ;;
    --keep-disabled) KEEP_DISABLED=true; shift; ;;
    *)
      if [ "$MODE" = "preload" ]; then
        PRELOAD+=("$1")
        shift
      elif [ "$MODE" = "test" ]; then
        TEST_OVERLAYS+=("$1")
        shift
      else
        echo "Unexpected positional argument $1"; usage; exit 1
      fi
      ;;
  esac
done

mkdir -p test-results
SUMMARY=test-results/summary.txt
echo "Overlay re-introduction test - $(date)" > "$SUMMARY"
echo "Device: $DEST_HOST" >> "$SUMMARY"
echo "Preload: ${PRELOAD[*]}" >> "$SUMMARY"
echo "Test Overlays: ${TEST_OVERLAYS[*]}" >> "$SUMMARY"
echo "" >> "$SUMMARY"

apply_preload(){
  overlays="$*"
  echo "Applying preload overlays: $overlays"
  ./scripts/set_min_extraconfig.sh "$DEST_HOST" "$DEST_USER" "$SSH_KEY" --apply $overlays
}

wait_for_ssh(){
  local target="$1"
  local user="$2"
  local key="$3"
  local timeout=${4:-300}
  local count=0
  until ssh -i "$key" -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$user@$target" 'true' 2>/dev/null; do
    sleep 3
    count=$((count+1))
    if [ "$count" -gt $((timeout/3)) ]; then
      echo "Timed out waiting for SSH after $timeout seconds"; return 1
    fi
  done
  return 0
}

# Backup original extraconfig before starting.
echo "Backing up current extraconfig files on target..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$DEST_USER@$DEST_HOST" "sudo transactional-update run /bin/sh -c 'if [ -f /boot/vc/extraconfig.txt ]; then cp /boot/vc/extraconfig.txt /boot/vc/extraconfig.txt.reintro.orig; fi; if [ -f /boot/efi/extraconfig.txt ]; then cp /boot/efi/extraconfig.txt /boot/efi/extraconfig.txt.reintro.orig; fi'"

# Start with a minimal preload extraconfig
apply_preload ${PRELOAD[*]}

echo "Rebooting initial preload..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$DEST_USER@$DEST_HOST" 'sudo systemctl reboot'
wait_for_ssh "$DEST_HOST" "$DEST_USER" "$SSH_KEY" 300 || (echo "SSH did not return; aborting"; exit 1)
sleep "$REBOOT_WAIT"

if [ "$DISABLE_CONFLICTS" = true ]; then
  echo "Disabling conflict overlays (moving DTBOs to disabled/) on target..."
  ./scripts/find_and_disable_conflict_overlays.sh "$DEST_HOST" "$DEST_USER" "$SSH_KEY" --apply --disable-files
  echo "Done disabling conflicting overlays"
  echo
fi

echo "Starting one-by-one overlay tests..."
for overlay in "${TEST_OVERLAYS[@]}"; do
  echo "Testing overlay: $overlay"
  echo "Test overlay: $overlay" >> "$SUMMARY"
  # apply preload + overlay
  ./scripts/set_min_extraconfig.sh "$DEST_HOST" "$DEST_USER" "$SSH_KEY" --apply ${PRELOAD[*]} "$overlay"
  echo "Rebooting..."
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$DEST_USER@$DEST_HOST" 'sudo systemctl reboot'
  wait_for_ssh "$DEST_HOST" "$DEST_USER" "$SSH_KEY" 300 || (echo "Failed to contact host after reboot; continuing to next overlay"; echo "SSH timeout after reboot - $overlay" >> "$SUMMARY"; continue)
  sleep "$REBOOT_WAIT"
  # run diagnostics
  LOG=test-results/${overlay}.log
  scp -i "$SSH_KEY" -o StrictHostKeyChecking=no tools/diagnose_pinctrl_rp1.sh "$DEST_USER@$DEST_HOST:/tmp/diagnose_pinctrl_rp1.sh"
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$DEST_USER@$DEST_HOST" "sudo bash /tmp/diagnose_pinctrl_rp1.sh" | tee "$LOG"
  if grep -qi "invalid brcm,pins" "$LOG" || grep -qi "pinctrl-rp1" "$LOG"; then
    echo "RESULT: FAIL - pinctrl-rp1 error present with overlay $overlay" >> "$SUMMARY"
  else
    echo "RESULT: PASS - no pinctrl-rp1 errors detected with overlay $overlay" >> "$SUMMARY"
  fi
  echo "---" >> "$SUMMARY"
done

echo "Tests completed. Restoring original extraconfigs..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$DEST_USER@$DEST_HOST" "sudo transactional-update run /bin/sh -c 'if [ -f /boot/vc/extraconfig.txt.reintro.orig ]; then cat /boot/vc/extraconfig.txt.reintro.orig > /boot/vc/extraconfig.txt; fi; if [ -f /boot/efi/extraconfig.txt.reintro.orig ]; then cat /boot/efi/extraconfig.txt.reintro.orig > /boot/efi/extraconfig.txt; fi'"

echo "Rebooting after test restore..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$DEST_USER@$DEST_HOST" 'sudo systemctl reboot'

echo "Summary of test results (saved to $SUMMARY):"
cat "$SUMMARY"

if [ "$DISABLE_CONFLICTS" = true ] && [ "$KEEP_DISABLED" = false ]; then
  echo "Restoring disabled overlays on target..."
  ./scripts/find_and_disable_conflict_overlays.sh "$DEST_HOST" "$DEST_USER" "$SSH_KEY" --restore
  echo "Rebooting after restoring disabled overlays..."
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$DEST_USER@$DEST_HOST" 'sudo systemctl reboot'
fi

exit 0
