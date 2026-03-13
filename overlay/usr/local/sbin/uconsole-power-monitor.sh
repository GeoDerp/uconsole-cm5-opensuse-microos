#!/bin/bash
# Monitors battery voltage/capacity and forces shutdown if critical
# to prevent PMIC/System brownout loops.
#
# Works with two paths:
#  1) Kernel battery driver (via sysfs) — preferred, accurate
#  2) Direct I2C reads — fallback if driver not probed

# Thresholds
CRIT_PERCENT=8
CRIT_VOLT_UV=3550000  # 3.55V
WARN_PERCENT=15
IDLE_TIMEOUT=1800     # 30 minutes in seconds

BAT_PATH="/sys/class/power_supply/axp20x-battery"
FAIL_COUNT=0
IDLE_COUNT=0

# Dynamic I2C bus detection for fallback path
/usr/sbin/modprobe i2c-dev 2>/dev/null
AXP_BUS=$(/usr/sbin/i2cdetect -l 2>/dev/null | grep -m1 'i2c0if\|i2c-gpio\|pmic_i2c\|f00000002.i2c' | cut -f1 | cut -d- -f2)
[ -z "$AXP_BUS" ] && AXP_BUS=13
AXP_ADDR=0x34

logger -t power-monitor "Starting uConsole power monitor (bus=$AXP_BUS)..."

# I2C fallback: read battery voltage directly from AXP221 ADC registers
read_voltage_i2c() {
    local msb lsb bin_val
    msb=$(/usr/sbin/i2cget -f -y "$AXP_BUS" "$AXP_ADDR" 0x78 2>/dev/null)
    lsb=$(/usr/sbin/i2cget -f -y "$AXP_BUS" "$AXP_ADDR" 0x79 2>/dev/null)
    if [ -z "$msb" ] || [ -z "$lsb" ]; then
        echo ""
        return
    fi
    # 1.1mV per bit, convert to μV
    bin_val=$(( (($msb << 4) | ($lsb & 0x0F)) ))
    echo $(( bin_val * 1100 ))
}

# Wait for battery path OR I2C availability (up to 60s)
WAIT_SEC=0
while [ ! -d "$BAT_PATH" ] && [ $WAIT_SEC -lt 60 ]; do
    sleep 5
    WAIT_SEC=$((WAIT_SEC+5))
    logger -t power-monitor "Waiting for battery sensor... ($WAIT_SEC/60s)"
done

USE_SYSFS=0
if [ -d "$BAT_PATH" ]; then
    USE_SYSFS=1
    logger -t power-monitor "Using kernel battery driver (sysfs)"
else
    # Verify I2C fallback works
    test_v=$(read_voltage_i2c)
    if [ -z "$test_v" ]; then
        logger -s -p crit -t power-monitor "FATAL: No battery sensor AND I2C fallback failed. Forcing shutdown."
        sync
        systemctl poweroff
        exit 1
    fi
    logger -t power-monitor "Using I2C fallback for battery monitoring"
fi

while true; do
    STATUS=""
    CAP=""
    VOLT=""

    if [ "$USE_SYSFS" -eq 1 ] && [ -d "$BAT_PATH" ]; then
        STATUS=$(cat "$BAT_PATH/status" 2>/dev/null)
        CAP=$(cat "$BAT_PATH/capacity" 2>/dev/null)
        VOLT=$(cat "$BAT_PATH/voltage_now" 2>/dev/null)
    else
        # I2C fallback path
        VOLT=$(read_voltage_i2c)
        # Check charging status via register 0x01 bit 6
        status_reg=$(/usr/sbin/i2cget -f -y "$AXP_BUS" "$AXP_ADDR" 0x01 2>/dev/null)
        if [ -n "$status_reg" ] && [ $(( ($status_reg >> 6) & 1 )) -eq 1 ]; then
            STATUS="Charging"
        else
            STATUS="Discharging"
        fi
        # Estimate capacity from voltage (3.5V-4.1V linear)
        if [ -n "$VOLT" ]; then
            mv=$(( VOLT / 1000 ))
            CAP=$(( (mv - 3500) * 100 / 600 ))
            [ "$CAP" -gt 100 ] && CAP=100
            [ "$CAP" -lt 0 ] && CAP=0
        fi
    fi

    if [ -z "$STATUS" ] || [ -z "$CAP" ] || [ -z "$VOLT" ]; then
        FAIL_COUNT=$((FAIL_COUNT+1))
        logger -t power-monitor "Warning: Failed to read battery sensor (Attempt $FAIL_COUNT/6)"
        sleep 5
    else
        FAIL_COUNT=0

        if [ "$STATUS" = "Discharging" ]; then
            if [ "$CAP" -le "$CRIT_PERCENT" ] || [ "$VOLT" -lt "$CRIT_VOLT_UV" ]; then
                logger -s -p crit -t power-monitor "CRITICAL BATTERY: ${CAP}% (${VOLT}uV). Shutting down immediately to prevent brownout."

                # Double check to prevent glitch trigger
                sleep 2
                if [ "$USE_SYSFS" -eq 1 ]; then
                    VOLT2=$(cat "$BAT_PATH/voltage_now" 2>/dev/null)
                else
                    VOLT2=$(read_voltage_i2c)
                fi
                if [ -n "$VOLT2" ] && [ "$VOLT2" -lt "$CRIT_VOLT_UV" ]; then
                     sync
                     systemctl poweroff
                     exit 0
                fi
            elif [ "$CAP" -le "$WARN_PERCENT" ]; then
                logger -t power-monitor "Low Battery: ${CAP}%"
            fi
        fi
    fi

    if [ "$FAIL_COUNT" -ge 6 ]; then
        logger -s -p crit -t power-monitor "CRITICAL: Battery sensor lost consistently (Potential hardware deadlock). Forcing shutdown."
        sync
        systemctl poweroff
        exit 0
    fi

    # 4. Inactivity Shutdown
    # Check if screen is blanked via DRM DPMS
    DPMS_STATE=$(cat /sys/class/drm/card0-DSI-1/dpms 2>/dev/null)
    if [ "$DPMS_STATE" = "Off" ]; then
        IDLE_COUNT=$((IDLE_COUNT + 30))
    else
        IDLE_COUNT=0
    fi

    if [ "$IDLE_COUNT" -ge "$IDLE_TIMEOUT" ]; then
        logger -s -p crit -t power-monitor "30 minutes of inactivity detected (screen off). Shutting down as alternative to sleep."
        sync
        /usr/local/sbin/axp221-poweroff.sh
        exit 0
    fi
    
    sleep 30
done