#!/usr/bin/env bash
set -euo pipefail

usage(){
  cat <<EOF
Usage: $0 <device_ip> <ssh_user> <ssh_key> [--apply] [--reboot]

Scans /boot/vc/overlays and /boot/efi/overlays on target for DTBOs containing numeric brcm,pins values 44/45 (0x2c/0x2d).
If --apply is provided, the script will backup extraconfig.txt/config.txt and comment out `dtoverlay` lines for the conflicting overlays
and write them into the transactional snapshot (both vc and efi if present). Without --apply the script only prints the candidate overlays.
  Use --reboot to automatically reboot the device after applying changes.
  Use --disable-files to rename matching .dtbo files into a disabled subdirectory (safer when extraconfig changes alone do not prevent an overlay from being applied). Use --restore to revert disable-file renames.
EOF
}

if [ "$#" -lt 3 ]; then
  usage; exit 1
fi

DEST_HOST="$1"
DEST_USER="$2"
SSH_KEY="$3"
APPLY=false
DISABLE_FILES=false
RESTORE=false
REBOOT=false
for arg in "${@:4}"; do
  case "$arg" in
    --apply) APPLY=true ;;
    --disable-files) DISABLE_FILES=true ;;
    --restore) RESTORE=true ;;
    --reboot) REBOOT=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $arg"; usage; exit 1 ;;
  esac
done

