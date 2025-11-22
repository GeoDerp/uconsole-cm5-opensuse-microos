#!/bin/bash
# deploy_uconsole_files.sh - Deploy uConsole CM5 files to device
#
# This script deploys the device tree, overlays, and drivers to the uConsole.
# Run this from the repository root on the host machine.
#
# Usage: ./scripts/deploy_uconsole_files.sh <user@host> [ssh_key]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Require target
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <user@host> [ssh_key]"
    echo "Example: $0 myuser@192.168.1.100 ~/.ssh/id_rsa"
    exit 1
fi

TARGET="$1"
SSH_KEY="${2:-$HOME/.ssh/id_rsa}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

SSH_OPTS="-o StrictHostKeyChecking=accept-new"
if [[ -f "$SSH_KEY" ]]; then
    SSH_OPTS="$SSH_OPTS -i $SSH_KEY"
fi

ssh_cmd() {
    ssh $SSH_OPTS "$TARGET" "$@"
}

scp_cmd() {
    scp $SSH_OPTS "$@"
}

# Check connectivity
log_info "Checking connectivity to $TARGET..."
if ! ssh_cmd 'echo "Connected"' &>/dev/null; then
    log_error "Cannot connect to $TARGET"
    exit 1
fi

# Get remote user home
REMOTE_HOME=$(ssh_cmd 'echo $HOME')
REMOTE_STAGING="$REMOTE_HOME/uconsole-staging"

log_info "Creating staging directory on remote..."
ssh_cmd "mkdir -p $REMOTE_STAGING/{overlays,drivers}"

# Deploy device tree
if [[ -f "$REPO_ROOT/merged-clockworkpi.dtb" ]]; then
    log_info "Deploying device tree..."
    scp_cmd "$REPO_ROOT/merged-clockworkpi.dtb" "$TARGET:$REMOTE_STAGING/"
fi

# Deploy overlays
if [[ -d "$REPO_ROOT/overlays" ]]; then
    log_info "Deploying overlays..."
    scp_cmd "$REPO_ROOT/overlays/"*.dtbo "$TARGET:$REMOTE_STAGING/overlays/" 2>/dev/null || true
fi

# Deploy drivers
for driver in panel-cwu50 ocp8178_bl axp20x_battery axp20x_ac_power; do
    driver_dir="$REPO_ROOT/extracted-drivers/$driver"
    if [[ -d "$driver_dir" ]]; then
        log_info "Deploying $driver driver..."
        scp_cmd -r "$driver_dir" "$TARGET:$REMOTE_STAGING/drivers/"
    fi
done

# Deploy verification script
if [[ -f "$SCRIPT_DIR/verify_uconsole_hardware.sh" ]]; then
    log_info "Deploying verification script..."
    scp_cmd "$SCRIPT_DIR/verify_uconsole_hardware.sh" "$TARGET:$REMOTE_STAGING/"
    ssh_cmd "chmod +x $REMOTE_STAGING/verify_uconsole_hardware.sh"
fi

log_info "Files deployed to $TARGET:$REMOTE_STAGING/"
echo ""
log_info "Next steps on the device:"
echo "  1. Copy device tree to boot partition:"
echo "     sudo cp $REMOTE_STAGING/merged-clockworkpi.dtb /boot/efi/"
echo ""
echo "  2. Copy overlays:"
echo "     sudo cp $REMOTE_STAGING/overlays/*.dtbo /boot/efi/overlays/"
echo ""
echo "  3. Build and install drivers:"
echo "     cd $REMOTE_STAGING/drivers/panel-cwu50 && make && sudo make install"
echo "     cd $REMOTE_STAGING/drivers/ocp8178_bl && make && sudo make install"
echo ""
echo "  4. Verify hardware:"
echo "     $REMOTE_STAGING/verify_uconsole_hardware.sh"
echo ""
echo "  5. Reboot to apply changes:"
echo "     sudo reboot"
