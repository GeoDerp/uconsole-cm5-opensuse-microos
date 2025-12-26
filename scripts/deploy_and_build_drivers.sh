#!/usr/bin/env bash
set -euo pipefail

usage(){
  cat <<EOF
Usage: $0 <device_ip> <ssh_user> <ssh_key> [--install-deps] [--no-reboot]

Deploy the `extracted-drivers` folder to `DEST` target, attempt to build modules on the target against kernel headers, and install the new modules into the active modules path.
Options:
  --install-deps  : Attempt to install kernel-devel and build toolchain in transactional-update.
  --no-reboot     : Do not reboot after module install (default: reboot to load modules)

Example:
  ./scripts/deploy_and_build_drivers.sh 192.168.1.100 myuser ~/.ssh/id_rsa --install-deps

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
for arg in "$@"; do
  case "$arg" in
    --install-deps) INSTALL_DEPS=true ;;
    --no-reboot) NO_REBOOT=true ;;
    *) echo "Unknown arg: $arg"; exit 1 ;;
  esac
done

TMPDIR=/tmp/uconsole-drivers-$$
mkdir -p "$TMPDIR"
cp -r extracted-drivers "$TMPDIR/"

echo "Uploading extracted-drivers to target $DEST_HOST:/tmp/uconsole-drivers"
scp -i "$SSH_KEY" -r "$TMPDIR/extracted-drivers" "$DEST_USER@$DEST_HOST:/tmp/uconsole-drivers"

if [ "$INSTALL_DEPS" = true ]; then
  echo "Installing kernel build packages on target via transactional-update..."
  ssh -i "$SSH_KEY" "$DEST_USER@$DEST_HOST" "sudo transactional-update pkg install -y kernel-default-devel make gcc" || true
fi

echo "Building kernel modules on target (if kernel headers present)"
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$DEST_USER@$DEST_HOST" <<'REMOTE'
set -euo pipefail
set -x
cd /tmp/uconsole-drivers
KVER=$(uname -r)
if [ ! -d /lib/modules/$KVER/build ]; then
  echo "Kernel build symlink not present at /lib/modules/$KVER/build. Building will likely fail unless kernel-devel is installed." >&2
fi
for d in *; do
  if [ -d "$d" ]; then
    if [ -f "$d/Makefile" ]; then
      echo "Building driver in $d"
      pushd "$d" >/dev/null
      echo "PWD: $(pwd)"
      ls -l
      # prefer building with kernel build system: make -C /lib/modules/<kver>/build M=$(pwd) modules
      sudo make -C /lib/modules/$KVER/build M=$(pwd) modules
      # install modules if created
      if ls *.ko >/dev/null 2>&1; then
        # Try to install to standard path (will fail on Read-Only FS like MicroOS)
        sudo mkdir -p /lib/modules/$KVER/extra
        if sudo cp -v *.ko /lib/modules/$KVER/extra 2>/dev/null; then
             echo "Installed to /lib/modules/$KVER/extra"
        else
             echo "NOTE: Could not write to /lib/modules (Read-Only FS). This is expected on MicroOS."
        fi
        
        # Copy to /var/lib/modules-overlay for MicroOS persistence (used by uconsole-backlight-init.sh)
        sudo mkdir -p /var/lib/modules-overlay
        sudo cp -v *.ko /var/lib/modules-overlay/ || true
        # Fix SELinux context for the overlay modules
        sudo restorecon -v /var/lib/modules-overlay/*.ko || true
      fi
      popd >/dev/null
    fi
  fi
done
echo "Running depmod and loading modules where appropriate"
sudo depmod -a
REMOTE

echo "Attempting to load uconsole-related modules: uconsole_fixup, ocp8178_bl, panel-cwd686, panel-cwu50, axp20x_ac_power, axp20x_battery"
for mod in uconsole_fixup ocp8178_bl panel-cwd686 panel-cwu50 axp20x_ac_power axp20x_battery; do
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$DEST_USER@$DEST_HOST" "sudo modprobe $mod || echo 'modprobe $mod failed'"
done

if [ "$NO_REBOOT" = false ]; then
  echo "Skipping reboot for debug"
  # echo "Rebooting target to finalize module install"
  # ssh -i "$SSH_KEY" "$DEST_USER@$DEST_HOST" 'sudo systemctl reboot'
fi

echo "Done."
rm -rf "$TMPDIR"
exit 0
