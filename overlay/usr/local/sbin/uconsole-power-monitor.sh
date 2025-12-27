#!/bin/bash
# Monitors battery voltage/capacity and forces shutdown if critical
# to prevent PMIC/System brownout loops.

# Thresholds
CRIT_PERCENT=8
CRIT_VOLT_UV=3550000  # 3.55V
WARN_PERCENT=15

BAT_PATH="/sys/class/power_supply/axp20x-battery"
FAIL_COUNT=0

logger -t power-monitor "Starting uConsole power monitor..."

# Wait for battery path to appear (up to 120s)
WAIT_SEC=0
while [ ! -d "$BAT_PATH" ] && [ $WAIT_SEC -lt 120 ]; do
    sleep 5
    WAIT_SEC=$((WAIT_SEC+5))
    logger -t power-monitor "Waiting for battery sensor... ($WAIT_SEC/120s)"
done

if [ ! -d "$BAT_PATH" ]; then
    logger -s -p crit -t power-monitor "FATAL: Battery sensor not found after timeout. Forcing shutdown for safety."
    sync
    systemctl poweroff
    exit 1
fi

while true; do
    if [ -d "$BAT_PATH" ]; then
        STATUS=$(cat "$BAT_PATH/status" 2>/dev/null)
        CAP=$(cat "$BAT_PATH/capacity" 2>/dev/null)
        VOLT=$(cat "$BAT_PATH/voltage_now" 2>/dev/null)

        if [ -z "$STATUS" ] || [ -z "$CAP" ]; then
            FAIL_COUNT=$((FAIL_COUNT+1))
            logger -t power-monitor "Warning: Failed to read battery sensor (Attempt $FAIL_COUNT/6)"
            sleep 5 # Extra delay to let I2C bus recover
        else
            FAIL_COUNT=0 # Reset counter on success

            if [ "$STATUS" == "Discharging" ]; then
                if [ "$CAP" -le "$CRIT_PERCENT" ] || [ "$VOLT" -lt "$CRIT_VOLT_UV" ]; then
                    logger -s -p crit -t power-monitor "CRITICAL BATTERY: ${CAP}% (${VOLT}uV). Shutting down immediately to prevent brownout."
                    
                    # Double check to prevent glitch trigger
                    sleep 2
                    VOLT2=$(cat "$BAT_PATH/voltage_now" 2>/dev/null)
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
    else
        FAIL_COUNT=$((FAIL_COUNT+1))
        logger -t power-monitor "Battery device not found! (Attempt $FAIL_COUNT/6)"
    fi

    if [ "$FAIL_COUNT" -ge 6 ]; then
        logger -s -p crit -t power-monitor "CRITICAL: Battery sensor lost consistently (Potential hardware deadlock). Forcing shutdown."
        sync
        systemctl poweroff
        exit 0
    fi
    
    sleep 30
done