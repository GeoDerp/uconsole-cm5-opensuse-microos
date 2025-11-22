#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 4 ]; then
  echo "Usage: $0 <device_ip> <ssh_user> <ssh_key> --preload overlay1 [overlay2 ...] --test overlayA overlayB ..."
  echo "Example: $0 192.168.1.100 myuser ~/.ssh/id_rsa --preload rp1-i2c1-fix clockworkpi-uconsole --test i2c1 i2c1-pi5"
  exit 1
fi

DEST_HOST="$1"
DEST_USER="$2"
SSH_KEY="$3"
shift 3

RUNTIME_ARGS=("$@")
echo "Running reintroduce overlay test with: ${RUNTIME_ARGS[*]}"
./scripts/reintroduce_overlay_test.sh "$DEST_HOST" "$DEST_USER" "$SSH_KEY" "${RUNTIME_ARGS[@]}"

exit $? 
