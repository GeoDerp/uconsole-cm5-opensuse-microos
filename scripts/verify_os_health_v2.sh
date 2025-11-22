#!/usr/bin/env bash
set -euo pipefail

# verify_os_health_v2.sh
# A safer, more testable verifier that supports EXTRACT_ONLY=1 and simulated mounts.

WORKDIR=$(cd "$(dirname "$0")/.." && pwd)
EXTRACT_ONLY=${EXTRACT_ONLY:-0}

usage() {
  cat <<EOF
Usage: $0 [--image </path/to/image.raw>] <device>
Examples:
  sudo $0 /dev/sda
  EXTRACT_ONLY=1 $0 --image openSUSE-MicroOS.raw ./does-not-matter
EOF
}

IMG_RAW=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image) IMG_RAW="$2"; shift 2 ;; 
    -h|--help) usage; exit 0 ;;
    *) DEV=$(realpath "$1"); shift 1 ;;
  esac
done

if [ -z "${DEV:-}" ]; then
  usage
  exit 2
fi

if (( EUID != 0 )) && [ "$EXTRACT_ONLY" -ne 1 ]; then
  echo "This script must be run as root unless EXTRACT_ONLY=1 is set" >&2
  exit 3
fi

FAIL=0
WARN=0

# optional image parity check
if [ -n "$IMG_RAW" ] && [ "$EXTRACT_ONLY" -ne 1 ]; then
  if [ -x "$WORKDIR/scripts/verify_flashed_image.sh" ]; then
    if ! "$WORKDIR/scripts/verify_flashed_image.sh" "$IMG_RAW" "$DEV"; then
      echo "Image parity flagged issues" >&2
      FAIL=1
    fi
  else
    echo "verify_flashed_image.sh not found; skipping parity check" >&2
  fi
fi

# Determine partitions
if [ "$EXTRACT_ONLY" -eq 1 ]; then
  BOOT_PART="$WORKDIR/boot-sim"
  ROOT_PART="$WORKDIR/root-sim"
  echo "EXTRACT_ONLY: using simulated mountpoints: $BOOT_PART / $ROOT_PART"
else
  PARTS=$(lsblk -nr -o NAME,TYPE "$DEV" 2>/dev/null | awk '$2=="part" {print "/dev/"$1}' || true)
  if [ -z "$PARTS" ]; then
    PARTS=$(ls ${DEV}?* 2>/dev/null || true)
  fi
  BOOT_PART="${DEV}1"
  ROOT_PART="${DEV}2"
  if [ ! -b "$BOOT_PART" ]; then
    BOOT_PART="${DEV}p1"
    ROOT_PART="${DEV}p2"
  fi
fi

TMP_BOOT_MNT=""
TMP_ROOT_MNT=""

if [ "$EXTRACT_ONLY" -eq 1 ]; then
  TMP_BOOT_MNT="$BOOT_PART"
  TMP_ROOT_MNT="$ROOT_PART"
  mkdir -p "$TMP_BOOT_MNT" "$TMP_ROOT_MNT"
else
  TMP_BOOT_MNT=$(mktemp -d)
  TMP_ROOT_MNT=$(mktemp -d)
fi

cleanup() {
  set +e
  if [ "$EXTRACT_ONLY" -ne 1 ]; then
    umount "$TMP_BOOT_MNT" 2>/dev/null || true
    umount "$TMP_ROOT_MNT" 2>/dev/null || true
    rmdir "$TMP_BOOT_MNT" 2>/dev/null || true
    rmdir "$TMP_ROOT_MNT" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# fsck only when real block partitions are present
if [ "$EXTRACT_ONLY" -ne 1 ] && [ -b "$BOOT_PART" ]; then
  FS_TYPE=$(blkid -s TYPE -o value "$BOOT_PART" 2>/dev/null || true)
  case "$FS_TYPE" in
    vfat|fat|fat32)
      if ! fsck.vfat -n "$BOOT_PART" >/dev/null 2>&1; then WARN=1; fi
      ;;
    ext4|ext3|ext2)
      if ! fsck -n "$BOOT_PART"; then WARN=1; fi
      ;;
    *) WARN=1;;
  esac
fi

if [ "$EXTRACT_ONLY" -ne 1 ] && [ -b "$ROOT_PART" ]; then
  FS_TYPE_ROOT=$(blkid -s TYPE -o value "$ROOT_PART" 2>/dev/null || true)
  if [ "$FS_TYPE_ROOT" = "ext4" ] || [ "$FS_TYPE_ROOT" = "ext3" ]; then
    FSCK_OUT=$(fsck -n "$ROOT_PART" 2>&1 || true)
    echo "$FSCK_OUT"
    if ! echo "$FSCK_OUT" | grep -q -E 'clean,|LIVE_JOURNAL'; then FAIL=1; fi
  fi
fi

# mount ro when appropriate
if [ "$EXTRACT_ONLY" -eq 1 ]; then
  echo "Using simulated mounts for boot/root."
else
  mount -o ro "$BOOT_PART" "$TMP_BOOT_MNT" 2>/dev/null || true
  mount -o ro "$ROOT_PART" "$TMP_ROOT_MNT" 2>/dev/null || true
fi

# boot checks
if [ -d "$TMP_BOOT_MNT" ]; then
  echo "Boot mount:$TMP_BOOT_MNT"
  if [ -f "$TMP_BOOT_MNT/config.txt" ]; then
    grep -E '^dtoverlay' "$TMP_BOOT_MNT/config.txt" || true
  fi
  if [ -f "$TMP_BOOT_MNT/cmdline.txt" ]; then
    ROOT_CMDLINE=$(grep -oE 'root=[^[:space:]]+' "$TMP_BOOT_MNT/cmdline.txt" || true)
    echo "cmdline root: $ROOT_CMDLINE"
    if [[ "$ROOT_CMDLINE" =~ ^root=UUID= ]] && [ "$EXTRACT_ONLY" -ne 1 ]; then
      UUID_IN_CMD=${ROOT_CMDLINE#root=UUID=}
      ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART" 2>/dev/null || true)
      if [ -n "$ROOT_UUID" ] && [ "$UUID_IN_CMD" != "$ROOT_UUID" ]; then
        WARN=1
        echo "cmdline root UUID mismatch: $UUID_IN_CMD vs $ROOT_UUID"
      fi
    fi
  else
    WARN=1
  fi
fi

# root fs checks
if [ -d "$TMP_ROOT_MNT" ]; then
  echo "Root mount:$TMP_ROOT_MNT"
  if [ ! -f "$TMP_ROOT_MNT/etc/os-release" ]; then
    FAIL=1
  fi
  if [ ! -f "$TMP_ROOT_MNT/etc/fstab" ]; then
    WARN=1
  fi
  if [ ! -d "$TMP_ROOT_MNT/lib/modules" ]; then
    WARN=1
  fi
fi

# Summary
if [ "$FAIL" -ne 0 ]; then
  echo "FAIL=$FAIL WARN=$WARN"
  exit 1
fi
if [ "$WARN" -ne 0 ]; then
  echo "FAIL=$FAIL WARN=$WARN"
  exit 2
fi

echo "FAIL=$FAIL WARN=$WARN"
exit 0
