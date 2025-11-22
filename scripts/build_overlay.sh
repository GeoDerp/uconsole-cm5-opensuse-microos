#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <overlay.dts> [output.dtbo]"
  exit 1
fi

INPUT="$1"
OUT=${2:-/tmp/$(basename "$INPUT" .dts).dtbo}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
STUB_INCLUDES="$REPO_ROOT/tools/dtc_stub_includes"

echo "Compiling $INPUT -> $OUT"

# Check if the DTS file uses #include directives (needs preprocessor)
if grep -q '^#include' "$INPUT"; then
  echo "  (using C preprocessor for #include directives)"
  cpp -nostdinc -I "$STUB_INCLUDES" -undef -x assembler-with-cpp "$INPUT" | \
    dtc -@ -I dts -O dtb -o "$OUT" -
else
  dtc -@ -I dts -O dtb -o "$OUT" "$INPUT"
fi

echo "Wrote $OUT"

# Print sha256 for verification
sha256sum "$OUT"
