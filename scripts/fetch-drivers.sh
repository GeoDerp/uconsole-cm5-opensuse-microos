#!/usr/bin/env bash
# fetch-drivers.sh — Download GPL-licensed kernel driver sources for uConsole CM5
#
# The driver source code is licensed under GPL-2.0 and cannot be distributed
# inside this MIT-licensed repository. This script fetches it from the original
# upstream repositories and sets up the out-of-tree build structure.
#
# Sources:
#   - ClockworkPi panel/backlight drivers: Rex's ClockworkPi Linux kernel fork
#   - RP1 DSI display driver:              Raspberry Pi Linux kernel
#   - RP1 audio output driver:             Raspberry Pi Linux kernel
#   - AXP20x battery/AC power drivers:     Mainline Linux kernel
#
# Usage: ./scripts/fetch-drivers.sh [--clean]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
DRIVERS_DIR="$REPO_DIR/extracted-drivers"

# Upstream raw content URLs
REX_RAW="https://raw.githubusercontent.com/ak-rex/ClockworkPi-linux/rpi-6.12.y"
RPI_RAW="https://raw.githubusercontent.com/raspberrypi/linux/rpi-6.12.y"
MAINLINE_RAW="https://raw.githubusercontent.com/torvalds/linux/master"

log() { echo -e "\033[0;32m[FETCH]\033[0m $1"; }
err() { echo -e "\033[0;31m[ERROR]\033[0m $1" >&2; }

download() {
    local url="$1"
    local dest="$2"
    mkdir -p "$(dirname "$dest")"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$dest"
    elif command -v wget >/dev/null 2>&1; then
        wget -q "$url" -O "$dest"
    else
        err "Neither curl nor wget found. Please install one."
        exit 1
    fi
}

# Generate a standard out-of-tree Makefile
make_simple_makefile() {
    local dir="$1"
    local obj_name="$2"
    cat > "$dir/Makefile" <<EOF
obj-m := ${obj_name}.o

KERNELDIR ?= /lib/modules/\$(shell uname -r)/build
PWD := \$(shell pwd)

all:
	\$(MAKE) -C \$(KERNELDIR) M=\$(PWD) modules

clean:
	\$(MAKE) -C \$(KERNELDIR) M=\$(PWD) clean
EOF
}

# Handle --clean flag
if [[ "${1:-}" == "--clean" ]]; then
    log "Removing extracted-drivers/..."
    rm -rf "$DRIVERS_DIR"
    log "Done."
    exit 0
fi

if [[ -d "$DRIVERS_DIR" ]] && [[ -n "$(ls -A "$DRIVERS_DIR" 2>/dev/null)" ]]; then
    log "extracted-drivers/ already exists. Use --clean to re-fetch."
    exit 0
fi

mkdir -p "$DRIVERS_DIR"

# ──────────────────────────────────────────────
# 1. ClockworkPi Panel Drivers (from Rex's fork)
# ──────────────────────────────────────────────
log "Fetching panel-cwu50 (CWU50 DSI panel)..."
mkdir -p "$DRIVERS_DIR/panel-cwu50"
download "$REX_RAW/drivers/gpu/drm/panel/panel-cwu50.c" "$DRIVERS_DIR/panel-cwu50/panel-cwu50.c"
make_simple_makefile "$DRIVERS_DIR/panel-cwu50" "panel-cwu50"

log "Fetching panel-cwd686 (CWD686 DSI panel)..."
mkdir -p "$DRIVERS_DIR/panel-cwd686"
download "$REX_RAW/drivers/gpu/drm/panel/panel-cwd686.c" "$DRIVERS_DIR/panel-cwd686/panel-cwd686.c"
make_simple_makefile "$DRIVERS_DIR/panel-cwd686" "panel-cwd686"

log "Fetching panel-cwu50-cm3 (CWU50 CM3 variant)..."
mkdir -p "$DRIVERS_DIR/panel-cwu50-cm3"
download "$REX_RAW/drivers/gpu/drm/panel/panel-cwu50-cm3.c" "$DRIVERS_DIR/panel-cwu50-cm3/panel-cwu50-cm3.c"
make_simple_makefile "$DRIVERS_DIR/panel-cwu50-cm3" "panel-cwu50-cm3"

# ──────────────────────────────────────────────
# 2. OCP8178 Backlight Driver (from Rex's fork)
# ──────────────────────────────────────────────
log "Fetching ocp8178_bl (1-wire backlight)..."
mkdir -p "$DRIVERS_DIR/ocp8178_bl"
download "$REX_RAW/drivers/video/backlight/ocp8178_bl.c" "$DRIVERS_DIR/ocp8178_bl/ocp8178_bl.c"
make_simple_makefile "$DRIVERS_DIR/ocp8178_bl" "ocp8178_bl"

