#!/bin/bash
# Deploy uConsole CM5 configuration files to a target device
# Usage: ./scripts/deploy_uconsole_config.sh <user@host> <ssh_key>
#
# This script deploys all configuration files needed for a working uConsole CM5
# on openSUSE MicroOS.

set -e

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <user@host> <ssh_key>"
    echo "Example: $0 myuser@192.168.1.100 ~/.ssh/id_rsa"
    exit 1
fi

TARGET="$1"
SSH_KEY="$2"

SSH_CMD="ssh -i $SSH_KEY"
SCP_CMD="scp -i $SSH_KEY"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Deploying uConsole CM5 configuration to $TARGET ==="

# Install required packages
echo "Installing required packages..."
$SSH_CMD $TARGET "sudo transactional-update --non-interactive pkg install i2c-tools" || echo "Note: Package install may require reboot to take effect"

# Deploy overlay files
echo "Deploying configuration files..."

# Create directories
$SSH_CMD $TARGET "sudo mkdir -p /usr/local/bin /var/lib/modules-overlay"

# Deploy modprobe config
$SCP_CMD "$REPO_DIR/overlay/etc/modprobe.d/uconsole.conf" $TARGET:/tmp/
$SSH_CMD $TARGET "sudo cp /tmp/uconsole.conf /etc/modprobe.d/"

# Deploy modules-load config
$SCP_CMD "$REPO_DIR/overlay/etc/modules-load.d/uconsole.conf" $TARGET:/tmp/uconsole-modules.conf
$SSH_CMD $TARGET "sudo cp /tmp/uconsole-modules.conf /etc/modules-load.d/uconsole.conf"

# Deploy systemd service
$SCP_CMD "$REPO_DIR/overlay/etc/systemd/system/uconsole-backlight.service" $TARGET:/tmp/
$SSH_CMD $TARGET "sudo cp /tmp/uconsole-backlight.service /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable uconsole-backlight.service"

# Deploy init script
$SCP_CMD "$REPO_DIR/overlay/usr/local/bin/uconsole-backlight-init.sh" $TARGET:/tmp/
$SSH_CMD $TARGET "sudo cp /tmp/uconsole-backlight-init.sh /usr/local/bin/ && sudo chmod +x /usr/local/bin/uconsole-backlight-init.sh && sudo restorecon /usr/local/bin/uconsole-backlight-init.sh"

# Deploy AXP221 power management scripts (for proper shutdown)
echo "Deploying AXP221 power management..."
$SCP_CMD "$REPO_DIR/overlay/usr/local/sbin/axp221-poweroff.sh" $TARGET:/tmp/
$SCP_CMD "$REPO_DIR/overlay/usr/local/sbin/axp221-configure-pek.sh" $TARGET:/tmp/
$SCP_CMD "$REPO_DIR/overlay/etc/systemd/system/axp221-poweroff.service" $TARGET:/tmp/
$SCP_CMD "$REPO_DIR/overlay/etc/systemd/system/axp221-configure-pek.service" $TARGET:/tmp/
$SSH_CMD $TARGET "sudo mkdir -p /usr/local/sbin && \
    sudo cp /tmp/axp221-poweroff.sh /tmp/axp221-configure-pek.sh /usr/local/sbin/ && \
    sudo chmod +x /usr/local/sbin/axp221-*.sh && \
    sudo restorecon /usr/local/sbin/axp221-*.sh && \
    sudo cp /tmp/axp221-poweroff.service /tmp/axp221-configure-pek.service /etc/systemd/system/ && \
    sudo systemctl daemon-reload && \
    sudo systemctl enable axp221-poweroff.service axp221-configure-pek.service"

# Deploy Battery Safety Monitor
echo "Deploying Battery Safety Monitor..."
$SCP_CMD "$REPO_DIR/overlay/usr/local/sbin/uconsole-power-monitor.sh" $TARGET:/tmp/
$SCP_CMD "$REPO_DIR/overlay/etc/systemd/system/uconsole-power-monitor.service" $TARGET:/tmp/
$SSH_CMD $TARGET "sudo mkdir -p /usr/local/sbin && \
    sudo cp /tmp/uconsole-power-monitor.sh /usr/local/sbin/ && \
    sudo chmod +x /usr/local/sbin/uconsole-power-monitor.sh && \
    sudo restorecon /usr/local/sbin/uconsole-power-monitor.sh && \
    sudo cp /tmp/uconsole-power-monitor.service /etc/systemd/system/ && \
    sudo systemctl daemon-reload && \
    sudo systemctl enable uconsole-power-monitor.service"

# Deploy btrfsmaintenance timer overrides (prevent display underflow at boot)
echo "Deploying btrfs timer overrides..."
for timer in btrfs-scrub btrfs-balance btrfs-trim btrfs-defrag; do
    if [ -f "$REPO_DIR/overlay/etc/systemd/system/${timer}.timer.d/uconsole-delay-boot.conf" ]; then
        $SCP_CMD "$REPO_DIR/overlay/etc/systemd/system/${timer}.timer.d/uconsole-delay-boot.conf" $TARGET:/tmp/
        $SSH_CMD $TARGET "sudo mkdir -p /etc/systemd/system/${timer}.timer.d && \
            sudo cp /tmp/uconsole-delay-boot.conf /etc/systemd/system/${timer}.timer.d/"
    fi
done
$SSH_CMD $TARGET "sudo systemctl daemon-reload"

# Deploy logind power button configuration
echo "Deploying power button configuration..."
if [ -f "$REPO_DIR/overlay/etc/systemd/logind.conf.d/uconsole-power.conf" ]; then
    $SCP_CMD "$REPO_DIR/overlay/etc/systemd/logind.conf.d/uconsole-power.conf" $TARGET:/tmp/
    $SSH_CMD $TARGET "sudo mkdir -p /etc/systemd/logind.conf.d && \
        sudo cp /tmp/uconsole-power.conf /etc/systemd/logind.conf.d/ && \
        sudo systemctl restart systemd-logind"
fi

# Deploy extraconfig.txt to boot partition
echo "Deploying boot configuration..."
$SCP_CMD "$REPO_DIR/overlay/boot/efi/extraconfig.txt" $TARGET:/tmp/
$SSH_CMD $TARGET "sudo cp /tmp/extraconfig.txt /boot/efi/extraconfig.txt"

# Deploy device tree and overlays
echo "Deploying device tree and overlays..."
$SCP_CMD "$REPO_DIR/merged-clockworkpi.dtb" $TARGET:/tmp/
$SSH_CMD $TARGET "sudo cp /tmp/merged-clockworkpi.dtb /boot/efi/"

# Deploy overlay DTBOs if they exist
for dtbo in "$REPO_DIR"/overlays/*.dtbo; do
    if [ -f "$dtbo" ]; then
        name=$(basename "$dtbo")
        $SCP_CMD "$dtbo" $TARGET:/tmp/
        $SSH_CMD $TARGET "sudo cp /tmp/$name /boot/efi/overlays/"
    fi
done

echo "=== Deployment complete ==="
echo ""
echo "Next steps:"
echo "1. Build and deploy drivers: ./scripts/deploy_and_build_drivers.sh <host_ip> <user> <ssh_key>"
echo "2. Reboot the device: $SSH_CMD $TARGET 'sudo reboot'"
