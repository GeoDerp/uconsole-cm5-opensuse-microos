#!/usr/bin/env bash
# Self-extracting driver build script for uConsole CM5.
#
# This file is a TEMPLATE. The base64 tarball payload at the end must be
# generated after fetching the GPL driver sources:
#
#   ./scripts/fetch-drivers.sh
#   tar -czf /tmp/drivers.tar.gz extracted-drivers/
#   base64 -w 76 /tmp/drivers.tar.gz >> self_extracting_build.sh
#
# The payload is then extracted and compiled on the target device.
set -euo pipefail

PAYLOAD_LINE=$(awk '/^__EMBEDDED_TARBALL_PAYLOAD_BEGINS__/ { print NR + 1; exit 0; }' "$0")

# Create a temporary directory in /var/tmp, since /tmp might not be available
BUILD_DIR=$(mktemp -d -p /var/tmp)
tail -n +$PAYLOAD_LINE "$0" | base64 -d | tar -xzf - -C $BUILD_DIR

cd $BUILD_DIR/extracted-drivers

KVER=$(uname -r)
if [ ! -d /lib/modules/$KVER/build ]; then
  echo "Kernel build symlink not present at /lib/modules/$KVER/build. Building will likely fail unless kernel-devel is installed." >&2
fi

# Only build drm-rp1-dsi and capture its tarball
d="drm-rp1-dsi"
if [ -d "$d" ]; then
  if [ -f "$d/Makefile" ]; then
    echo "Building driver in "$d"" >&2 # Redirect to stderr
    pushd "$d" >/dev/null
    make -C /lib/modules/$KVER/build M=$(pwd) modules 1>/dev/null 2>&1 # Redirect make output
    if ls *.ko >/dev/null 2>&1; then
      TARBALL_NAME="compiled_modules_from_snapshot.tar.gz"
      tar -czf "$TARBALL_NAME" *.ko
      echo "__BASE64_TARBALL_BEGIN__"
      base64 -w 0 "$TARBALL_NAME"
      echo "__BASE64_TARBALL_END__"
      rm "$TARBALL_NAME"
    fi
    popd >/dev/null
  fi
fi

echo "Running depmod" >&2 # Redirect to stderr
depmod -a

rm -rf $BUILD_DIR

exit 0

__EMBEDDED_TARBALL_PAYLOAD_BEGINS__
