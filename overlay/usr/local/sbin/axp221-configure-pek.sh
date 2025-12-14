#!/bin/bash
# Configure AXP221 power button (PEK) for hardware shutdown
# Unbind driver to release I2C address, then force write.

# Ensure i2c-dev is loaded
/usr/sbin/modprobe i2c-dev 2>/dev/null

AXP_BUS=13
AXP_ADDR=0x34
PEK_REG=0x36
DRIVER_PATH="/sys/bus/i2c/drivers/axp20x-i2c"
DEVICE="13-0034"

# Unbind the AXP driver for this specific device only
if [ -e "$DRIVER_PATH/$DEVICE" ]; then
    echo "$DEVICE" > "$DRIVER_PATH/unbind" 2>/dev/null
    sleep 0.2
fi

# Read current PEK register value (Force read)
current=$(/usr/sbin/i2cget -f -y ${AXP_BUS} ${AXP_ADDR} ${PEK_REG})
# Clear bits 0-1 to set 4-second power button shutdown
# Default is often 0x4D or similar. We want to keep other bits but set [1:0] to 00.
# 0xFC mask clears bottom 2 bits.
if [ -n "$current" ]; then
    new_val=$((current & 0xFC))
    /usr/sbin/i2cset -f -y ${AXP_BUS} ${AXP_ADDR} ${PEK_REG} ${new_val}
    logger -t axp221-pek "Configured power button: 4-second hardware shutdown (was $current, now $new_val)"
else
    logger -t axp221-pek "Failed to read PEK register!"
fi

# Rebind the driver
echo "$DEVICE" > "$DRIVER_PATH/bind" 2>/dev/null || true
