#!/bin/bash
# AXP221 PMIC poweroff via I2C
# Must unbind driver first since it claims the I2C address

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

# Unbind the AXP driver to release I2C address
if [ -e "$DRIVER_PATH/$DEVICE" ]; then
    echo "$DEVICE" > "$DRIVER_PATH/unbind" 2>/dev/null
    sleep 0.2
fi

# Issue poweroff command to AXP221
/usr/sbin/i2cset -y ${AXP_BUS} ${AXP_ADDR} ${OFF_CTRL_REG} ${OFF_BIT}

# Should not reach here - PMIC should have cut power
sleep 5
logger -t axp221-poweroff "WARNING: Power-off command sent but system still running!"
