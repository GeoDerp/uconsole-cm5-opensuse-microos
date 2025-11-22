#!/usr/bin/env bash
set -euo pipefail

usage(){
  cat <<EOF
Usage: $0 <device_ip> <ssh_user> <ssh_key> [--reboot-wait 60] [--keep-disabled]

High-level orchestration script to deploy DTB, DTBOs, install dtc, remove conflicting overlays, build & install extracted drivers, then run the re-introduction overlay test.
Example:
  ./scripts/run_full_uconsole_tests.sh 192.168.1.100 myuser ~/.ssh/id_rsa --reboot-wait 60
EOF
}

if [ "$#" -lt 3 ]; then
  usage; exit 1
fi
DEST_HOST="$1"
DEST_USER="$2"
SSH_KEY="$3"
shift 3
REBOOT_WAIT=60
KEEP_DISABLED=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --reboot-wait) REBOOT_WAIT="$2"; shift 2; ;;
    --keep-disabled) KEEP_DISABLED=true; shift; ;;
    -h|--help) usage; exit 0; ;;
    *) echo "Unknown arg: $1"; exit 1; ;;
  esac
done

echo "Step 1: Deploy merged DTB and DTBO overlays, install dtc, and optionally use min-extraconfig"
./scripts/deploy_and_diagnose.sh "$DEST_HOST" "$DEST_USER" "$SSH_KEY" --install-dtc --reboot --min-extraconfig rp1-i2c1-fix clockworkpi-uconsole

echo "Waiting ${REBOOT_WAIT}s after reboot for services..."
sleep ${REBOOT_WAIT}

echo "Step 2: Find and disable conflicting overlays"
./scripts/find_and_disable_conflict_overlays.sh "$DEST_HOST" "$DEST_USER" "$SSH_KEY" --apply --disable-files --reboot
sleep ${REBOOT_WAIT}

echo "Step 3: Build and deploy extracted drivers on the target"
./scripts/deploy_and_build_drivers.sh "$DEST_HOST" "$DEST_USER" "$SSH_KEY" --install-deps
sleep ${REBOOT_WAIT}

echo "Step 4: Run the overlay re-introduction harness"
./scripts/reintroduce_overlay_test.sh "$DEST_HOST" "$DEST_USER" "$SSH_KEY" --preload rp1-i2c1-fix clockworkpi-uconsole --test i2c1 i2c1-pi5 rpi-display --reboot-wait ${REBOOT_WAIT}

if [ "$KEEP_DISABLED" = false ]; then
  echo "Restoring disabled overlays" 
  ./scripts/find_and_disable_conflict_overlays.sh "$DEST_HOST" "$DEST_USER" "$SSH_KEY" --restore --reboot
fi

echo "Full run completed. Check test-results/ for logs and summary"
exit 0
