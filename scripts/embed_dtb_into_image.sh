#!/usr/bin/env bash
set -euo pipefail

# Append a DTB to a kernel Image safely.
# Usage: scripts/embed_dtb_into_image.sh --image Image --dtb merged-clockworkpi.dtb --out Image.merged

usage(){
  echo "Usage: $0 --image PATH --dtb PATH [--out PATH]"
  exit 2
}

IMAGE=""
DTB=""
OUT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --image) IMAGE="$2"; shift 2;;
    --dtb) DTB="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    -h|--help) usage;;
    *) echo "Unknown arg: $1"; usage;;
  esac
done

[ -n "$IMAGE" ] || usage
[ -n "$DTB" ] || usage
[ -n "$OUT" ] || OUT="${IMAGE}.merged"

if [ ! -f "$IMAGE" ]; then
  echo "Image not found: $IMAGE" >&2
  exit 3
fi
if [ ! -f "$DTB" ]; then
  echo "DTB not found: $DTB" >&2
  exit 4
fi

echo "Checking for existing FDT magic inside $IMAGE"
if grep -aob $'\xD0\x0D\xFE\xED' "$IMAGE" >/dev/null; then
  echo "Warning: Image already contains FDT magic bytes (may include an appended DTB). Results may overwrite behavior." >&2
fi

echo "Creating merged image: $OUT"
cp -a "$IMAGE" "$OUT"

# Ensure appended DTB is aligned to 4 bytes (FDT is fine but align for cleanliness)
DTB_SIZE=$(stat -c%s "$DTB")
PAD=$(( (4 - (DTB_SIZE % 4)) %4 ))

if [ "$PAD" -ne 0 ]; then
  echo "Padding DTB by $PAD bytes for 4-byte alignment"
  dd if=/dev/zero bs=1 count=$PAD 2>/dev/null >> "$DTB" || true
fi

echo "Appending DTB ($DTB -> $OUT)"
cat "$DTB" >> "$OUT"

echo "Syncing to disk"
sync

echo "SHA256 sums"
sha256sum "$IMAGE" "$DTB" "$OUT" || true

echo "Searching for FDT magic in merged output"
if grep -aob $'\xD0\x0D\xFE\xED' "$OUT" | sed -n '1,5p'; then
  echo "Found FDT magic(s) in $OUT"
fi

echo "Done. Output: $OUT"

exit 0
