#!/usr/bin/env bash
# deploy_to_device.sh - Deploy fixed DTB and overlays to CM5 uConsole running MicroOS
#
# This script deploys:
#   1. A fixed merged DTB (merged-clockworkpi.dtb) with RP1-compatible pinctrl settings
#   2. The rp1-i2c1-fix overlay for proper RP1 I2C1 pin configuration
#
# The merged DTB already contains all necessary device configurations for the
# uConsole CM5 (backlight, display panel, battery/PMIC). The rp1-i2c1-fix overlay
# ensures RP1 pinctrl uses the correct pin naming convention.

set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <device_ip> <ssh_user> <ssh_key> [--no-reboot] [--install-dtc]"
  echo "Example: $0 192.168.1.100 myuser ~/.ssh/id_rsa"
  exit 1
fi

DEST_HOST="$1"
DEST_USER="$2"
SSH_KEY="$3"
NO_REBOOT=false
INSTALL_DTC=false

for arg in "${@:4}"; do
  case "$arg" in
    --no-reboot) NO_REBOOT=true ;;
    --reboot) NO_REBOOT=false ;;
    --install-dtc) INSTALL_DTC=true ;;
    -h|--help) 
      echo "Usage: $0 <device_ip> <ssh_user> <ssh_key> [--reboot|--no-reboot] [--install-dtc]"
      exit 0 
      ;;
    *) echo "Unknown argument: $arg"; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$REPO_ROOT"

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"

echo "=== Deploying to CM5 uConsole at $DEST_HOST ==="

# Compile merged DTB (with fixed RP1 pinctrl)
echo "[1/5] Compiling merged device tree..."
dtc -I dts -O dtb -o /tmp/merged-clockworkpi-fixed.dtb merged-clockworkpi.dts 2>&1 | grep -v "^Warning" || true
echo "  - Merged DTB: $(sha256sum /tmp/merged-clockworkpi-fixed.dtb | cut -d' ' -f1)"

# Compile the RP1 I2C1 fix overlay
echo "[2/5] Compiling rp1-i2c1-fix overlay..."
./scripts/build_overlay.sh overlays/rp1-i2c1-fix.dts /tmp/rp1-i2c1-fix.dtbo 2>&1 | grep -v "^Warning" || true

# Copy files to target (to user's home, which is visible inside transactional-update)
echo "[3/5] Copying files to target device..."
scp $SSH_OPTS -i "$SSH_KEY" /tmp/merged-clockworkpi-fixed.dtb "$DEST_USER@$DEST_HOST:/home/$DEST_USER/"
scp $SSH_OPTS -i "$SSH_KEY" /tmp/rp1-i2c1-fix.dtbo "$DEST_USER@$DEST_HOST:/home/$DEST_USER/"

# Write files into /boot/efi (FAT partition, writable)
echo "[4/5] Installing files into /boot/efi..."
ssh $SSH_OPTS -i "$SSH_KEY" "$DEST_USER@$DEST_HOST" "sudo sh -c '
  set -e
  mkdir -p /boot/efi/overlays
  cp /home/$DEST_USER/merged-clockworkpi-fixed.dtb /boot/efi/merged-clockworkpi.dtb
  cp /home/$DEST_USER/rp1-i2c1-fix.dtbo /boot/efi/overlays/rp1-i2c1-fix.dtbo
  echo \"=== Files installed ===\"
  sha256sum /boot/efi/merged-clockworkpi.dtb
  sha256sum /boot/efi/overlays/rp1-i2c1-fix.dtbo
'"

# Update extraconfig.txt with minimal required settings
echo "[5/5] Updating extraconfig.txt..."
ssh $SSH_OPTS -i "$SSH_KEY" "$DEST_USER@$DEST_HOST" "sudo sh -c '
  set -e
  # Backup original extraconfig if not already backed up
  if [ ! -f /boot/efi/extraconfig.txt.orig ]; then
    cp /boot/efi/extraconfig.txt /boot/efi/extraconfig.txt.orig 2>/dev/null || true
  fi
  
  # Create clean extraconfig.txt with only necessary settings
  cat > /boot/efi/extraconfig.txt << EOF
# uConsole CM5 configuration
# Use the merged DTB with all hardware configuration
device_tree=merged-clockworkpi.dtb

# Enable RP1 I2C1 pin fix overlay for proper pinctrl
dtoverlay=rp1-i2c1-fix

# Optional: uncomment if using display via DSI
# dtoverlay=vc4-kms-v3d-pi5
EOF

  echo \"=== extraconfig.txt updated ===\"
  cat /boot/efi/extraconfig.txt
'"

# Install dtc if requested
if [ "$INSTALL_DTC" = true ]; then
  echo "[Optional] Installing dtc on target..."
  ssh $SSH_OPTS -i "$SSH_KEY" "$DEST_USER@$DEST_HOST" "sudo transactional-update pkg install -y dtc" || true
fi

# Reboot if requested
if [ "$NO_REBOOT" = false ]; then
  echo ""
  echo "=== Rebooting target device ==="
  ssh $SSH_OPTS -i "$SSH_KEY" "$DEST_USER@$DEST_HOST" 'sudo systemctl reboot' || true
  echo "Device is rebooting. Wait ~60 seconds before reconnecting."
else
  echo ""
  echo "=== Deployment complete (no reboot) ==="
  echo "Remember to reboot the device for changes to take effect."
fi
