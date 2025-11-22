#!/usr/bin/env bash
set -euo pipefail

usage(){
  cat <<EOF
Usage: $0
Runs diagnostics on a running CM5 to detect brcm,pins being applied to RP1 and confirms PMIC binding.
Outputs diagnostic data (aliases, dtbos that have numeric brcm pins, journal entries).
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

echo "=== Diagnostic: pinctrl-rp1 / brcm,pins scan ==="
echo

echo "[1] Check kernel logs for pinctrl-rp1 errors"
journalctl -k -b --no-pager | grep -i 'pinctrl-rp1' | sed -n '1,80p' || echo "(none)"
echo

echo "[2] Check /proc/device-tree for RP1 i2c brcm,pins and aliases"
echo "-- Alias mapping (aliases):"
if [ -f /proc/device-tree/aliases ]; then
  dtc -I fs -O dts /proc/device-tree | grep -n "aliases" -A 10 || true
else
  echo "No /proc/device-tree/aliases found"
fi
echo "-- /proc/device-tree/aliases/i2c1 content (if available):"
if [ -f /proc/device-tree/aliases/i2c1 ]; then
  hexdump -C /proc/device-tree/aliases/i2c1 || true
  echo; printf "(value as text): "; cat /proc/device-tree/aliases/i2c1 || true
else
  echo "/proc/device-tree/aliases/i2c1 not present"
fi
echo

echo "-- RP1 i2c brcm,pins (hex bytes if present):"
RP1_I2C_BRCP=/proc/device-tree/axi/pcie@1000120000/rp1_nexus/rp1/gpio@d0000/i2c1/brcm,pins
if [ -f "$RP1_I2C_BRCP" ]; then
  echo "Found file: $RP1_I2C_BRCP"
  echo -n "Value: "; hexdump -v -e '1/1 "%02x "' "$RP1_I2C_BRCP" || true
else
  echo "$RP1_I2C_BRCP does not exist in the running device tree"
fi
echo

echo "[3] Check overlays in /boot/vc/overlays and /boot/efi/overlays for numeric brcm,pins 44/45"
for dir in /boot/vc/overlays /boot/efi/overlays; do
  if [ -d "$dir" ]; then
    echo "Checking $dir"
    for f in "$dir"/*.dtbo; do
      [ -e "$f" ] || continue
      tmpd=$(mktemp -d)
      if command -v dtc >/dev/null 2>&1; then
        dtc -I dtb -O dts -o "$tmpd/out.dts" "$f" || true
        if grep -E "brcm,pins\s*=\s*<.*44|brcm,pins\s*=\s*<.*0x2c" "$tmpd/out.dts" -n; then
          echo "--> Numeric brcm pins found in $f (via decompile)"
        fi
        if grep -n "i2c1" "$tmpd/out.dts"; then
          echo "i2c1 references present in $f (via decompile)"
        fi
      else
        echo "dtc not present on target; using binary scan for $f"
        # Search for ASCII brcm,pins or numeric 44/45 pattern 00 00 00 2c / 2d
        if strings "$f" | grep -qi "brcm,pins"; then
          echo "--> ASCII 'brcm,pins' found in $f (strings)"
        fi
        if strings "$f" | grep -qi "i2c1"; then
          echo "i2c1 references present in $f (strings)"
        fi
        if command -v hexdump >/dev/null 2>&1; then
          # produce hex stream (no spaces) and search for 0000002c/0000002d
          if hexdump -v -e '1/1 "%02x"' "$f" | grep -q -E '0000002c|0000002d'; then
            echo "--> Numeric brcm pins value (44/45) found in $f (hexdump)"
          fi
        elif command -v xxd >/dev/null 2>&1; then
          if xxd -p "$f" | tr -d '\n' | grep -q -E '0000002c|0000002d'; then
            echo "--> Numeric brcm pins value (44/45) found in $f (xxd)"
          fi
        else
          echo "hexdump/xxd not present; cannot perform binary numeric search on $f"
        fi
      fi
      rm -rf "$tmpd"
    done
  else
    echo "$dir not present"
  fi
done
echo

echo "[4] Check merged DTB & explicit overlay binaries in /boot/vc"
if [ -f /boot/vc/merged-clockworkpi.dtb ]; then
  echo "Merged dtb SHA256 (/boot/vc/merged-clockworkpi.dtb): $(sha256sum /boot/vc/merged-clockworkpi.dtb | awk '{print $1}')"
  dtc -I dtb -O dts -o /tmp/merged.dts /boot/vc/merged-clockworkpi.dtb || true
  grep -n "i2c1 =\|rp1_i2c1 =\|brcm,pins = <" /tmp/merged.dts || echo "(no relevant entries)"
else
  echo "/boot/vc/merged-clockworkpi.dtb not present"
fi
if [ -f /boot/efi/merged-clockworkpi.dtb ]; then
  echo "Merged dtb SHA256 (/boot/efi/merged-clockworkpi.dtb): $(sha256sum /boot/efi/merged-clockworkpi.dtb | awk '{print $1}')"
else
  echo "/boot/efi/merged-clockworkpi.dtb not present"
fi
echo

echo "[4a] Check the running device tree binary if accessible via /sys/firmware/fdt"
if [ -f /sys/firmware/fdt ]; then
  echo "Copying runtime DTB from /sys/firmware/fdt to /tmp/runtime-merged.dtb"
  cp /sys/firmware/fdt /tmp/runtime-merged.dtb || true
  if [ -f /tmp/runtime-merged.dtb ]; then
    echo "SHA256 of runtime DTB (/sys/firmware/fdt): $(sha256sum /tmp/runtime-merged.dtb | awk '{print $1}')"
    if command -v dtc >/dev/null 2>&1; then
      dtc -I dtb -O dts -o /tmp/runtime-merged.dts /tmp/runtime-merged.dtb || true
      grep -n "i2c1 =\|rp1_i2c1 =\|brcm,pins = <" /tmp/runtime-merged.dts || echo "(no relevant entries in runtime dtb)"
    else
      echo "dtc not present; cannot decompile runtime DTB to dts"
    fi
  fi
  if [ -f /boot/vc/merged-clockworkpi.dtb ] && [ -f /tmp/runtime-merged.dtb ]; then
    if cmp -s /tmp/runtime-merged.dtb /boot/vc/merged-clockworkpi.dtb; then
      echo "Runtime DTB matches /boot/vc/merged-clockworkpi.dtb (content identical)"
    else
      echo "Runtime DTB does NOT match /boot/vc/merged-clockworkpi.dtb"
    fi
  fi
  if [ -f /boot/efi/merged-clockworkpi.dtb ] && [ -f /tmp/runtime-merged.dtb ]; then
    if cmp -s /tmp/runtime-merged.dtb /boot/efi/merged-clockworkpi.dtb; then
      echo "Runtime DTB matches /boot/efi/merged-clockworkpi.dtb (content identical)"
    else
      echo "Runtime DTB does NOT match /boot/efi/merged-clockworkpi.dtb"
    fi
  fi
else
  echo "/sys/firmware/fdt not available on this kernel - fallback to using /proc/device-tree"
  if command -v dtc >/dev/null 2>&1; then
    echo "Creating a DTB from /proc/device-tree and writing /tmp/runtime-merged.dtb"
    dtc -I fs -O dtb -o /tmp/runtime-merged.dtb /proc/device-tree || true
    if [ -f /tmp/runtime-merged.dtb ]; then
      echo "SHA256 of runtime DTB (compiled from /proc/device-tree): $(sha256sum /tmp/runtime-merged.dtb | awk '{print $1}')"
      dtc -I dtb -O dts -o /tmp/runtime-merged.dts /tmp/runtime-merged.dtb || true
      grep -n "i2c1 =\|rp1_i2c1 =\|brcm,pins = <" /tmp/runtime-merged.dts || echo "(no relevant entries in runtime dtb)"
    fi
  else
    echo "dtc not present and /sys/firmware/fdt not available; cannot produce a runtime DTB for binary comparison"
  fi
fi
echo

echo "[5] PMIC and i2c devices"
echo "-- i2c bus devices:"
ls -1 /sys/bus/i2c/devices || true
echo "-- Look for x-powers/axp221 or axp22x devices in sysfs or dmesg:"
ls -1 /sys/bus/i2c/devices/* | xargs -r -n1 bash -lc 'grep -H "x-powers\|axp22x\|axp221" -s /sys/bus/i2c/devices/$(basename "$0")/subsystem 2>/dev/null || true' || true
echo

echo "[6] Search kernel logs for invalid brcm pins, again (more lines):"
journalctl -k -b --no-pager | grep -i 'invalid brcm,pins' -n | sed -n '1,200p' || echo "(none)"
echo

echo "[7] Print active extraconfig lines (if present)"
if [ -f /boot/vc/extraconfig.txt ]; then
  echo "/boot/vc/extraconfig.txt contents:"; sed -n '1,200p' /boot/vc/extraconfig.txt || true
else
  echo "/boot/vc/extraconfig.txt not present"
fi
if [ -f /boot/efi/extraconfig.txt ]; then
  echo "/boot/efi/extraconfig.txt contents:"; sed -n '1,200p' /boot/efi/extraconfig.txt || true
else
  echo "/boot/efi/extraconfig.txt not present"
fi
echo
echo "[8] Search config.txt and config files for dtoverlay lines (vc and efi)"
for f in /boot/vc/config.txt /boot/efi/config.txt /boot/config.txt; do
  if [ -f "$f" ]; then
    echo "Config file: $f"; grep -n "dtoverlay" "$f" || echo "(no dtoverlay lines)"
  fi
done

echo "=== Diagnostic complete ==="
exit 0
