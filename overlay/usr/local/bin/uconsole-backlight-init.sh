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

# 4. Driver Initialization
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

if [ -e /sys/class/backlight/backlight@0/brightness ]; then echo 8 > /sys/class/backlight/backlight@0/brightness; fi
exit 0
