#!/bin/bash
set -euo pipefail

echo "--- uConsole Driver Recovery ---"
echo "This script will attempt to install the uConsole drivers from a USB drive."
echo "Please insert a USB drive with the 'uconsole-drivers.tar.gz' file in the root directory."
read -p "Press Enter to continue..."

# Find the USB drive
USB_DRIVE=\$(lsblk -o NAME,MOUNTPOINT | grep -E " /run/media/| /media/" | awk '{print \$1}')
if [ -z "\$USB_DRIVE" ]; then
  echo "Could not find a mounted USB drive. Please make sure it is mounted and try again."
  exit 1
fi

MOUNT_POINT=\$(lsblk -o NAME,MOUNTPOINT | grep "\$USB_DRIVE" | awk '{print \$2}')
DRIVER_TARBALL="\$MOUNT_POINT/uconsole-drivers.tar.gz"

if [ ! -f "\$DRIVER_TARBALL" ]; then
  echo "Could not find 'uconsole-drivers.tar.gz' on the USB drive."
  exit 1
fi

echo "--- Found driver tarball at \$DRIVER_TARBALL ---"
echo "--- Preparing to install drivers in a new snapshot ---"

# Create a temporary script to be run by transactional-update
cat > /tmp/tu-install.sh << 'EOF'
#!/bin/bash
set -euo pipefail
echo "--- Building and installing drivers ---"
mkdir -p /tmp/uconsole-drivers-install
tar -xzf __DRIVER_TARBALL__ -C /tmp/uconsole-drivers-install
cd /tmp/uconsole-drivers-install/extracted-drivers
KVER=\$(uname -r)
if [ ! -d /lib/modules/\$KVER/build ]; then
  echo "Kernel build headers not found. Run 'sudo transactional-update pkg install kernel-default-devel' first." >&2
  exit 1
fi
for d in *; do
  if [ -d "\$d" ] && [ -f "\$d/Makefile" ]; then
    echo "--- Building \$d ---"
    (cd "\$d" && make -C /lib/modules/\$KVER/build M=\$(pwd) modules)
    if ls "\$d"/*.ko >/dev/null 2>&1; then
      echo "--- Installing \`ls \$d/*.ko\` ---"
      mkdir -p /lib/modules/\$KVER/extra
      cp -v "\$d"/*.ko /lib/modules/\$KVER/extra
    fi
  fi
done
depmod -a
echo "--- Driver installation complete.---"
EOF

sed -i "s|__DRIVER_TARBALL__|\$DRIVER_TARBALL|g" /tmp/tu-install.sh
chmod +x /tmp/tu-install.sh

echo "--- Running transactional-update ---"
sudo transactional-update run bash /tmp/tu-install.sh

echo "--- Rebooting device ---"
sudo reboot

echo "--- Done ---"
