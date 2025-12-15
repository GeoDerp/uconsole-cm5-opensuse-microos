#!/bin/bash
# Monitor AXP221 for Power Button Tap (Short Press) via I2C polling
# Required because hardware IRQ line is disabled in device tree.

AXP_BUS=13
AXP_ADDR=0x34
IRQ_STAT1_REG=0x44
# Bit 4 = PEK Short Press
MASK=0x10

logger -t axp221-monitor "Starting power button monitor..."

# Clear any pending IRQs on startup to prevent boot-loop
# (e.g. the press used to turn on the device)
/usr/sbin/i2cset -f -y ${AXP_BUS} ${AXP_ADDR} ${IRQ_STAT1_REG} 0xFF

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
