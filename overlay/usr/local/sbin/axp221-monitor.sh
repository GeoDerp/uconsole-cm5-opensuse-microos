#!/bin/bash
# Monitor AXP221 for Power Button Tap (Short Press) via I2C polling
# Required because hardware IRQ line is disabled in device tree.

/usr/sbin/modprobe i2c-dev 2>/dev/null

# Dynamic bus detection — bus number varies between boots (13 or 15)
AXP_BUS=$(/usr/sbin/i2cdetect -l 2>/dev/null | grep -m1 'i2c0if\|i2c-gpio\|f00000002.i2c' | cut -f1 | cut -d- -f2)
[ -z "$AXP_BUS" ] && AXP_BUS=13
AXP_ADDR=0x34
IRQ_STAT1_REG=0x44
# Bit 4 = PEK Short Press, Bit 5 = PEK Long Press
SHORT_MASK=0x10
LONG_MASK=0x20

logger -t axp221-monitor "Starting power button monitor..."

# Wait for I2C device
for i in {1..10}; do
    if [ -e "/dev/i2c-${AXP_BUS}" ]; then
        break
    fi
    sleep 0.5
done

# Clear any pending IRQs on startup to prevent boot-loop
# Retry clearing until readback confirms it's clear
CLEARED=0
for i in {1..5}; do
    /usr/sbin/i2cset -f -y ${AXP_BUS} ${AXP_ADDR} ${IRQ_STAT1_REG} 0xFF
    val=$(/usr/sbin/i2cget -f -y ${AXP_BUS} ${AXP_ADDR} ${IRQ_STAT1_REG} 2>/dev/null)
    
    # Check if read succeeded and bits are clear
    if [ -n "$val" ] && [ $(($val & ($SHORT_MASK | $LONG_MASK))) -eq 0 ]; then
        logger -t axp221-monitor "IRQ cleared successfully (Reg 0x44: $val)"
        CLEARED=1
        break
    fi
    logger -t axp221-monitor "Failed to clear IRQ (Reg 0x44: $val), retrying..."
    sleep 0.5
done

if [ "$CLEARED" -eq 0 ]; then
    logger -t axp221-monitor "FATAL: Could not clear pending IRQ after retries. Exiting to prevent shutdown loop."
    exit 1
fi

# Post-Boot Safety Delay: Wait 30 seconds before acting on any new press
sleep 30

while true; do
    # Read status register
    val=$(/usr/sbin/i2cget -f -y ${AXP_BUS} ${AXP_ADDR} ${IRQ_STAT1_REG} 2>/dev/null)
    
    if [ -n "$val" ]; then
        # Check for Long Press (Bit 5) first -> Graceful Shutdown
        if [ $(($val & $LONG_MASK)) -ne 0 ]; then
            /usr/sbin/i2cset -f -y ${AXP_BUS} ${AXP_ADDR} ${IRQ_STAT1_REG} $LONG_MASK
            logger -t axp221-monitor "Long press detected! Triggering graceful shutdown to prevent PMIC zombie state..."
            sync
            systemctl poweroff
            exit 0
        fi

        # Check for Short Press (Bit 4) -> Lock Session
        if [ $(($val & $SHORT_MASK)) -ne 0 ]; then
            # Clear the interrupt
            /usr/sbin/i2cset -f -y ${AXP_BUS} ${AXP_ADDR} ${IRQ_STAT1_REG} $SHORT_MASK
            
            if pgrep -x sway >/dev/null; then
                logger -t axp221-monitor "Short press detected! Locking session..."
                /usr/bin/loginctl lock-session
            else
                logger -t axp221-monitor "Short press detected but Sway not running. Ignoring."
            fi
            
            sleep 1
        fi
    fi
    
    # Poll every 0.5 seconds
    sleep 0.5
done
