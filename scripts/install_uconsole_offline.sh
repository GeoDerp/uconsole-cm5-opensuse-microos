#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 <path_to_efi_mount> <path_to_root_mount>"
    echo "Example: $0 /run/media/$USER/EFI /run/media/$USER/ROOT"
    exit 1
}

if [ "$#" -lt 2 ]; then
    usage
fi

EFI_DIR="$1"
ROOT_DIR="$2"

if [ ! -d "$EFI_DIR/overlays" ] || [ ! -d "$ROOT_DIR/usr" ]; then
    echo "Error: Invalid EFI or ROOT paths provided."
    echo "Make sure the partitions are mounted correctly."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# Ensure driver sources have been fetched
if [ ! -d "$REPO_DIR/extracted-drivers" ] || [ -z "$(ls -A "$REPO_DIR/extracted-drivers" 2>/dev/null)" ]; then
    echo "Driver sources not found. Fetching from upstream..."
    "$SCRIPT_DIR/fetch-drivers.sh"
fi

echo "=== Building Device Tree Overlays ==="
"$SCRIPT_DIR/build_overlay.sh" "$REPO_DIR/overlays/clockworkpi-uconsole-cm5-stable.dts" "$REPO_DIR/overlays/clockworkpi-uconsole-cm5-stable.dtbo"
"$SCRIPT_DIR/build_overlay.sh" "$REPO_DIR/overlays/uconsole-audio.dts" "$REPO_DIR/overlays/uconsole-audio.dtbo"
"$SCRIPT_DIR/build_overlay.sh" "$REPO_DIR/overlays/uconsole-sd-alt.dts" "$REPO_DIR/overlays/uconsole-sd-alt.dtbo"

echo "=== Deploying to EFI Partition ==="
sudo cp -v "$REPO_DIR/overlays/clockworkpi-uconsole-cm5-stable.dtbo" "$EFI_DIR/overlays/"
sudo cp -v "$REPO_DIR/overlays/uconsole-audio.dtbo" "$EFI_DIR/overlays/"
sudo cp -v "$REPO_DIR/overlays/uconsole-sd-alt.dtbo" "$EFI_DIR/overlays/"
sudo cp -v "$REPO_DIR/overlay/boot/efi/extraconfig.txt" "$EFI_DIR/"

echo "=== Deploying Base Configs to ROOT Partition ==="
# Scripts and Services
sudo mkdir -p "$ROOT_DIR/usr/local/sbin" "$ROOT_DIR/etc/systemd/system"
sudo cp -v "$REPO_DIR/overlay/usr/local/sbin/"* "$ROOT_DIR/usr/local/sbin/"
sudo chmod +x "$ROOT_DIR/usr/local/sbin/"*.sh
sudo cp -rv "$REPO_DIR/overlay/etc/systemd/system/"* "$ROOT_DIR/etc/systemd/system/"

# Modprobe and NetworkManager
sudo mkdir -p "$ROOT_DIR/etc/modprobe.d" "$ROOT_DIR/etc/NetworkManager/conf.d"
sudo cp -v "$REPO_DIR/overlay/etc/modprobe.d/"* "$ROOT_DIR/etc/modprobe.d/"
sudo cp -v "$REPO_DIR/overlay/etc/NetworkManager/conf.d/"* "$ROOT_DIR/etc/NetworkManager/conf.d/"

echo "=== Setting up QEMU Chroot for Driver Build ==="
if ! command -v qemu-aarch64-static >/dev/null 2>&1; then
    echo "Error: qemu-aarch64-static is required to cross-compile drivers."
    echo "Please install it (e.g. sudo zypper in qemu-linux-user or sudo apt install qemu-user-static)"
    exit 1
fi

sudo cp $(which qemu-aarch64-static) "$ROOT_DIR/usr/bin/"
sudo cp -r "$REPO_DIR/extracted-drivers" "$ROOT_DIR/tmp/"

# Create the compilation script to run inside the chroot
sudo bash -c "cat << 'EOF' > $ROOT_DIR/tmp/build.sh
#!/bin/bash
set -euo pipefail
# Find the kernel version from the headers
KVER=\$(ls -1 /usr/src | grep linux- | grep -v obj | head -n 1 | sed 's/linux-//')
if [ -z \"\$KVER\" ]; then
    echo \"Could not detect kernel headers in /usr/src/\"
    exit 1
fi
echo \"Building modules for kernel: \$KVER\"
export KVER
mkdir -p /tmp/built-modules
for d in /tmp/extracted-drivers/*; do
    if [ -d \"\$d\" ] && [ -f \"\$d/Makefile\" ]; then
        echo \"Building \$d\"
        cd \"\$d\"
        make -C /lib/modules/\$KVER/build M=\$(pwd) modules
        cp *.ko /tmp/built-modules/ || true
    fi
done
EOF"

sudo chmod +x "$ROOT_DIR/tmp/build.sh"

echo "=== Compiling Drivers for ARM64 (Takes 1-2 minutes) ==="
sudo chroot "$ROOT_DIR" /bin/bash /tmp/build.sh

echo "=== Installing Drivers ==="
# Since this script runs on the host, we might need to mount the @/var subvolume to make changes persistent on MicroOS.
# If /var is empty, we create /var/lib/modules-overlay and copy them.
sudo mkdir -p "$ROOT_DIR/var/lib/modules-overlay"
sudo cp -v "$ROOT_DIR/tmp/built-modules/"*.ko "$ROOT_DIR/var/lib/modules-overlay/"

echo "=== Configuring GRUB ==="
# Add module_blacklist=vc4 fbcon=rotate:1 to GRUB if missing
if sudo grep -q "GRUB_CMDLINE_LINUX=" "$ROOT_DIR/etc/default/grub"; then
    sudo sed -i 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="module_blacklist=vc4 fbcon=rotate:1 /' "$ROOT_DIR/etc/default/grub"
fi
sudo sed -i 's/ quiet / /g' "$ROOT_DIR/etc/default/grub" || true

echo "=== Cleaning Up ==="
sudo rm -rf "$ROOT_DIR/tmp/extracted-drivers" "$ROOT_DIR/tmp/build.sh" "$ROOT_DIR/tmp/built-modules"

echo ""
echo "=========================================================="
echo "✅ Installation Complete!"
echo "Please safely eject the partitions and plug the CM5"
echo "back into the uConsole hardware. When you boot,"
echo "the screen will display the scrolling Linux TTY."
echo "=========================================================="