# ──────────────────────────────────────────────
# 3. RP1 DSI Display Driver (from Raspberry Pi)
# ──────────────────────────────────────────────
log "Fetching drm-rp1-dsi (RP1 DSI controller)..."
mkdir -p "$DRIVERS_DIR/drm-rp1-dsi"
download "$RPI_RAW/drivers/gpu/drm/rp1/rp1-dsi/rp1_dsi.c"     "$DRIVERS_DIR/drm-rp1-dsi/rp1_dsi.c"
download "$RPI_RAW/drivers/gpu/drm/rp1/rp1-dsi/rp1_dsi.h"     "$DRIVERS_DIR/drm-rp1-dsi/rp1_dsi.h"
download "$RPI_RAW/drivers/gpu/drm/rp1/rp1-dsi/rp1_dsi_dma.c" "$DRIVERS_DIR/drm-rp1-dsi/rp1_dsi_dma.c"
download "$RPI_RAW/drivers/gpu/drm/rp1/rp1-dsi/rp1_dsi_dsi.c" "$DRIVERS_DIR/drm-rp1-dsi/rp1_dsi_dsi.c"
# rp1_platform.h is not in the rp1-dsi subdirectory; fetch from the rp1 parent or include path
download "$RPI_RAW/include/linux/rp1_platform.h"               "$DRIVERS_DIR/drm-rp1-dsi/rp1_platform.h" 2>/dev/null || \
download "$RPI_RAW/drivers/gpu/drm/rp1/rp1-dsi/rp1_platform.h" "$DRIVERS_DIR/drm-rp1-dsi/rp1_platform.h" 2>/dev/null || \
    log "  Warning: rp1_platform.h not found upstream — you may need to create a stub."

cat > "$DRIVERS_DIR/drm-rp1-dsi/Makefile" <<'EOF'
obj-m := drm-rp1-dsi.o
drm-rp1-dsi-y := rp1_dsi.o rp1_dsi_dma.o rp1_dsi_dsi.o

ccflags-y += -I$(src)

KERNELDIR ?= /lib/modules/$(shell uname -r)/build
PWD := $(shell pwd)

all:
	$(MAKE) -C $(KERNELDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KERNELDIR) M=$(PWD) clean
EOF

# ──────────────────────────────────────────────
# 4. RP1 Audio Output Driver (from Raspberry Pi)
# ──────────────────────────────────────────────
log "Fetching rp1_aout (RP1 PWM audio)..."
mkdir -p "$DRIVERS_DIR/rp1_aout"
download "$RPI_RAW/sound/soc/raspberrypi/rp1_aout.c" "$DRIVERS_DIR/rp1_aout/rp1_aout.c"

cat > "$DRIVERS_DIR/rp1_aout/Makefile" <<'EOF'
obj-m := snd-soc-rp1-aout.o
snd-soc-rp1-aout-objs := rp1_aout.o

KDIR := /lib/modules/$(shell uname -r)/build
PWD := $(shell pwd)

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
EOF

# ──────────────────────────────────────────────
# 5. AXP20x Power Drivers (from mainline Linux)
# ──────────────────────────────────────────────
log "Fetching axp20x_battery (AXP20x fuel gauge)..."
mkdir -p "$DRIVERS_DIR/axp20x_battery"
download "$MAINLINE_RAW/drivers/power/supply/axp20x_battery.c" "$DRIVERS_DIR/axp20x_battery/axp20x_battery.c"
make_simple_makefile "$DRIVERS_DIR/axp20x_battery" "axp20x_battery"

log "Fetching axp20x_ac_power (AXP20x AC supply)..."
mkdir -p "$DRIVERS_DIR/axp20x_ac_power"
download "$MAINLINE_RAW/drivers/power/supply/axp20x_ac_power.c" "$DRIVERS_DIR/axp20x_ac_power/axp20x_ac_power.c"
make_simple_makefile "$DRIVERS_DIR/axp20x_ac_power" "axp20x_ac_power"

# ──────────────────────────────────────────────
# 6. Apply CM5-specific patches
# ──────────────────────────────────────────────
PATCHES_DIR="$REPO_DIR/patches"
if [[ -d "$PATCHES_DIR" ]] && ls "$PATCHES_DIR"/*.patch >/dev/null 2>&1; then
    log "Applying CM5-specific patches..."
    for p in "$PATCHES_DIR"/*.patch; do
        if patch --dry-run -p1 -d "$REPO_DIR" < "$p" >/dev/null 2>&1; then
            patch -p1 -d "$REPO_DIR" < "$p" >/dev/null
            log "  Applied $(basename "$p")"
        else
            err "  FAILED to apply $(basename "$p") — file may have changed upstream"
        fi
    done
else
    log "No patches found in patches/ — using upstream code as-is."
fi

# ──────────────────────────────────────────────
# Done
# ──────────────────────────────────────────────
log ""
log "✅ All driver sources fetched into extracted-drivers/"
log ""
log "These files are GPL-2.0 licensed and are NOT part of this MIT repository."
log "They are gitignored and must be fetched again after a fresh clone."
log ""
log "Next step: run ./scripts/install_uconsole_offline.sh to compile and deploy."
