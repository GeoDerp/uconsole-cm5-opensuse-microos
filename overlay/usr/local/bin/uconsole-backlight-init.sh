#!/bin/bash
# uConsole display and backlight initialization
# This script is run at boot by uconsole-backlight.service
set -x

# Ensure i2c-dev is loaded for power cycling
/usr/sbin/modprobe i2c-dev 2>/dev/null

# Fix SELinux context for custom modules (MicroOS has SELinux)
for ko in /var/lib/modules-overlay/*.ko; do
    [ -f "$ko" ] && chcon -t modules_object_t "$ko" 2>/dev/null
done

# Load dependencies (AXP drivers) - other modules handled by modprobe.d
/usr/sbin/modprobe industrialio 2>/dev/null
/usr/sbin/modprobe axp20x_adc 2>/dev/null
/usr/sbin/insmod /var/lib/modules-overlay/axp20x_ac_power.ko 2>/dev/null
/usr/sbin/insmod /var/lib/modules-overlay/axp20x_battery.ko 2>/dev/null

# Power Cycle Display (ALDO2)
# Unbind AXP driver first to release I2C address
if [ -d /sys/bus/i2c/drivers/axp20x-i2c ]; then
    echo "13-0034" > /sys/bus/i2c/drivers/axp20x-i2c/unbind 2>/dev/null
fi

# Toggle ALDO2
VAL=$(/usr/sbin/i2cget -y -f 13 0x34 0x10)
# Clear bit 2 (0xFB mask)
OFF_VAL=$(printf "0x%X" $(( $VAL & 0xFB )))
# Set bit 2 (0x04 mask)
ON_VAL=$(printf "0x%X" $(( $VAL | 0x04 )))

echo "Power cycling display (ALDO2)..."
/usr/sbin/i2cset -y -f 13 0x34 0x10 $OFF_VAL
sleep 1
/usr/sbin/i2cset -y -f 13 0x34 0x10 $ON_VAL
sleep 0.5

# Rebind AXP driver
echo "13-0034" > /sys/bus/i2c/drivers/axp20x-i2c/bind 2>/dev/null

# Set brightness - assuming backlight driver will load and create device
if [ -e /sys/class/backlight/backlight@0/brightness ]; then
    echo 8 > /sys/class/backlight/backlight@0/brightness 2>/dev/null
fi

# Bind framebuffer console
if [ -e /sys/class/vtconsole/vtcon1/bind ]; then
    echo 1 > /sys/class/vtconsole/vtcon1/bind 2>/dev/null
fi

exit 0