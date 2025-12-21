#!/usr/bin/env bash
set -euo pipefail

# deploy_overlays_to_device.sh
# Usage: ./deploy_overlays_to_device.sh <user@host> [--overlays-dir path] [--names name1,name2] [--reboot]
# Copies dtbo files to remote /boot/vc/overlays and ensures dtoverlay lines are present in /boot/vc/extraconfig.txt

if [[ $# -lt 1 || "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: $0 <user@host> [--overlays-dir path] [--names name1,name2] [--reboot]"
    echo "Example: $0 myuser@192.168.1.100"
    exit 1
fi

REMOTE="$1"
shift

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
OVERLAYS_DIR="$REPO_ROOT/overlays"
NAMES=""
REBOOT=0

while [ $# -gt 0 ]; do
  case "$1" in
    --overlays-dir) OVERLAYS_DIR="$2"; shift 2 ;;
    --names) NAMES="$2"; shift 2 ;;
    --reboot) REBOOT=1; shift 1 ;;
    -h|--help) echo "Usage: $0 [user@host] [--overlays-dir path] [--names name1,name2] [--reboot]"; exit 0 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [ ! -d "$OVERLAYS_DIR" ]; then
  echo "Overlays directory not found: $OVERLAYS_DIR" >&2
  exit 2
fi

# Collect dtbo files to deploy
mapfile -t DTBOS < <(cd "$OVERLAYS_DIR" && ls -1 *.dtbo 2>/dev/null || true)
if [ ${#DTBOS[@]} -eq 0 ]; then
  echo "No .dtbo files found in $OVERLAYS_DIR" >&2
  exit 3
fi

if [ -n "$NAMES" ]; then
  IFS=',' read -ra WANT <<< "$NAMES"
  FILTERED=()
  for f in "${DTBOS[@]}"; do
    base=${f%.dtbo}
    for w in "${WANT[@]}"; do
      if [ "$base" = "$w" ] || [ "$base" = "${w}-overlay" ]; then
        FILTERED+=("$f")
      fi
    done
  done
  DTBOS=("${FILTERED[@]}")
  if [ ${#DTBOS[@]} -eq 0 ]; then
    echo "No matching dtbo files for names: $NAMES" >&2
    exit 4
  fi
fi

echo "Deploying overlays to $REMOTE from $OVERLAYS_DIR:"
for f in "${DTBOS[@]}"; do echo " - $f"; done

# Helper to run remote commands via ssh
ssh_exec() { ssh -tt "$REMOTE" "$@"; }

# Copy each dtbo and move into place with sudo, backing up existing files
for dtbo in "${DTBOS[@]}"; do
  src="$OVERLAYS_DIR/$dtbo"
  tmp="/tmp/$dtbo"
  echo "Copying $src -> $REMOTE:$tmp"
  scp "$src" "$REMOTE:$tmp"
  echo "Installing $dtbo on remote"
  # attempt to place overlay into boot overlays; on transactional/readonly systems this may fail
  set +e
  ssh_exec "sudo bash -eux -c \"mkdir -p /boot/efi/overlays && (mountpoint -q /boot/efi && mount -o remount,rw /boot/efi) || true && if [ -f /boot/efi/overlays/$dtbo ]; then cp -a /boot/efi/overlays/$dtbo /boot/efi/overlays/$dtbo.bak.\$(date +%s); fi && mv $tmp /boot/efi/overlays/$dtbo && chmod 644 /boot/efi/overlays/$dtbo && sync\""
  rc=$?
  set -e
  if [ $rc -eq 0 ]; then
    echo "Installed $dtbo to /boot/efi/overlays"
  else
    echo "Warning: unable to install $dtbo into /boot/efi/overlays (rc=$rc). Falling back to /root/overlays on remote for manual action."
    ssh_exec "sudo mkdir -p /root/overlays && sudo mv $tmp /root/overlays/$dtbo && sudo chmod 644 /root/overlays/$dtbo && sudo chown root:root /root/overlays/$dtbo || true"
    echo "Placed $dtbo at /root/overlays/$dtbo on remote. You will need to install it into /boot/efi/overlays (image is likely transactional/readonly)."
  fi
done

# Update /boot/efi/extraconfig.txt to include dtoverlay lines
EXTRA_RCPT="/boot/efi/extraconfig.txt"
TMP_REMOTE="/tmp/extraconfig.txt.tmp"
echo "Updating remote $EXTRA_RCPT with dtoverlay entries"

# Build unique list of dtoverlay lines based on dtbo names
DTO_LINES_TMP=$(mktemp)
for dtbo in "${DTBOS[@]}"; do
  base=${dtbo%.dtbo}
  # strip -overlay suffix
  if [[ $base == *-overlay ]]; then base=${base%-overlay}; fi
  echo "dtoverlay=$base" >> "$DTO_LINES_TMP"
done
sort -u "$DTO_LINES_TMP" -o "$DTO_LINES_TMP"

# Fetch remote extraconfig if exists, else create (use double-quoting so $EXTRA_RCPT expands locally)
ssh_exec "sudo bash -eux -c \"if [ -f $EXTRA_RCPT ]; then cat $EXTRA_RCPT > $TMP_REMOTE; else echo '# extraconfig created by deploy script' > $TMP_REMOTE; fi\""

# Append missing lines
while IFS= read -r dto; do
  # grep remote file for exact line (use ssh_exec so sudo can prompt)
  if ssh_exec "sudo grep -Fxq '$dto' $TMP_REMOTE" >/dev/null 2>&1; then
    echo "Remote already has: $dto"
  else
    echo "Appending remote: $dto"
    ssh_exec "sudo bash -c 'echo \"$dto\" >> $TMP_REMOTE'"
  fi
done < "$DTO_LINES_TMP"

# Move tmp extraconfig into place (backup if exists)
ssh_exec "sudo bash -eux -c '\
  if [ -f $EXTRA_RCPT ]; then cp -a $EXTRA_RCPT ${EXTRA_RCPT}.bak.$(date +%s); fi && \
  mv $TMP_REMOTE $EXTRA_RCPT && chmod 644 $EXTRA_RCPT && sync'"

rm -f "$DTO_LINES_TMP"

echo "Deployment complete. Overlays installed and extraconfig updated on $REMOTE"

if [ "$REBOOT" -eq 1 ]; then
  echo "Rebooting remote host $REMOTE"
  ssh_exec "sudo reboot"
fi

echo "Done."
