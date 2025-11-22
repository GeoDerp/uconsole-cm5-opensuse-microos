#!/bin/bash
set -euo pipefail

echo "--- lsblk ---"
lsblk -o NAME,KNAME,TYPE,MOUNTPOINT,FSTYPE,LABEL,SIZE

echo "--- blkid ---"
blkid || true

parts=$(ls /dev/* 2>/dev/null | egrep -o '/dev/(mmcblk[0-9]p[0-9]+|sd[a-z][0-9]+|nvme[0-9]n[0-9]p[0-9]+)' | sort -u || true)

n=0
for p in $parts; do
  [ -b "$p" ] || continue
  mountpoint=$(findmnt -n -o TARGET --source "$p" || true)
  echo "\n=== partition: $p mounted: ${mountpoint:-no} ==="
  if [ -n "$mountpoint" ]; then
    echo "searching mounted $p"
    sudo find "$mountpoint" -maxdepth 5 -type f \( -iname "*.dtb" -o -iname "merged-clockworkpi.dtb" -o -iname "*cm5*.dtb" \) -printf "%p\n" || true
  else
    d="/tmp/mnt_search_$n"
    mkdir -p "$d"
    if sudo mount -o ro "$p" "$d" 2>/dev/null; then
      echo "searching $p mounted at $d"
      sudo find "$d" -maxdepth 5 -type f \( -iname "*.dtb" -o -iname "merged-clockworkpi.dtb" -o -iname "*cm5*.dtb" \) -printf "%p\n" || true
      sudo umount "$d" || true
      rmdir "$d" || true
    else
      echo "could not mount $p (skipping)"
    fi
    n=$((n+1))
  fi
done

echo "\n--- extra search in /boot ---"
sudo find /boot -maxdepth 4 -type f \( -iname "*.dtb" -o -iname "merged-clockworkpi.dtb" -o -iname "*cm5*.dtb" \) -printf "%p\n" 2>/dev/null || true

exit 0
