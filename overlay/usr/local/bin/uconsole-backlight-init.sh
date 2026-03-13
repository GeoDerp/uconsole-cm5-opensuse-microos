#!/bin/bash
# uConsole hardware initialization
set -x
/usr/sbin/modprobe i2c-dev 2>/dev/null

# 1. Find PMIC bus — dynamic detection, NOT hardcoded
AXP_BUS=$(/usr/sbin/i2cdetect -l | grep -m1 'i2c0if\|i2c-gpio\|f00000002.i2c' | cut -f1 | cut -d- -f2)
[ -z "$AXP_BUS" ] && AXP_BUS=15
AXP_ADDR=0x34

# 2. Maximize Power for Peripherals
# Enable all LDOs
/usr/sbin/i2cset -y -f $AXP_BUS $AXP_ADDR 0x12 0xff
# Set V_OFF to 3.0V (Level 4)
/usr/sbin/i2cset -y -f $AXP_BUS $AXP_ADDR 0x31 0x04
# Maximize VBUS current limit (No limit)
/usr/sbin/i2cset -y -f $AXP_BUS $AXP_ADDR 0x30 0x63

# 3. Handle USB Hub Power (GPIO 42/43 on RP1)
RP1_GPIO_CHIP=$(grep -l pinctrl-rp1 /sys/class/gpio/gpiochip*/label | head -n 1 | sed 's|.*/gpiochip||' | sed 's|/label||')
if [ -n "$RP1_GPIO_CHIP" ]; then
    for g in 42 43; do
        GPIO_NUM=$((RP1_GPIO_CHIP + g))
        echo $GPIO_NUM > /sys/class/gpio/export 2>/dev/null
        echo out > /sys/class/gpio/gpio$GPIO_NUM/direction 2>/dev/null
        echo 1 > /sys/class/gpio/gpio$GPIO_NUM/value 2>/dev/null
    done
fi

# 4. Dynamic Driver Rebuild (MicroOS Auto-Healing)
KVER=$(uname -r)
MARKER_FILE="/var/lib/modules-overlay/.built_for_${KVER}"

if [ ! -f "$MARKER_FILE" ]; then
    echo "New kernel detected: $KVER. Rebuilding uConsole drivers..."
    VMLINUX_PATH="/tmp/vmlinux"
    if [ -f "/usr/lib/modules/${KVER}/vmlinux.xz" ]; then
        xz -dc "/usr/lib/modules/${KVER}/vmlinux.xz" > "$VMLINUX_PATH" 2>/dev/null
    fi

    mkdir -p /var/lib/modules-overlay/
    for d in panel-cwu50 ocp8178_bl drm-rp1-dsi uconsole-fixup snd_soc_rp1_aout; do
        SRC_DIR="/usr/local/src/uconsole-drivers/$d"
        if [ -d "$SRC_DIR" ]; then
            cd "$SRC_DIR" || continue
            make clean KERNELRELEASE="$KVER" >/dev/null 2>&1
            if [ -f "$VMLINUX_PATH" ]; then
                make -C "/lib/modules/${KVER}/build" M="$PWD" VMLINUX="$VMLINUX_PATH" modules KBUILD_MODPOST_WARN= >/dev/null 2>&1
            else
                make -C "/lib/modules/${KVER}/build" M="$PWD" modules >/dev/null 2>&1
            fi
            
            MOD_FILE=$(ls *.ko 2>/dev/null | head -n 1)
            if [ -n "$MOD_FILE" ]; then
                cp "$MOD_FILE" /var/lib/modules-overlay/
            fi
        fi
    done
    rm -f "$VMLINUX_PATH"
    # Remove old built modules marker
    rm -f /var/lib/modules-overlay/.built_for_*
    touch "$MARKER_FILE"
    echo "Rebuild complete."
fi

# 5. Driver Initialization
for ko in /var/lib/modules-overlay/*.ko; do [ -f "$ko" ] && chcon -t modules_object_t "$ko" 2>/dev/null; done

load_module() {
    local mod_name="$1"
    local mod_file_name="${mod_name//_/-}.ko"
    local alt_mod_file_name="${mod_name//-/_}.ko"
    if /usr/sbin/modprobe "$mod_name" 2>/dev/null; then return 0; fi
    for f in "$mod_file_name" "$alt_mod_file_name"; do
        local p="/var/lib/modules-overlay/$f"
        if [ -f "$p" ]; then if /usr/sbin/insmod "$p" 2>/dev/null; then return 0; fi; fi
    done
    return 1
}

load_module drm_dma_helper
load_module panel_cwu50
load_module drm_rp1_dsi
if load_module ocp8178_bl; then /usr/sbin/rmmod ocp8178_bl 2>/dev/null; load_module ocp8178_bl; fi
/usr/sbin/modprobe industrialio 2>/dev/null
/usr/sbin/modprobe axp20x_adc 2>/dev/null

load_module uconsole_fixup

# With clockworkpi-uconsole-cm5-stable overlay, kernel instantiates them natively.
# Keep as fallback for older overlays.
/usr/sbin/modprobe axp20x_ac_power 2>/dev/null
/usr/sbin/modprobe axp20x_battery 2>/dev/null
load_module snd_soc_rp1_aout

for b in /sys/class/backlight/*/brightness; do
    [ -f "$b" ] && echo 8 > "$b" 2>/dev/null
done
exit 0
