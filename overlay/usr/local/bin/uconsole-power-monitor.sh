#!/bin/bash
# uConsole Power and Idle Monitor
# Handles low battery warnings, critical 5-minute shutdown countdown, and inactivity shutdown

# Thresholds
WARNING_VOLTAGE=3650          # 3.65V (~15%)
CRITICAL_VOLTAGE=3550         # 3.55V (~0%, brownout threshold)
IDLE_TIMEOUT=600              # 10 minutes in seconds

AXP_BUS=15
AXP_ADDR=0x34

# Try dynamic bus again if needed
AXP_BUS=$(/usr/sbin/i2cdetect -l 2>/dev/null | grep -m1 'i2c0if\|i2c-gpio\|f00000002.i2c' | cut -f1 | cut -d- -f2)
[ -z "$AXP_BUS" ] && AXP_BUS=13

get_battery_info() {
    # Try sysfs first (fuel gauge driver)
    if [ -f "/sys/class/power_supply/axp20x-battery/capacity" ]; then
        PERC=$(cat /sys/class/power_supply/axp20x-battery/capacity)
        MV=$(cat /sys/class/power_supply/axp20x-battery/voltage_now 2>/dev/null)
        if [ -n "$MV" ]; then
            MV=$((MV / 1000)) # microvolts to millivolts
        else
            MV=0
        fi
        echo "$PERC $MV"
        return
    fi

    # Fallback to I2C if driver is missing
    MSB=$(/usr/sbin/i2cget -f -y $AXP_BUS $AXP_ADDR 0x78 2>/dev/null)
    LSB=$(/usr/sbin/i2cget -f -y $AXP_BUS $AXP_ADDR 0x79 2>/dev/null)
    if [ -n "$MSB" ] && [ -n "$LSB" ]; then
        BIN=$(( (($MSB << 4) | ($LSB & 0x0F)) ))
        MV=$(( $BIN * 11 / 10 ))
        # Scale percentage based on 3.55V brownout threshold
        PERC=$(( ($MV - 3550) * 100 / (4200 - 3550) ))
        [ $PERC -gt 100 ] && PERC=100
        [ $PERC -lt 0 ] && PERC=0
        echo "$PERC $MV"
    else
        echo "ERR ERR"
    fi
}

check_charging() {
    # Try sysfs first
    if [ -f "/sys/class/power_supply/axp20x-battery/status" ]; then
        STATUS=$(cat /sys/class/power_supply/axp20x-battery/status)
        if [ "$STATUS" = "Charging" ]; then
            echo 1
            return
        fi
        echo 0
        return
    fi

    # Fallback to I2C
    STATUS_REG=$(/usr/sbin/i2cget -f -y $AXP_BUS $AXP_ADDR 0x01 2>/dev/null)
    if [ -n "$STATUS_REG" ]; then
        CHARGING=$(( ($STATUS_REG >> 6) & 1 ))
        echo $CHARGING
        return
    fi
    echo 0
}

send_notification() {
    local msg="$1"
    if pgrep -x "sway" >/dev/null; then
        USER_ID=$(pgrep -u geo sway | head -n 1)
        if [ -n "$USER_ID" ]; then
            sudo -u geo DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus notify-send -u critical "uConsole Power" "$msg" 2>/dev/null
        fi
    fi
}

IDLE_COUNT=0
LAST_WARNING=0
CRITICAL_SHUTDOWN_TIMER=0
SHUTDOWN_DELAY=300 # 5 minutes

while true; do
    read PERC MV < <(get_battery_info)
    CHARGING=$(check_charging)
    
    if [ "$PERC" != "ERR" ]; then
        # 1. Critical Shutdown Countdown (0% or 3.55V)
        if [ $CHARGING -eq 0 ] && ([ "$PERC" -le 0 ] || [ "$MV" -le $CRITICAL_VOLTAGE ]); then
            if [ $CRITICAL_SHUTDOWN_TIMER -eq 0 ]; then
                CRITICAL_SHUTDOWN_TIMER=$SHUTDOWN_DELAY
                echo "CRITICAL BATTERY: Initiating 5-minute shutdown countdown." | wall
            fi
            
            # Send visual warning every minute during countdown
            if [ $((CRITICAL_SHUTDOWN_TIMER % 60)) -eq 0 ]; then
                MINUTES=$((CRITICAL_SHUTDOWN_TIMER / 60))
                send_notification "Battery at $PERC% (${MV}mV)! Shutting down in $MINUTES minute(s) to prevent hardware lock. PLUG IN NOW!"
            fi
            
            CRITICAL_SHUTDOWN_TIMER=$((CRITICAL_SHUTDOWN_TIMER - 60))
            
            if [ $CRITICAL_SHUTDOWN_TIMER -lt 0 ]; then
                echo "CRITICAL BATTERY LIMIT REACHED. Shutting down." | wall
                /usr/local/sbin/uconsole-poweroff.sh
                exit 0
            fi
        else
            # Reset timer if charging resumes or battery magically recovers
            if [ $CRITICAL_SHUTDOWN_TIMER -gt 0 ]; then
                CRITICAL_SHUTDOWN_TIMER=0
                send_notification "Charging detected. Shutdown countdown cancelled."
            fi

            # 2. Standard Low Battery Warning (Every 5 minutes)
            if [ $CHARGING -eq 0 ] && ([ "$PERC" -le 15 ] || [ "$MV" -le $WARNING_VOLTAGE ]); then
                CURRENT_TIME=$(date +%s)
                if [ $((CURRENT_TIME - LAST_WARNING)) -ge 300 ]; then
                    send_notification "Battery Low ($PERC%, ${MV}mV). Please connect power soon."
                    LAST_WARNING=$CURRENT_TIME
                fi
            fi
        fi
    fi

    # 3. Inactivity Shutdown
    if [ $CHARGING -eq 0 ]; then
        if grep -q 1 /sys/class/graphics/fb0/blank 2>/dev/null; then
            IDLE_COUNT=$((IDLE_COUNT + 60))
        else
            IDLE_COUNT=0
        fi
    else
        IDLE_COUNT=0
    fi

    if [ $IDLE_COUNT -ge $IDLE_TIMEOUT ]; then
        echo "uConsole: 10 minutes of inactivity on battery. Shutting down." | wall
        /usr/local/sbin/uconsole-poweroff.sh
        exit 0
    fi

    sleep 60
done