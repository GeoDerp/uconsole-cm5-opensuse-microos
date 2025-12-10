#!/bin/bash
# Configure AXP221 power button (PEK) for hardware shutdown
# Must unbind driver first since it claims the I2C address

AXP_BUS=13
AXP_ADDR=0x34
PEK_REG=0x36
DRIVER_PATH="/sys/bus/i2c/drivers/axp20x-i2c"
DEVICE="13-0034"

# Unbind the AXP driver to release I2C address
if [ -e "$DRIVER_PATH/$DEVICE" ]; then
    echo "$DEVICE" > "$DRIVER_PATH/unbind" 2>/dev/null
    sleep 0.2
fi

# Read current PEK register value
current=$(/usr/sbin/i2cget -y ${AXP_BUS} ${AXP_ADDR} ${PEK_REG})
# Clear bits 0-1 to set 4-second power button shutdown
new_val=$((current & 0xFC))
/usr/sbin/i2cset -y ${AXP_BUS} ${AXP_ADDR} ${PEK_REG} ${new_val}
logger -t axp221-pek "Configured power button: 4-second hardware shutdown (was $current, now $new_val)"

# Rebind the driver
echo "$DEVICE" > "$DRIVER_PATH/bind" 2>/dev/null || true
