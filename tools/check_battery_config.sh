#!/bin/bash
# Check and Fix AXP221 Battery Shutdown Threshold
# Usage: sudo ./check_battery_config.sh

AXP_BUS=13
AXP_ADDR=0x34
VOFF_REG=0x31

# Ensure i2c-dev loaded
modprobe i2c-dev

echo "=== AXP221 Battery Diagnostics ==="

# 1. Check Current Voltage
if [ -d /sys/class/power_supply/axp20x-battery ]; then
    VOLT=$(cat /sys/class/power_supply/axp20x-battery/voltage_now)
    echo "Current Battery Voltage: $((VOLT / 1000)) mV"
    STATUS=$(cat /sys/class/power_supply/axp20x-battery/status)
    echo "Charging Status: $STATUS"
else
    echo "Battery driver not loaded."
fi

# 2. Check Shutdown Threshold (V_OFF)
# Reg 0x31: [2:0]
# 000=2.6V, 001=2.7V, 010=2.8V, 011=2.9V, 100=3.0V, 101=3.1V, 110=3.2V, 111=3.3V
VAL=$(i2cget -f -y $AXP_BUS $AXP_ADDR $VOFF_REG)
if [ -n "$VAL" ]; then
    LEVEL=$((VAL & 0x07))
    echo "Current V_OFF Register (0x31): $VAL (Level: $LEVEL)"
    
    case $LEVEL in
        0) V="2.6V";; 1) V="2.7V";; 2) V="2.8V";; 3) V="2.9V";;
        4) V="3.0V";; 5) V="3.1V";; 6) V="3.2V";; 7) V="3.3V";;
    esac
    echo "Shutdown Threshold: $V"

    # Fix if too high (> 3.0V)
    if [ "$LEVEL" -gt 4 ]; then
        echo "WARNING: Threshold is too high ($V). Setting to 3.0V (Level 4)..."
        # Keep other bits, set 2:0 to 100 (4)
        NEW_VAL=$(( (VAL & 0xF8) | 0x04 ))
        i2cset -f -y $AXP_BUS $AXP_ADDR $VOFF_REG $NEW_VAL
        echo "Fixed. New Register Value: $(i2cget -f -y $AXP_BUS $AXP_ADDR $VOFF_REG)"
    else
        echo "Threshold is safe."
    fi
else
    echo "Failed to read PMIC."
fi
echo "=================================="
