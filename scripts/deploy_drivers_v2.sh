#!/usr/bin/env bash
set -euo pipefail
set -x

rm -f self_extracting_build.sh

usage(){
  cat <<'__USAGE_EOF__'
Usage: $0 <device_ip> <ssh_user> <ssh_key> [--install-deps] [--no-reboot]

Deploy the 'extracted-drivers' folder to DEST target, attempt to build modules on the target against kernel headers, and install the new modules into the active modules path.
This script creates a self-extracting script to work around the limitations of transactional-update.

Options:
  --install-deps  : Attempt to install kernel-devel and build toolchain in transactional-update.
  --no-reboot     : Do not reboot after module install (default: reboot to load modules)

Example:
  ./scripts/deploy_drivers_v2.sh 192.168.1.100 myuser ~/.ssh/id_rsa --install-deps

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
    --no-reboot) NO_REBOOT=false ;; 
    *) echo "Unknown arg: $arg"; exit 1 ;; 
  esac
done

TMPDIR=/var/home/geo/.gemini/tmp/53194aa38886f1b160f0cdc26bf9c346a577ae92636926d1d7538bf6d14f08bd 
mkdir -p "$TMPDIR"
cp -r extracted-drivers "$TMPDIR/"
tar -czf "/var/home/geo/.gemini/tmp/53194aa38886f1b160f0cdc26bf9c346a577ae92636926d1d7538bf6d14f08bd/uconsole-drivers.tar.gz" -C "$TMPDIR" extracted-drivers



base64 "$TMPDIR/uconsole-drivers.tar.gz" >> "self_extracting_build.sh"



if [ "$INSTALL_DEPS" = true ]; then
  echo "Installing kernel build packages on target via transactional-update..."
  ssh -i "$SSH_KEY" "$DEST_USER@$DEST_HOST" "sudo transactional-update pkg install -y kernel-default-devel make gcc" || true
fi

echo "Building kernel modules on target (if kernel headers present) by creating and executing a temporary script within transactional-update"

# Capture the full output from the transactional-update run
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$DEST_USER@$DEST_HOST" \
  "sudo transactional-update run bash -c 'cat > /var/tmp/script_in_transaction.sh && bash /var/tmp/script_in_transaction.sh; rm /var/tmp/script_in_transaction.sh'" < "self_extracting_build.sh" > "$TMPDIR/remote_output.log"
FULL_OUTPUT=$(cat "$TMPDIR/remote_output.log")

echo "DEBUG: FULL_OUTPUT is: $FULL_OUTPUT" # Debug echo

# Extract the base64 encoded tarball from the output
# Extract the base64 encoded tarball from the output
# Filter out transactional-update's own messages to isolate only the base64 block
FILTERED_LOG="$TMPDIR/filtered_output.log"

# Use grep to get the last occurrence of the base64 block
# This command ensures that only the lines within the last pair of markers are considered.
echo "$FULL_OUTPUT" | tac | \
  awk '/__BASE64_TARBALL_END__/{flag=1; next} /__BASE64_TARBALL_BEGIN__/{flag=0} flag{print}' | \
  tac > "$FILTERED_LOG"

BASE64_TARBALL=$(awk '
  /^\s*__BASE64_TARBALL_BEGIN__\s*$/{
    flag=1; next
  }
  /^\s*__BASE64_TARBALL_END__\s*$/{
    flag=0
  }
  flag {
    print
  }
' "$FILTERED_LOG")

echo "DEBUG: BASE64_TARBALL is: $BASE64_TARBALL" # Debug echo

if [ -z "$BASE64_TARBALL" ]; then
  echo "Error: No compiled modules tarball found in transactional-update output." >&2
  echo "$FULL_OUTPUT" # Print full output for debugging
  exit 1
fi

# Decode the base64 tarball locally
echo "$BASE64_TARBALL" | tr -d '\n' | base64 -d > "$TMPDIR/compiled_modules.tar.gz"
ls -l "$TMPDIR/compiled_modules.tar.gz" # Debug ls

# Extract the modules locally
mkdir -p "$TMPDIR/compiled_modules"
tar -xzf "$TMPDIR/compiled_modules.tar.gz" -C "$TMPDIR/compiled_modules"
ls -l "$TMPDIR/compiled_modules/" # Debug ls

echo "Deploying compiled modules to /var/lib/modules-overlay/ on remote"
# Create the target directory on the remote if it doesn't exist
ssh -i "$SSH_KEY" "$DEST_USER@$DEST_HOST" "sudo mkdir -p /var/lib/modules-overlay"

# SCP each compiled module to the remote /var/lib/modules-overlay/
for ko_file in "$TMPDIR"/compiled_modules/*.ko; do
  echo "DEBUG: ko_file is: $ko_file" # Debug echo
  echo "Copying $(basename "$ko_file") to remote"
  scp -i "$SSH_KEY" "$ko_file" "$DEST_USER@$DEST_HOST:/var/lib/modules-overlay/"
done

# Run depmod on the remote to update module dependencies
echo "Running depmod -a on remote"
ssh -i "$SSH_KEY" "$DEST_USER@$DEST_HOST" "sudo depmod -a"

echo "Attempting to load uconsole-related modules: ocp8178_bl, panel-cwd686, panel-cwu50"
for mod in ocp8178_bl panel-cwd686 panel-cwu50; do # Only load modules that were actually built
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$DEST_USER@$DEST_HOST" "sudo modprobe $mod || echo 'modprobe $mod failed'"
done

if [ "$NO_REBOOT" = false ]; then
  echo "Rebooting target to finalize module install"
  ssh -i "$SSH_KEY" "$DEST_USER@$DEST_HOST" 'sudo systemctl reboot'
fi

set +x # Debug set +x

echo "Done."
rm -rf "$TMPDIR"
exit 0
