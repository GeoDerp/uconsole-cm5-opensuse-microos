#!/bin/bash
# deploy_stabilized_config.sh - uConsole CM5 Stable Config Deployer
# Aligned with March 2026 Stability Review (docs/STABILITY-REVIEW.md)

set -euo pipefail

TARGET="${1:-geo@192.168.1.37}"
SSH_KEY="${2:-$HOME/.ssh/pi_temp}"

log() { echo -e "\033[0;32m[DEPLOY]\033[0m $1"; }

# 1. Prepare Overlays
log "Compiling Stable Overlay..."
./scripts/build_overlay.sh overlays/clockworkpi-uconsole-cm5-stable.dts overlays/clockworkpi-uconsole-cm5-stable.dtbo

# 2. Sync to Device
log "Syncing files to $TARGET..."
scp -i "$SSH_KEY" overlays/clockworkpi-uconsole-cm5-stable.dtbo "$TARGET:/tmp/"
scp -i "$SSH_KEY" overlay/usr/local/bin/uconsole-backlight-init.sh "$TARGET:/tmp/"
scp -i "$SSH_KEY" overlay/usr/local/sbin/axp221-poweroff.sh "$TARGET:/tmp/"
scp -i "$SSH_KEY" overlay/usr/local/sbin/axp221-configure-pek.sh "$TARGET:/tmp/"
scp -i "$SSH_KEY" overlay/usr/local/sbin/axp221-monitor.sh "$TARGET:/tmp/"
scp -i "$SSH_KEY" overlay/usr/local/sbin/uconsole-power-monitor.sh "$TARGET:/tmp/"
scp -i "$SSH_KEY" overlay/usr/local/sbin/uconsole-dsi-rebind.sh "$TARGET:/tmp/"
scp -i "$SSH_KEY" overlay/usr/local/bin/uconsole-battery.sh "$TARGET:/tmp/"
scp -i "$SSH_KEY" overlay/boot/efi/extraconfig.txt "$TARGET:/tmp/extraconfig.txt"

# 3. Sync Driver Sources for Dynamic Recompilation
# Sources are stored persistently so the init script can recompile them if the kernel updates
log "Syncing driver sources to persistent storage..."
ssh -i "$SSH_KEY" "$TARGET" "sudo mkdir -p /usr/local/src/uconsole-drivers && sudo chown \$USER:\$USER /usr/local/src/uconsole-drivers"
scp -i "$SSH_KEY" -r extracted-drivers/* "$TARGET:/usr/local/src/uconsole-drivers/"

# 4. Apply System Configuration
log "Applying hardware configuration on remote..."
ssh -i "$SSH_KEY" "$TARGET" bash << 'EOF'
    set -e
    
    # Install Overlay
    sudo cp /tmp/clockworkpi-uconsole-cm5-stable.dtbo /boot/efi/overlays/
    
    # Install Scripts
    sudo cp /tmp/uconsole-backlight-init.sh /usr/local/bin/
    sudo cp /tmp/axp221-poweroff.sh /usr/local/sbin/
    sudo cp /tmp/axp221-configure-pek.sh /usr/local/sbin/
    sudo cp /tmp/axp221-monitor.sh /usr/local/sbin/
    sudo cp /tmp/uconsole-power-monitor.sh /usr/local/sbin/
    sudo cp /tmp/uconsole-dsi-rebind.sh /usr/local/sbin/
    sudo cp /tmp/uconsole-battery.sh /usr/local/bin/
    sudo chmod +x /usr/local/bin/uconsole-backlight-init.sh /usr/local/bin/uconsole-battery.sh
    sudo chmod +x /usr/local/sbin/axp221-poweroff.sh /usr/local/sbin/axp221-configure-pek.sh
    sudo chmod +x /usr/local/sbin/axp221-monitor.sh /usr/local/sbin/uconsole-power-monitor.sh
    sudo chmod +x /usr/local/sbin/uconsole-dsi-rebind.sh
    sudo restorecon -v /usr/local/bin/*.sh /usr/local/sbin/*.sh 2>/dev/null || true
    
    # Update boot config
    sudo cp /tmp/extraconfig.txt /boot/efi/extraconfig.txt
    
    # Fix Boot Config (Main config.txt)
    # Ensure dtparam=spi=off is at the TOP (prevent GPIO1 collision)
    sudo sed -i '/dtparam=spi=off/d' /boot/efi/config.txt
    sudo sed -i '1i dtparam=spi=off' /boot/efi/config.txt
    
    # Remove old overlay references that conflict
    sudo sed -i '/clockworkpi-uconsole-cm5-ultimate/d' /boot/efi/config.txt
    sudo sed -i '/clockworkpi-uconsole-cm5-final/d' /boot/efi/config.txt
    sudo sed -i '/clockworkpi-uconsole-cm5-fix/d' /boot/efi/config.txt
    
    # Fix GRUB
    sudo sed -i 's/GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="deferred_probe_timeout=5 usbcore.autosuspend=-1 fbcon=rotate:1"/' /etc/default/grub
    sudo transactional-update run grub2-mkconfig -o /boot/grub2/grub.cfg
EOF

log "Deployment complete. Reboot required. If device hangs, do 60-second battery pull."
