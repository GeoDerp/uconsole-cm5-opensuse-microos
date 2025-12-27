#!/bin/bash
# uConsole display and backlight initialization
# This script is run at boot by uconsole-backlight.service
set -x

# Ensure i2c-dev is loaded
/usr/sbin/modprobe i2c-dev 2>/dev/null

# Fix SELinux context for custom modules (MicroOS has SELinux)
for ko in /var/lib/modules-overlay/*.ko; do
    [ -f "$ko" ] && chcon -t modules_object_t "$ko" 2>/dev/null
done

# Function to robustly load modules (fallback to insmod from overlay)
load_module() {
    local mod_name="$1"
    # Normalize name (replace - with _)
    local mod_file_name="${mod_name//-/_}.ko"
    
    echo "Attempting to load $mod_name..."
    
    if /usr/sbin/modprobe "$mod_name" 2>/dev/null; then
        echo "  Loaded via modprobe."
        return 0
    fi
    
    echo "  modprobe failed. Trying insmod from overlay..."
    local overlay_path="/var/lib/modules-overlay/$mod_file_name"
    
    if [ -f "$overlay_path" ]; then
        if /usr/sbin/insmod "$overlay_path" 2>/dev/null; then
            echo "  Loaded via insmod ($overlay_path)."
            return 0
        else
            echo "  Failed to insmod $overlay_path."
        fi
    else
        echo "  Overlay file not found: $overlay_path"
    fi
    return 1
}

# Power Cycle Display (ALDO2) - Force regulator toggle via I2C to reset panel
# This is required because the panel controller needs a hard voltage reset
# and regulator_enable() is a no-op if already on.
VAL=$(/usr/sbin/i2cget -y -f 13 0x34 0x10 2>/dev/null)
if [ -n "$VAL" ]; then
    # Clear bit 2 (0xFB mask)
    OFF_VAL=$(printf "0x%X" $(( $VAL & 0xFB )))
    # Set bit 2 (0x04 mask)
    ON_VAL=$(printf "0x%X" $(( $VAL | 0x04 )))

    echo "Power cycling display (ALDO2)..."
    /usr/sbin/i2cset -y -f 13 0x34 0x10 $OFF_VAL
    sleep 1
    /usr/sbin/i2cset -y -f 13 0x34 0x10 $ON_VAL
    sleep 0.5
else
    echo "WARNING: Failed to read PMIC via I2C. Skipping power cycle."
fi

# Explicitly load display and backlight drivers
echo "Loading display drivers (First to ensure regulators work)..."
load_module panel_cwu50
load_module drm_rp1_dsi

# Load backlight driver (OCP8178) with reload workaround
if load_module ocp8178_bl; then
    echo "Reloading ocp8178_bl to fix desync..."
    /usr/sbin/rmmod ocp8178_bl 2>/dev/null
    load_module ocp8178_bl
fi

# Allow display init to settle before stressing I2C with battery polling
sleep 2

echo "Loading AXP and Fixup drivers..."
/usr/sbin/modprobe industrialio 2>/dev/null
/usr/sbin/modprobe axp20x_adc 2>/dev/null

# Load fixup module to instantiate AXP221 children (ADC, Battery)
load_module uconsole_fixup

# Load Battery Drivers
/usr/sbin/modprobe axp20x_ac_power 2>/dev/null
/usr/sbin/modprobe axp20x_battery 2>/dev/null

# Load Audio Drivers
/usr/sbin/modprobe snd_soc_simple_card 2>/dev/null
load_module snd_soc_rp1_aout

# Set brightness - assuming backlight driver will load and create device
if [ -e /sys/class/backlight/backlight@0/brightness ]; then
    echo 8 > /sys/class/backlight/backlight@0/brightness 2>/dev/null
fi

# Bind framebuffer console
if [ -e /sys/class/vtconsole/vtcon1/bind ]; then
    echo 1 > /sys/class/vtconsole/vtcon1/bind 2>/dev/null
fi

exit 0