echo "Scanning target $DEST_HOST for conflicting overlays (brcm,pins numeric 44/45)..."
TMP_SCRIPT="/tmp/find_conflict_overlays.remote.sh"
cat <<'REMOTE' > /tmp/find_conflict_overlays.remote.sh
#!/usr/bin/env bash
set -euo pipefail
conf=()
for dir in /boot/vc/overlays /boot/efi/overlays; do
  if [ -d "$dir" ]; then
    for f in "$dir"/*.dtbo; do
      [ -e "$f" ] || continue
      if command -v dtc >/dev/null 2>&1; then
        dtc -I dtb -O dts -o /tmp/out.dts "$f" || true
        found=0
        if grep -q -E "brcm,pins\s*=\s*<" /tmp/out.dts 2>/dev/null; then
          if grep -q -E "44|45|0x2c|0x2d" /tmp/out.dts 2>/dev/null; then
            found=1
          fi
        fi
        # check binary hex pattern if xxd/hexdump present
        if [ "$found" -eq 0 ]; then
          if command -v xxd >/dev/null 2>&1; then
            if xxd -p "$f" | tr -d '\n' | grep -q -E '0000002c|0000002d'; then
              found=1
            fi
          elif command -v hexdump >/dev/null 2>&1; then
            if hexdump -v -e '1/1 "%02x"' "$f" | tr -d '\n' | grep -q -E '0000002c|0000002d'; then
              found=1
            fi
          fi
        fi
        if [ "$found" -eq 1 ]; then
          conf+=("$f")
        fi
      else
        # fallback binary scan
        if command -v xxd >/dev/null 2>&1; then
          if xxd -p "$f" | tr -d '\n' | grep -q -E '0000002c|0000002d'; then
          conf+=("$f")
          fi
        elif command -v hexdump >/dev/null 2>&1; then
          if hexdump -v -e '1/1 "%02x"' "$f" | tr -d '\n' | grep -q -E '0000002c|0000002d'; then
            conf+=("$f")
          fi
        fi
        if strings "$f" | grep -qi "brcm,pins"; then
          conf+=("$f")
        fi
      fi
    done
  fi
done
printf "%s\n" "${conf[@]}"
REMOTE

scp -i "$SSH_KEY" -o StrictHostKeyChecking=no /tmp/find_conflict_overlays.remote.sh "$DEST_USER@$DEST_HOST:/tmp/find_conflict_overlays.remote.sh"
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$DEST_USER@$DEST_HOST" 'bash /tmp/find_conflict_overlays.remote.sh; rm -f /tmp/out.dts /tmp/find_conflict_overlays.remote.sh' > /tmp/conflicting_overlays.txt || true

echo "Found the following candidate overlays on target (file paths); may be empty if none found:"
cat /tmp/conflicting_overlays.txt || true
echo

if [ "$APPLY" = true ] || [ "$DISABLE_FILES" = true ] || [ "$RESTORE" = true ]; then
  echo "---> Applying changes: back up extraconfig/configs and comment out dtoverlay lines for these overlays"
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    filename=$(basename "$f")
    overlayname=${filename%.dtbo}
    echo "Candidate: $overlayname"
    # change /boot/vc/extraconfig.txt and /boot/efi/extraconfig.txt if present
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$DEST_USER@$DEST_HOST" \
      "sudo transactional-update run /bin/sh -c \"mkdir -p /tmp; if [ -f /boot/vc/extraconfig.txt ]; then cp /boot/vc/extraconfig.txt /boot/vc/extraconfig.txt.orig; sed -E '/^dtoverlay=${overlayname}(,|$)/d' /boot/vc/extraconfig.txt > /tmp/extraconfig && cat /tmp/extraconfig > /boot/vc/extraconfig.txt; fi\""
    # do same for efi
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$DEST_USER@$DEST_HOST" \
      "sudo transactional-update run /bin/sh -c \"if [ -f /boot/efi/extraconfig.txt ]; then cp /boot/efi/extraconfig.txt /boot/efi/extraconfig.txt.orig; sed -E '/^dtoverlay=${overlayname}(,|$)/d' /boot/efi/extraconfig.txt > /tmp/extraconfig && cat /tmp/extraconfig > /boot/efi/extraconfig.txt; fi\""
    # also edit config.txt files (comment out any matching dtoverlay lines)
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$DEST_USER@$DEST_HOST" \
      "sudo transactional-update run /bin/sh -c \"if [ -f /boot/vc/config.txt ]; then cp /boot/vc/config.txt /boot/vc/config.txt.orig; sed -E 's/^dtoverlay=${overlayname}(,|$)/#&/' /boot/vc/config.txt > /tmp/config && cat /tmp/config > /boot/vc/config.txt; fi\""
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$DEST_USER@$DEST_HOST" \
      "sudo transactional-update run /bin/sh -c \"if [ -f /boot/efi/config.txt ]; then cp /boot/efi/config.txt /boot/efi/config.txt.orig; sed -E 's/^dtoverlay=${overlayname}(,|$)/#&/' /boot/efi/config.txt > /tmp/config && cat /tmp/config > /boot/efi/config.txt; fi\""
    # If disable-files is requested, move the dtbo out into a disabled directory
    if [ "$DISABLE_FILES" = true ] && [ "$RESTORE" = false ]; then
      echo "Disabling overlay file: $f"
      # Determine base dir (vc or efi) and filename
      basedir=$(dirname "$f")
      filename=$(basename "$f")
      # move into disabled subdir preserving name
      ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$DEST_USER@$DEST_HOST" \
        "sudo transactional-update run /bin/sh -c \"mkdir -p ${basedir}/disabled; if [ -f \"${f}\" ]; then mv \"${f}\" ${basedir}/disabled/\"${filename}\"; fi\""
    fi
    # If restore requested, move back from disabled
    if [ "$RESTORE" = true ]; then
      echo "Restoring any disabled overlay file for: $overlayname"
      # find base dir from candidate listing, test both vc and efi
      for basedir in /boot/vc/overlays /boot/efi/overlays; do
        ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$DEST_USER@$DEST_HOST" \
          "sudo transactional-update run /bin/sh -c \"if [ -f ${basedir}/disabled/\"${overlayname}.dtbo\" ]; then mv ${basedir}/disabled/\"${overlayname}.dtbo\" ${basedir}/\"${overlayname}.dtbo\"; fi\""
      done
    fi
  done < /tmp/conflicting_overlays.txt
  echo "Applied edits to extraconfig files; backed up originals as *.orig"
  if [ "$REBOOT" = true ]; then
    echo "Rebooting target..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$DEST_USER@$DEST_HOST" 'sudo systemctl reboot'
  fi
else
  echo "Run the script again with --apply to modify extraconfig and remove conflicting overlays. Use --reboot to reboot the target afterwards."
fi

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$DEST_USER@$DEST_HOST" 'rm -f /tmp/find_conflict_overlays.remote.sh /tmp/out.dts' || true
rm -f /tmp/find_conflict_overlays.remote.sh /tmp/conflicting_overlays.txt

exit 0
