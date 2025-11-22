#!/usr/bin/env bash
set -euo pipefail

# verify_os_health.sh
# Thin wrapper: delegate to verify_os_health_v2.sh for all checks.

WORKDIR=$(cd "$(dirname "$0")/.." && pwd)
V2="$WORKDIR/scripts/verify_os_health_v2.sh"
if [ -x "$V2" ]; then
  exec "$V2" "$@"
else
  echo "ERROR: ${V2} not found or not executable" >&2
  exit 1
fi
