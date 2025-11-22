#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <device_ip> <ssh_user> <ssh_key> [--reboot]"
  echo "Example: $0 192.168.1.100 myuser ~/.ssh/id_rsa --reboot"
  exit 1
fi

DEST_HOST="$1"
DEST_USER="$2"
SSH_KEY="$3"
REBOOT=false
INSTALL_DTC=false
MIN_EXTRACONFIG=false
MIN_OVERLAYS=()
for arg in "${@:4}"; do
  case "$arg" in
    --reboot) REBOOT=true ;;
    --install-dtc) INSTALL_DTC=true ;;
    --min-extraconfig) MIN_EXTRACONFIG=true ;;
    --help|-h) echo "Usage: $0 <host> <user> <ssh_key> [--reboot] [--install-dtc] [--min-extraconfig overlay1 overlay2 ...]"; exit 0 ;;
    *)
      if [ "$MIN_EXTRACONFIG" = true ]; then
        MIN_OVERLAYS+=("$arg")
      else
        echo "Unknown argument: $arg"; exit 1
      fi
      ;;
  esac
done

echo "[deploy_and_diagnose] Building and deploying artifacts..."
if [ "$INSTALL_DTC" = true ]; then
  ./scripts/deploy_to_device.sh "$DEST_HOST" "$DEST_USER" "$SSH_KEY" ${REBOOT:+--reboot} --install-dtc
else
  ./scripts/deploy_to_device.sh "$DEST_HOST" "$DEST_USER" "$SSH_KEY" ${REBOOT:+--reboot}
fi

if [ "$MIN_EXTRACONFIG" = true ]; then
  ./scripts/set_min_extraconfig.sh "$DEST_HOST" "$DEST_USER" "$SSH_KEY" --apply "${MIN_OVERLAYS[@]}"
fi

echo "[deploy_and_diagnose] Waiting for target to become reachable (SSH)..."
COUNT=0
until ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$DEST_USER@$DEST_HOST" 'true' 2>/dev/null; do
  sleep 3
  COUNT=$((COUNT+1))
  if [ "$COUNT" -gt 40 ]; then
    echo "Timed out waiting for SSH access to $DEST_HOST"
    exit 1
  fi
done

echo "[deploy_and_diagnose] Running remote diagnostics..."
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no tools/diagnose_pinctrl_rp1.sh "$DEST_USER@$DEST_HOST:/tmp/diagnose_pinctrl_rp1.sh"
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$DEST_USER@$DEST_HOST" 'sudo bash /tmp/diagnose_pinctrl_rp1.sh'

echo "Done. See output above for diagnostic results."
