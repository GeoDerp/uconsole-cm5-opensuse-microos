#!/bin/bash
# Monitor AXP221 for Power Button Tap (Short Press) via I2C polling
# Required because hardware IRQ line is disabled in device tree.

AXP_BUS=13
AXP_ADDR=0x34
IRQ_STAT1_REG=0x44
# Bit 4 = PEK Short Press
MASK=0x10

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
    
    # Check if read succeeded and bit is clear
    if [ -n "$val" ] && [ $(($val & $MASK)) -eq 0 ]; then
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
# This ensures that if the script restarts or loops, the user has time to intervene via SSH/Console
sleep 30

while true; do
    # Read status register
    val=$(/usr/sbin/i2cget -f -y ${AXP_BUS} ${AXP_ADDR} ${IRQ_STAT1_REG} 2>/dev/null)
    
    if [ -n "$val" ]; then
        # Check if Bit 4 is set
        if [ $(($val & $MASK)) -ne 0 ]; then
            logger -t axp221-monitor "Power button pressed! Initiating shutdown..."
            
            # Clear the interrupt (write 1 to the bit)
            /usr/sbin/i2cset -f -y ${AXP_BUS} ${AXP_ADDR} ${IRQ_STAT1_REG} $MASK
            
            # Trigger graceful shutdown
            /usr/sbin/poweroff
            
            # Exit loop
            exit 0
        fi
    fi
    
    # Poll every 0.5 seconds
    sleep 0.5
done
