#!/usr/bin/env bash
set -euo pipefail

# Auto-run the full orchestration until success or until max retries reached.
# Usage: $0 <device_ip> <ssh_user> <ssh_key> [--attempts N] [--wait-seconds S]

DRY_RUN=false
if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <device_ip> <ssh_user> <ssh_key> [--attempts N=3] [--wait-seconds S=60]"
  exit 1
fi

DEST_HOST="$1"
DEST_USER="$2"
SSH_KEY="$3"
shift 3
ATTEMPTS=3
WAIT_S=60
while [ "$#" -gt 0 ]; do
  case "$1" in
    --attempts)
      ATTEMPTS="$2"; shift 2; ;;
    --wait-seconds)
      WAIT_S="$2"; shift 2; ;;
    --help|-h)
      echo "Usage: $0 <device_ip> <ssh_user> <ssh_key> [--attempts N] [--wait-seconds S]"; exit 0; ;;
    --dry-run)
      DRY_RUN=true; shift; ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

LOGDIR=auto-run-$(date +%Y%m%d-%H%M%S)
mkdir -p "$LOGDIR"
ATTEMPT=1
while [ "$ATTEMPT" -le "$ATTEMPTS" ]; do
  echo "Attempt $ATTEMPT/$ATTEMPTS: running full orchestrator..."
  if [ "$DRY_RUN" = true ]; then
    echo "[dry-run] Would run: ./scripts/preflight_target.sh $DEST_HOST $DEST_USER $SSH_KEY" | tee "$LOGDIR/preflight-$ATTEMPT.log"
    echo "[dry-run] Would run: ./scripts/run_full_uconsole_tests.sh $DEST_HOST $DEST_USER $SSH_KEY --reboot-wait $WAIT_S" | tee "$LOGDIR/full-$ATTEMPT.log"
  else
    ./scripts/preflight_target.sh "$DEST_HOST" "$DEST_USER" "$SSH_KEY" > "$LOGDIR/preflight-$ATTEMPT.log" 2>&1 || true
    ./scripts/run_full_uconsole_tests.sh "$DEST_HOST" "$DEST_USER" "$SSH_KEY" --reboot-wait "$WAIT_S" > "$LOGDIR/full-$ATTEMPT.log" 2>&1 || true
  fi
  EXIT=$?
  if [ "$EXIT" -eq 0 ]; then
    echo "Success on attempt $ATTEMPT. Logs: $LOGDIR/full-$ATTEMPT.log"
    exit 0
  else
    echo "Attempt $ATTEMPT failed with exit $EXIT. See logs: $LOGDIR/full-$ATTEMPT.log"
    ATTEMPT=$((ATTEMPT+1))
    echo "Sleeping for $WAIT_S seconds before retry..."
    sleep "$WAIT_S"
  fi
done

echo "All attempts failed. Check logs in $LOGDIR for details."
exit 1
