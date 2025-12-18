#!/bin/bash
# uConsole CM5 Battery Monitor for Waybar
# Reads raw I2C data from AXP221 PMIC

AXP_BUS=13
AXP_ADDR=0x34

# Read Voltage (Reg 0x78, 0x79)
MSB=$(/usr/sbin/i2cget -f -y $AXP_BUS $AXP_ADDR 0x78 2>/dev/null)
LSB=$(/usr/sbin/i2cget -f -y $AXP_BUS $AXP_ADDR 0x79 2>/dev/null)

if [ -z "$MSB" ] || [ -z "$LSB" ]; then
    echo '{"text": "err", "tooltip": "I2C Read Failed", "class": "error"}'
    exit 0
fi

# Convert to mV (1.1mV per bit)
BIN=$(( (($MSB << 4) | ($LSB & 0x0F)) ))
MV=$(( $BIN * 11 / 10 ))

# Estimate Percentage (3.5V to 4.1V range)
MIN=3500
MAX=4100
PERC=$(( ($MV - $MIN) * 100 / ($MAX - $MIN) ))

[ $PERC -gt 100 ] && PERC=100
[ $PERC -lt 0 ] && PERC=0

# Check Charging Status (Reg 0x01 bit 6)
STATUS_REG=$(/usr/sbin/i2cget -f -y $AXP_BUS $AXP_ADDR 0x01 2>/dev/null)
CHARGING=$(( ($STATUS_REG >> 6) & 1 ))

# Check Power Source (Reg 0x00)
# Bit 7: ACIN Present, Bit 5: VBUS Present
PWR_SRC_REG=$(/usr/sbin/i2cget -f -y $AXP_BUS $AXP_ADDR 0x00 2>/dev/null)
ACIN=$(( ($PWR_SRC_REG >> 7) & 1 ))
VBUS=$(( ($PWR_SRC_REG >> 5) & 1 ))
PLUGGED=$(( $ACIN | $VBUS ))

if [ $CHARGING -eq 1 ]; then
    ICON="↑"
    CLASS="charging"
elif [ $PLUGGED -eq 1 ]; then
    ICON="●"
    CLASS="plugged"
else
    ICON="▮"
    CLASS="discharging"
fi

# Determine warning levels
[ $PERC -le 30 ] && CLASS="${CLASS} warning"
[ $PERC -le 15 ] && CLASS="${CLASS} critical"

# Return JSON with capacity for compatibility
echo "{\"text\": \"${PERC}% ${ICON}\", \"tooltip\": \"Voltage: ${MV}mV\", \"class\": \"${CLASS}\", \"percentage\": ${PERC}, \"capacity\": ${PERC}}"
