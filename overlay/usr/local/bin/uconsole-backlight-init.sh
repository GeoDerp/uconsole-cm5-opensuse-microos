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

# Load dependencies
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

# Reload Display Drivers
# We must reload because we cut power to the panel
echo "Reloading display drivers..."
/usr/sbin/rmmod drm_rp1_dsi panel_cwu50 2>/dev/null
sleep 0.5

# Manually toggle Panel Reset (GPIO 648) while drivers are unloaded
# This ensures the panel enters a known state before the driver probes
if [ -d /sys/class/gpio ]; then
    echo 648 > /sys/class/gpio/export 2>/dev/null
    if [ -d /sys/class/gpio/gpio648 ]; then
        echo out > /sys/class/gpio/gpio648/direction 2>/dev/null
        # Assert Reset (Physical Low)
        echo 0 > /sys/class/gpio/gpio648/value 2>/dev/null
        sleep 0.2
        # De-assert Reset (Physical High)
        echo 1 > /sys/class/gpio/gpio648/value 2>/dev/null
        sleep 0.2
        echo 648 > /sys/class/gpio/unexport 2>/dev/null
    fi
fi

/usr/sbin/insmod /var/lib/modules-overlay/panel-cwu50.ko
sleep 0.2
/usr/sbin/insmod /var/lib/modules-overlay/drm_rp1_dsi.ko
sleep 0.5

# Failsafe: Force Backlight GPIO High (GPIO 9 on RP1 / gpio649)
# This loop ensures we don't give up if the driver fights back
MAX_RETRIES=3
for i in $(seq 1 $MAX_RETRIES); do
    echo "Attempt $i to force Backlight GPIO High..."
    
    # 1. Unbind driver
    if [ -d /sys/bus/platform/drivers/ocp8178-backlight ]; then
        echo backlight@0 > /sys/bus/platform/drivers/ocp8178-backlight/unbind 2>/dev/null
    fi
    sleep 0.2
    
    # 2. Force GPIO
    echo 649 > /sys/class/gpio/export 2>/dev/null
    if [ -d /sys/class/gpio/gpio649 ]; then
        echo out > /sys/class/gpio/gpio649/direction 2>/dev/null
        echo 1 > /sys/class/gpio/gpio649/value 2>/dev/null
        echo 649 > /sys/class/gpio/unexport 2>/dev/null
    fi
    
    # 3. Rebind driver
    if [ -d /sys/bus/platform/drivers/ocp8178-backlight ]; then
        echo backlight@0 > /sys/bus/platform/drivers/ocp8178-backlight/bind 2>/dev/null
    fi
    sleep 0.5
    
    # 4. Verify
    GPIO_STATE=$(grep "gpio-9" /sys/kernel/debug/gpio 2>/dev/null)
    if echo "$GPIO_STATE" | grep -q "out hi"; then
        echo "Backlight GPIO verified High."
        break
    else
        echo "Backlight GPIO still failed ($GPIO_STATE). Retrying..."
    fi
done

# Set brightness
if [ -e /sys/class/backlight/backlight@0/brightness ]; then
    echo 8 > /sys/class/backlight/backlight@0/brightness 2>/dev/null
fi

# Bind framebuffer console
if [ -e /sys/class/vtconsole/vtcon1/bind ]; then
    echo 1 > /sys/class/vtconsole/vtcon1/bind 2>/dev/null
fi

exit 0