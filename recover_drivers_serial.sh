#!/bin/bash
set -euo pipefail

echo "--- uConsole Driver Recovery ---"
echo "This script will attempt to install the uConsole drivers from a USB drive."
echo "Please insert a USB drive with the 'uconsole-drivers-build.tar.gz' file in the root directory."
read -p "Press Enter to continue..."

# Find the USB drive
USB_DRIVE=\$(lsblk -o NAME,MOUNTPOINT | grep -E " /run/media/| /media/" | awk '{print \$1}')
if [ -z "\$USB_DRIVE" ]; then
  echo "Could not find a mounted USB drive. Please make sure it is mounted and try again."
  exit 1
fi

MOUNT_POINT=\$(lsblk -o NAME,MOUNTPOINT | grep "\$USB_DRIVE" | awk '{print \$2}')
DRIVER_TARBALL="\$MOUNT_POINT/uconsole-drivers-build.tar.gz"

if [ ! -f "\$DRIVER_TARBALL" ]; then
  echo "Could not find 'uconsole-drivers-build.tar.gz' on the USB drive."
  exit 1
fi

echo "--- Found driver tarball at \$DRIVER_TARBALL ---"
echo "--- Preparing to install drivers in a new snapshot ---"

sudo transactional-update run tar -xzf \$DRIVER_TARBALL -C /
sudo transactional-update run /uconsole-drivers-build/install.sh
sudo transactional-update run rm -rf /uconsole-drivers-build
sudo reboot

echo "--- Done ---"
