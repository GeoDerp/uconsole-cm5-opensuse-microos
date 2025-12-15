#!/usr/bin/env bash
set -euo pipefail

usage(){
  cat <<EOF
Usage: $0 <device_ip> <ssh_user> <ssh_key> [--snapshot <snap_num>] [--no-reboot] [--no-deploy] [--no-drivers]

Interactive helper that:
  1) Lists snapshots on remote and optionally rolls back to a chosen snapshot
  2) Reboots the remote and waits for SSH
  3) Deploys device tree/overlays/config and (optionally) drivers

Example:
  ./scripts/revert_and_deploy.sh 192.168.1.37 geo ~/.ssh/pi_temp --snapshot 5

EOF
}

if [ "$#" -lt 3 ]; then
  usage; exit 1
fi

DEST_HOST="$1"
DEST_USER="$2"
SSH_KEY="$3"
shift 3

SNAPSHOT=""
NO_REBOOT=false
NO_DEPLOY=false
NO_DRIVERS=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    --snapshot) SNAPSHOT="$2"; shift 2 ;;
    --no-reboot) NO_REBOOT=true; shift ;;
    --no-deploy) NO_DEPLOY=true; shift ;;
    --no-drivers) NO_DRIVERS=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1"; usage; exit 1 ;;
  esac
done

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -i $SSH_KEY"

echo "Connecting to $DEST_USER@$DEST_HOST to list snapshots..."
ssh $SSH_OPTS "$DEST_USER@$DEST_HOST" 'sudo snapper list' || true

if [ -z "$SNAPSHOT" ]; then
  read -p "Enter snapshot number to rollback to (or blank to cancel): " SNAPSHOT
fi
if [ -z "$SNAPSHOT" ]; then
  echo "No snapshot chosen; aborting."; exit 1
fi

echo "About to run: sudo snapper rollback $SNAPSHOT on $DEST_HOST"
read -p "Proceed? [y/N] " yn
if [[ ! "$yn" =~ ^[Yy]$ ]]; then
  echo "Aborted by user."; exit 1
fi

echo "Running rollback on remote..."
ssh $SSH_OPTS "$DEST_USER@$DEST_HOST" "sudo snapper rollback $SNAPSHOT"

if [ "$NO_REBOOT" = false ]; then
  echo "Rebooting device to activate rollback..."
  ssh $SSH_OPTS "$DEST_USER@$DEST_HOST" 'sudo systemctl reboot' || true

  # Wait for SSH to come back up
  echo -n "Waiting for device to come back online"
  for i in {1..60}; do
    sleep 2
    if ssh $SSH_OPTS -o ConnectTimeout=5 "$DEST_USER@$DEST_HOST" 'echo ok' >/dev/null 2>&1; then
      echo "\nDevice is online."; break
    else
      echo -n "."
    fi
    if [ $i -eq 60 ]; then
      echo "\nTimed out waiting for device. You may need to check it manually."; exit 1
    fi
  done
else
  echo "Skipping reboot as requested (--no-reboot).";
fi

if [ "$NO_DEPLOY" = true ]; then
  echo "Skipping configuration deployment (--no-deploy)."; exit 0
fi

echo "Deploying DTB, overlays and config via scripts/deploy_to_device.sh and scripts/deploy_uconsole_config.sh"
./scripts/deploy_to_device.sh "$DEST_HOST" "$DEST_USER" "$SSH_KEY" --no-reboot || true
./scripts/deploy_uconsole_config.sh "$DEST_USER@$DEST_HOST" "$SSH_KEY" || true

if [ "$NO_DRIVERS" = false ]; then
  echo "Deploying and building drivers on target (this may create a new snapshot)."
  ./scripts/deploy_and_build_drivers.sh "$DEST_HOST" "$DEST_USER" "$SSH_KEY" --install-deps --no-reboot || true
  echo "Driver deployment finished. Reminder: reboot the target to activate kernel modules if you didn't already." 
else
  echo "Skipping drivers as requested (--no-drivers)."
fi

echo "All steps complete. If you haven't rebooted since driver install, please reboot the device to activate the new kernel snapshot and modules."

exit 0
