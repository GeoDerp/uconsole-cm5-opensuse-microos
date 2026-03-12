#!/bin/bash
# uConsole Power and Idle Monitor
# Handles low battery warnings, critical shutdown, and inactivity shutdown

# Thresholds
WARNING_BATTERY_THRESHOLD=15  # 15 percent
WARNING_VOLTAGE=3650          # 3.65V
LOW_BATTERY_THRESHOLD=8       # 8 percent
CRITICAL_VOLTAGE=3550         # 3.55V
IDLE_TIMEOUT=600              # 10 minutes in seconds

AXP_BUS=15
AXP_ADDR=0x34

get_battery_info() {
    # Read Voltage (Reg 0x78, 0x79)
    # Correct registers found in uconsole-battery.sh
    MSB=$(/usr/sbin/i2cget -f -y $AXP_BUS $AXP_ADDR 0x78 2>/dev/null)
    LSB=$(/usr/sbin/i2cget -f -y $AXP_BUS $AXP_ADDR 0x79 2>/dev/null)
    if [ -n "$MSB" ] && [ -n "$LSB" ]; then
        BIN=$(( (($MSB << 4) | ($LSB & 0x0F)) ))
        MV=$(( $BIN * 11 / 10 ))
        
        # Estimate Percentage (3.5V to 4.1V range)
        PERC=$(( ($MV - 3500) * 100 / (4100 - 3500) ))
        [ $PERC -gt 100 ] && PERC=100
        [ $PERC -lt 0 ] && PERC=0
        echo "$PERC $MV"
    else
        echo "ERR ERR"
    fi
}

check_charging() {
    STATUS_REG=$(/usr/sbin/i2cget -f -y $AXP_BUS $AXP_ADDR 0x01 2>/dev/null)
    # Bit 6 is charging status
    CHARGING=$(( ($STATUS_REG >> 6) & 1 ))
    echo $CHARGING
}

IDLE_COUNT=0
LAST_WARNING=0

while true; do
    read PERC MV < <(get_battery_info)
    CHARGING=$(check_charging)
    
    if [ "$PERC" != "ERR" ]; then
        # 1. Critical Shutdown (Immediate action)
        if [ $CHARGING -eq 0 ] && ([ $PERC -le $LOW_BATTERY_THRESHOLD ] || [ $MV -le $CRITICAL_VOLTAGE ]); then
            echo "!!! CRITICAL BATTERY ($PERC%, ${MV}mV) !!! System shutting down NOW to prevent hardware lock." | wall
            /usr/local/sbin/uconsole-poweroff.sh
            exit 0
        fi

        # 2. Low Battery Warning (Every 5 minutes)
        if [ $CHARGING -eq 0 ] && ([ $PERC -le $WARNING_BATTERY_THRESHOLD ] || [ $MV -le $WARNING_VOLTAGE ]); then
            CURRENT_TIME=$(date +%s)
            if [ $((CURRENT_TIME - LAST_WARNING)) -ge 300 ]; then
                echo "--- WARNING: uConsole Battery Low ($PERC%, ${MV}mV) --- Please connect power soon." | wall
                # If sway is running, attempt a desktop notification
                if pgrep -x "sway" >/dev/null; then
                    USER_ID=$(pgrep -u geo sway | head -n 1)
                    if [ -n "$USER_ID" ]; then
                        sudo -u geo DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus notify-send -u critical "Battery Low" "Voltage: ${MV}mV ($PERC%). Please plug in!" 2>/dev/null
                    fi
                fi
                LAST_WARNING=$CURRENT_TIME
            fi
        fi
    fi

    # 3. Inactivity Shutdown
    # Check if screen is blanked
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
