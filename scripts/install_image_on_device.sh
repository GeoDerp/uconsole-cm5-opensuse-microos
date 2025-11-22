#!/usr/bin/env bash
set -euo pipefail

# Usage: scripts/install_image_on_device.sh <user@host> /path/to/Image.merged
# This will SCP the merged image to the remote user's home and run a transactional-update

if [ $# -ne 2 ]; then
  echo "Usage: $0 <user@host> /path/to/Image.merged"
  exit 2
fi

REMOTE="$1"
LOCAL_IMAGE="$2"

if [ ! -f "$LOCAL_IMAGE" ]; then
  echo "Local merged image not found: $LOCAL_IMAGE" >&2
  exit 3
fi

USERPART="$(echo "$REMOTE" | cut -d@ -f1)"
HOSTPART="$(echo "$REMOTE" | cut -d@ -f2-)"
REMOTE_PATH="~/Image.merged"

echo "Copying $LOCAL_IMAGE to ${USERPART}@${HOSTPART}:$REMOTE_PATH"
scp -o StrictHostKeyChecking=no "$LOCAL_IMAGE" "${USERPART}@${HOSTPART}:$REMOTE_PATH"

echo "Invoking remote transactional-update shell to install the Image from the uploaded file into the kernel path"
ssh -o StrictHostKeyChecking=no "${USERPART}@${HOSTPART}" \
  "sudo sh -c 'KVER=\$(uname -r); TARGET=/usr/lib/modules/\${KVER}/Image; echo remote target \${TARGET}; if [ -f \"\${TARGET}\" ]; then cp -a \"\${TARGET}\" \"\${TARGET}.orig\"; fi; transactional-update shell <<IN
cp -a /home/${USERPART}/Image.merged \"\${TARGET}\"
sync
IN
echo Installed merged Image into snapshot at \"\${TARGET}\"'

echo "Remote install attempted. If sudo prompted for password, the above SSH session will have asked for it."

exit 0
