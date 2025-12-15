#!/usr/bin/env bash
set -euo pipefail

usage(){
  cat <<EOF
Usage: $0 <device_ip> <ssh_user> <ssh_key> [--install-deps] [--no-reboot] [--tarball <path>]

Build and install drivers inside a transactional-update snapshot on the target.
This uploads the driver sources, runs a `transactional-update run` that builds the
modules against the target's kernel headers and installs them into
`/lib/modules/$(uname -r)/extra` inside the new snapshot, and runs `depmod -a`.

Example:
  ./scripts/deploy_and_build_drivers_snapshot.sh 192.168.1.37 geo ~/.ssh/pi_temp --install-deps

EOF
}

if [ "$#" -lt 3 ]; then
  usage; exit 1
fi

DEST_HOST="$1"
DEST_USER="$2"
SSH_KEY="$3"
shift 3

INSTALL_DEPS=false
NO_REBOOT=false
TARBALL=""
for arg in "$@"; do
  case "$arg" in
    --install-deps) INSTALL_DEPS=true ;;
    --no-reboot) NO_REBOOT=true ;;
    --tarball) TARBALL="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $arg"; usage; exit 1 ;;
  esac
done

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -i $SSH_KEY"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Create tarball of extracted-drivers if not provided
if [ -z "$TARBALL" ]; then
  TMP_TAR="/tmp/uconsole-drivers-$(date +%s).tar.gz"
  echo "Creating driver tarball $TMP_TAR"
  tar -czf "$TMP_TAR" -C "$REPO_ROOT" extracted-drivers
  TARBALL="$TMP_TAR"
fi

echo "Uploading driver tarball to target $DEST_HOST:/home/$DEST_USER/uconsole-drivers.tar.gz"
scp $SSH_OPTS "$TARBALL" "$DEST_USER@$DEST_HOST:/home/$DEST_USER/uconsole-drivers.tar.gz"

if [ "$INSTALL_DEPS" = true ]; then
  echo "Installing kernel build packages on target via transactional-update..."
  ssh $SSH_OPTS "$DEST_USER@$DEST_HOST" "sudo transactional-update pkg install -y kernel-default-devel make gcc" || true
fi

echo "Running build/install inside transactional-update on target"
ssh $SSH_OPTS "$DEST_USER@$DEST_HOST" "sudo transactional-update run /bin/sh -c '
  set -euo pipefail
  TMPDIR=/tmp/uconsole-drivers-install
  rm -rf \"$TMPDIR\" && mkdir -p \"$TMPDIR\"
  tar -xzf /home/$DEST_USER/uconsole-drivers.tar.gz -C \"$TMPDIR\"
  cd \"$TMPDIR/extracted-drivers\"
  KVER=\$(uname -r)
  if [ ! -d /lib/modules/\$KVER/build ]; then
    echo "Kernel build headers not found. Installing kernel-default-devel in snapshot..."
    zypper --non-interactive install -y kernel-default-devel || true
  fi
  for d in *; do
    if [ -d \"\$d\" ] && [ -f \"\$d/Makefile\" ]; then
      echo "Building driver: \$d"
      (cd \"\$d\" && make -C /lib/modules/\$KVER/build M=\$(pwd) modules) || true
      if ls \"\$d\"/*.ko >/dev/null 2>&1; then
        mkdir -p /lib/modules/\$KVER/extra
        cp -v \"\$d\"/*.ko /lib/modules/\$KVER/extra || true
        mkdir -p /var/lib/modules-overlay
        cp -v \"\$d\"/*.ko /var/lib/modules-overlay/ || true
      fi
    fi
  done
  depmod -a || true
  echo "Driver build/install in snapshot complete."
'"

echo "Driver installation finished on target."

if [ "$NO_REBOOT" = false ]; then
  echo "Rebooting target to activate snapshot..."
  ssh $SSH_OPTS "$DEST_USER@$DEST_HOST" 'sudo systemctl reboot' || true
else
  echo "Skipping reboot (--no-reboot supplied). Remember to reboot the device to activate the new snapshot."
fi

# Cleanup local tarball if we created one
if [[ "$TMP_TAR" != "" && -f "$TMP_TAR" ]]; then
  rm -f "$TMP_TAR" || true
fi

echo "Done."
