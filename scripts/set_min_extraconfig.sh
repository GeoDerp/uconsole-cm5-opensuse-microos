#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 4 ]; then
  echo "Usage: $0 <device_ip> <ssh_user> <ssh_key> --apply|--revert [overlay1 overlay2 ...]"
  echo "Example: $0 192.168.1.100 myuser ~/.ssh/id_rsa --apply rp1-i2c1-fix clockworkpi-uconsole"
  exit 1
fi

DEST_HOST="$1"
DEST_USER="$2"
SSH_KEY="$3"
ACTION="$4"
shift 4

if [ "$ACTION" = "--apply" ]; then
  if [ "$#" -lt 1 ]; then
    echo "Please specify overlay names to enable (e.g. rp1-i2c1-fix)."; exit 1
  fi
  echo "Applying minimal extraconfig to $DEST_HOST (overlays: $*)"
  TMPFILE=$(mktemp)
  for o in "$@"; do
    echo "dtoverlay=$o" >> "$TMPFILE"
  done
  scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$TMPFILE" "$DEST_USER@$DEST_HOST:/tmp/extraconfig.tmp"
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$DEST_USER@$DEST_HOST" \
    "sudo transactional-update run /bin/sh -c 'if [ -f /boot/vc/extraconfig.txt ]; then cp /boot/vc/extraconfig.txt /boot/vc/extraconfig.txt.orig; fi; cat /tmp/extraconfig.tmp > /boot/vc/extraconfig.txt; sha256sum /boot/vc/extraconfig.txt'"
  if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$DEST_USER@$DEST_HOST" 'test -d /boot/efi' >/dev/null 2>&1; then
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$DEST_USER@$DEST_HOST" \
      "sudo transactional-update run /bin/sh -c 'if [ -f /boot/efi/extraconfig.txt ]; then cp /boot/efi/extraconfig.txt /boot/efi/extraconfig.txt.orig; fi; cat /tmp/extraconfig.tmp > /boot/efi/extraconfig.txt; sha256sum /boot/efi/extraconfig.txt'"
  fi
  echo "Applied minimal extraconfig on $DEST_HOST. Reboot recommended."
elif [ "$ACTION" = "--revert" ]; then
  echo "Reverting extraconfig on $DEST_HOST (restore from /boot/vc/extraconfig.txt.orig if present)."
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$DEST_USER@$DEST_HOST" \
    "sudo transactional-update run /bin/sh -c 'if [ -f /boot/vc/extraconfig.txt.orig ]; then cat /boot/vc/extraconfig.txt.orig > /boot/vc/extraconfig.txt; else echo \"No /boot/vc/extraconfig.txt.orig to restore from\"; fi'"
  if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$DEST_USER@$DEST_HOST" 'test -f /boot/efi/extraconfig.txt.orig' >/dev/null 2>&1; then
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$DEST_USER@$DEST_HOST" \
      "sudo transactional-update run /bin/sh -c 'cat /boot/efi/extraconfig.txt.orig > /boot/efi/extraconfig.txt'"
  fi
else
  echo "Unknown action: $ACTION"; exit 1
fi

rm -f "$TMPFILE"
echo "Done."
