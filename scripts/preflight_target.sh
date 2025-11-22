#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <device_ip> <ssh_user> <ssh_key>"
  exit 1
fi

DEST_HOST="$1"
DEST_USER="$2"
SSH_KEY="$3"

echo "Preflight checks for $DEST_USER@$DEST_HOST"

echo "[1] Test SSH connectivity"
ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$DEST_USER@$DEST_HOST" 'echo SSH OK' || { echo "SSH not reachable"; exit 2; }

echo "[2] Check for /boot/vc and /boot/efi"
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$DEST_USER@$DEST_HOST" 'ls -ld /boot/vc /boot/efi 2>/dev/null || true'

echo "[3] Check dtc presence"
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$DEST_USER@$DEST_HOST" 'command -v dtc || echo "dtc missing"'

echo "[4] Check kernel headers and build link"
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$DEST_USER@$DEST_HOST" 'KVER=$(uname -r); if [ -d /lib/modules/$KVER/build ]; then echo "/lib/modules/$KVER/build present"; else echo "/lib/modules/$KVER/build missing (kernel-devel not installed)"; fi'

echo "[5] Print extraconfig and config versions in /boot partition(s)"
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$DEST_USER@$DEST_HOST" 'echo "--- /boot/vc/extraconfig.txt"; [ -f /boot/vc/extraconfig.txt ] && sed -n "1,200p" /boot/vc/extraconfig.txt || echo "(not found)"; echo "--- /boot/efi/extraconfig.txt"; [ -f /boot/efi/extraconfig.txt ] && sed -n "1,200p" /boot/efi/extraconfig.txt || echo "(not found)"'

echo "[6] List overlays in /boot/vc/overlays and /boot/efi/overlays"
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$DEST_USER@$DEST_HOST" 'ls -1 /boot/vc/overlays 2>/dev/null || true; ls -1 /boot/efi/overlays 2>/dev/null || true'

echo "Preflight checks complete." 
exit 0
