#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/auto_cm5_checks_and_apply.sh --host user@host --key /path/to/key
#        [--dtb /remote/path/to/merged-clockworkpi.dtb] [--apply] [--reboot]
#
# By default this performs read-only diagnostics remotely and prints results.
# Use --apply to copy the DTB into a transactional snapshot on the remote and
# print the inside-snapshot sha256. Use --reboot to reboot the remote **only if**
# the inside-snapshot sha256 equals the local DTB sha256.

HOST=""
KEY=""
REMOTE_DTB=""
APPLY=0
REBOOT=0

print_usage() {
  cat <<EOF
Usage: $0 --host user@host --key /path/to/key [--dtb /remote/path] [--apply] [--reboot]

Required:
  --host   : SSH target (user@host)
  --key    : Path to SSH private key

Optional:
  --dtb    : Remote path to DTB (default: /home/<user>/merged-clockworkpi.dtb)
  --apply  : Copy local DTB into transactional snapshot on remote
  --reboot : Reboot remote if the inside-TU sha256 matches the local DTB

Example:
  $0 --host myuser@192.168.1.100 --key ~/.ssh/id_rsa --apply --reboot
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="$2"; shift 2;;
    --key) KEY="$2"; shift 2;;
    --dtb) REMOTE_DTB="$2"; shift 2;;
    --apply) APPLY=1; shift;;
    --reboot) REBOOT=1; shift;;
    -h|--help) print_usage; exit 0;;
    *) echo "Unknown arg: $1"; print_usage; exit 2;;
  esac
done

# Validate required parameters
if [[ -z "$HOST" || -z "$KEY" ]]; then
  echo "Error: --host and --key are required" >&2
  print_usage
  exit 1
fi

if [ ! -f "$KEY" ]; then
  echo "SSH key not found: $KEY" >&2
  exit 2
fi

# Extract username from HOST for default DTB path
REMOTE_USER="${HOST%%@*}"
if [[ -z "$REMOTE_DTB" ]]; then
  REMOTE_DTB="/home/${REMOTE_USER}/merged-clockworkpi.dtb"
fi

LOCAL_SHA=""
if ssh -i "$KEY" "$HOST" test -f "$REMOTE_DTB"; then
  LOCAL_SHA=$(ssh -i "$KEY" "$HOST" sha256sum "$REMOTE_DTB" | awk '{print $1}')
else
  echo "Remote DTB not present at $REMOTE_DTB" >&2
fi

echo "Running diagnostics on $HOST"
ssh -i "$KEY" "$HOST" bash -s -- "$REMOTE_USER" <<'REMOTE'
set -euo pipefail
REMOTE_USER="$1"

echo "==== 0) Environment ===="
whoami
uname -a
date

echo
echo "==== kernel logs (pinctrl/i2c/axp/backlight/drm) ===="
sudo journalctl -k -b --no-pager | grep -Ei 'pinctrl|pinctrl-rp1|i2c|designware|axp|axp221|ocp8178|backlight|drm|panel|brcm' || true

echo
echo "==== DTB checksums (remote) ===="
if [ -f "/home/${REMOTE_USER}/merged-clockworkpi.dtb" ]; then sha256sum "/home/${REMOTE_USER}/merged-clockworkpi.dtb" || true; else echo "no /home/${REMOTE_USER}/merged-clockworkpi.dtb"; fi
if [ -f /boot/vc/merged-clockworkpi.dtb ]; then sha256sum /boot/vc/merged-clockworkpi.dtb || true; else echo "no /boot/vc/merged-clockworkpi.dtb"; fi
if [ -f /boot/efi/bcm2712-rpi-cm5-cm5io.dtb ]; then sha256sum /boot/efi/bcm2712-rpi-cm5-cm5io.dtb || true; else echo "no EFI DTB"; fi

echo
echo "==== backlight / drm / panel ===="
ls -la /sys/class/backlight || true
for b in /sys/class/backlight/*; do
  [ -e "$b" ] || continue
  echo "== $b =="
  cat "$b/brightness" 2>/dev/null || true
  cat "$b/max_brightness" 2>/dev/null || true
done

echo
echo "==== inputs ===="
cat /proc/bus/input/devices || true

echo
echo "==== i2c / power_supply ===="
ls -la /sys/bus/i2c/devices || true
ls -la /sys/class/power_supply || true

echo
echo "==== device-tree rp1 i2c brcm,pins (if present) ===="
sudo find /proc/device-tree -type f -name 'brcm,pins' -exec sh -c 'echo "{}"; hexdump -C "{}"' \; || true

REMOTE

if [ "$APPLY" -eq 1 ]; then
  echo
  echo "Applying DTB into transactional snapshot on remote..."
  ssh -i "$KEY" "$HOST" bash -s -- "$REMOTE_USER" <<'TU'
set -euo pipefail
REMOTE_USER="$1"
echo "Snapshot shell: copying /home/${REMOTE_USER}/merged-clockworkpi.dtb -> /boot/vc/merged-clockworkpi.dtb"
sudo transactional-update shell <<INS
set -e
cp -v /home/${REMOTE_USER}/merged-clockworkpi.dtb /boot/vc/merged-clockworkpi.dtb
if [ -d /boot/efi ]; then
  for f in /boot/efi/bcm2712-rpi-cm5-cm5io.dtb /boot/efi/bcm2712-rpi-cm4io.dtb; do
    if [ -f "\$f" ]; then
      cp -v /boot/vc/merged-clockworkpi.dtb "\$f" || true
    fi
  done
fi
echo "SHA inside snapshot (installed):"
sha256sum /boot/vc/merged-clockworkpi.dtb || true
[ -f /boot/efi/bcm2712-rpi-cm5-cm5io.dtb ] && sha256sum /boot/efi/bcm2712-rpi-cm5-cm5io.dtb || true
ls -l /boot/vc/merged-clockworkpi.dtb || true
INS
echo "Snapshot copy finished"
TU

  echo
  echo "Post-TU: on-disk checksums (remote real root)"
  ssh -i "$KEY" "$HOST" 'sha256sum /boot/vc/merged-clockworkpi.dtb 2>/dev/null || true; [ -f /boot/efi/bcm2712-rpi-cm5-cm5io.dtb ] && sha256sum /boot/efi/bcm2712-rpi-cm5-cm5io.dtb || true; ls -l /boot/vc/merged-clockworkpi.dtb || true'

  if [ "$REBOOT" -eq 1 ]; then
    echo
    echo "Checking SHA inside snapshot vs local remote copy..."
    INSIDE_SHA=$(ssh -i "$KEY" "$HOST" sudo sha256sum /boot/vc/merged-clockworkpi.dtb | awk '{print $1}' || true)
    LOCAL_SHA=$(ssh -i "$KEY" "$HOST" sha256sum "$REMOTE_DTB" | awk '{print $1}' || true)
    echo "inside-sha: $INSIDE_SHA"
    echo "local-sha:  $LOCAL_SHA"
    if [ -n "$INSIDE_SHA" ] && [ "$INSIDE_SHA" = "$LOCAL_SHA" ]; then
      echo "SHAs match. Rebooting remote now..."
      ssh -i "$KEY" "$HOST" 'sudo systemctl reboot'
      echo "Reboot command sent. Give the device ~30s to reboot before running post-boot checks."
    else
      echo "SHAs do not match; NOT rebooting. Investigate copy/visibility inside TU shell." >&2
    fi
  fi
fi

echo "Done."
