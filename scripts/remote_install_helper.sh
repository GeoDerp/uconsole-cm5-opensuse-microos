#!/bin/sh
set -euo pipefail
# Usage: remote_install_helper.sh <source-on-remote> <target-on-remote>
if [ $# -ne 2 ]; then
  echo "Usage: $0 <source> <target>" >&2
  exit 2
fi
SRC="$1"
TARGET="$2"

echo "Inside helper: copying $SRC to $TARGET inside transactional snapshot"
TMP_SCRIPT="/tmp/_copy_into_snapshot.sh"
cat > "$TMP_SCRIPT" <<SH
cp -a "$SRC" "$TARGET"
sync
SH

sudo transactional-update shell < "$TMP_SCRIPT"

echo "Helper done: copied $SRC -> $TARGET (in new snapshot)."

exit 0
