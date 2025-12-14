#!/bin/bash
# AXP221 PMIC poweroff via I2C
# Unbind drivers to release I2C address

# Ensure i2c-dev is loaded
/usr/sbin/modprobe i2c-dev 2>/dev/null

AXP_BUS=13
AXP_ADDR=0x34
OFF_CTRL_REG=0x32
OFF_BIT=0x80
DRIVER_PATH="/sys/bus/i2c/drivers/axp20x-i2c"
DEVICE="13-0034"

# Sync filesystems first
sync
sync

# Log the poweroff attempt
logger -t axp221-poweroff "Triggering AXP221 hardware power-off via I2C"

# 1. Unbind Regulator child first (if present)
if [ -d /sys/bus/platform/drivers/axp20x-regulator ]; then
    for child in /sys/bus/platform/drivers/axp20x-regulator/axp20x-regulator.*; do
        if [ -e "$child" ]; then
            dev=$(basename "$child")
            echo "$dev" > /sys/bus/platform/drivers/axp20x-regulator/unbind 2>/dev/null
        fi
    done
fi

# 2. Unbind Parent I2C driver
if [ -e "$DRIVER_PATH/$DEVICE" ]; then
    echo "$DEVICE" > "$DRIVER_PATH/unbind" 2>/dev/null
    sleep 0.2
fi

# Issue poweroff command to AXP221
# Force access with -f
/usr/sbin/i2cset -f -y ${AXP_BUS} ${AXP_ADDR} ${OFF_CTRL_REG} ${OFF_BIT}

# Should not reach here - PMIC should have cut power
sleep 5
logger -t axp221-poweroff "WARNING: Power-off command sent but system still running!"
