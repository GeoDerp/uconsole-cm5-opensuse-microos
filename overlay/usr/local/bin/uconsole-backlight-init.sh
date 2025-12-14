#!/bin/bash
# uConsole display and backlight initialization
# This script is run at boot by uconsole-backlight.service
set -x

# Fix SELinux context for custom modules (MicroOS has SELinux)
for ko in /var/lib/modules-overlay/*.ko; do
    [ -f "$ko" ] && chcon -t modules_object_t "$ko" 2>/dev/null
done

# Power cycle the display regulator (ALDO2) to ensure clean state
# ALDO2 is bit 2 of register 0x10 on AXP221
# 0x10: [7]ALDO1 [6]dldo4 [5]dldo3 [4]dldo2 [3]dldo1 [2]aldo2 [1]dcdc5 [0]dc1sw
# We read, clear bit 2, write, sleep, set bit 2, write.
# Use i2cget/i2cset. Driver must be unbound from 0x34 first.

if [ -d /sys/bus/i2c/drivers/axp20x-i2c ]; then
    echo "13-0034" > /sys/bus/i2c/drivers/axp20x-i2c/unbind 2>/dev/null
fi

VAL=$(i2cget -y -f 13 0x34 0x10)
# Clear bit 2 (0xFB mask)
OFF_VAL=$(printf "0x%X" $(( $VAL & 0xFB )))
# Set bit 2 (0x04 mask)
ON_VAL=$(printf "0x%X" $(( $VAL | 0x04 )))

echo "Power cycling display (ALDO2)..."
i2cset -y -f 13 0x34 0x10 $OFF_VAL
sleep 1
i2cset -y -f 13 0x34 0x10 $ON_VAL
sleep 0.5

# Rebind AXP driver
echo "13-0034" > /sys/bus/i2c/drivers/axp20x-i2c/bind 2>/dev/null

# Load AXP and IndustrialIO drivers (required for power management)
modprobe industrialio 2>/dev/null
modprobe axp20x_adc 2>/dev/null
insmod /var/lib/modules-overlay/axp20x_ac_power.ko 2>/dev/null
insmod /var/lib/modules-overlay/axp20x_battery.ko 2>/dev/null

# Reload display drivers to force initialization
# This fixes the "backlight on, black screen" issue by ensuring the DSI link is reset
echo "Reloading display drivers..."
rmmod drm_rp1_dsi panel_cwu50 2>/dev/null
sleep 0.5
insmod /var/lib/modules-overlay/panel-cwu50.ko
sleep 0.2
insmod /var/lib/modules-overlay/drm-rp1-dsi.ko
sleep 0.5

# Load backlight driver if not loaded
if ! lsmod | grep -q ocp8178_bl; then
    modprobe ocp8178_bl 2>/dev/null || insmod /var/lib/modules-overlay/ocp8178_bl.ko 2>/dev/null
fi

# Failsafe: Manually force Backlight GPIO (GPIO 9 on RP1 / gpio649) High
# The driver sometimes leaves it as Input Low. We unbind, force High, then rebind.
if [ -d /sys/class/gpio ]; then
    # Unbind driver to release GPIO
    if [ -d /sys/bus/platform/drivers/ocp8178-backlight ]; then
        echo backlight@0 > /sys/bus/platform/drivers/ocp8178-backlight/unbind 2>/dev/null
    fi
    
    # Export and force High
    echo 649 > /sys/class/gpio/export 2>/dev/null
    if [ -d /sys/class/gpio/gpio649 ]; then
        echo out > /sys/class/gpio/gpio649/direction 2>/dev/null
        echo 1 > /sys/class/gpio/gpio649/value 2>/dev/null
        # Release GPIO for driver
        echo 649 > /sys/class/gpio/unexport 2>/dev/null
    fi
    
    # Rebind driver
    if [ -d /sys/bus/platform/drivers/ocp8178-backlight ]; then
        echo backlight@0 > /sys/bus/platform/drivers/ocp8178-backlight/bind 2>/dev/null
    fi
fi

# Wait for backlight device to appear
count=0
while [ ! -e /sys/class/backlight/backlight@0/brightness ] && [ $count -lt 30 ]; do
    sleep 0.5
    count=$((count + 1))
done

# Set brightness to trigger GPIO output mode and illuminate display
# The OCP8178 driver needs a brightness write to properly set GPIO direction
if [ -e /sys/class/backlight/backlight@0/brightness ]; then
    echo 8 > /sys/class/backlight/backlight@0/brightness 2>/dev/null
fi

# Bind framebuffer console to DRM display
# This enables text console output on the display
if [ -e /sys/class/vtconsole/vtcon1/bind ]; then
    echo 1 > /sys/class/vtconsole/vtcon1/bind 2>/dev/null
fi

exit 0
