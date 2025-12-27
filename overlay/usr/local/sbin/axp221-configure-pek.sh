#!/bin/bash
# Configure AXP221 power button (PEK) for hardware shutdown and monitoring
# Uses direct I2C writes (force mode) to avoid unbinding driver.

# Ensure i2c-dev is loaded
/usr/sbin/modprobe i2c-dev 2>/dev/null

AXP_BUS=13
AXP_ADDR=0x34
PEK_REG=0x36
IRQ_EN1_REG=0x40
IRQ_STAT1_REG=0x44

# 1. Configure Hardware Hard-Off Time (4 Seconds)
# Read current PEK register value
current=$(/usr/sbin/i2cget -f -y ${AXP_BUS} ${AXP_ADDR} ${PEK_REG} 2>/dev/null)
if [ -n "$current" ]; then
    # Set bits 0-1 to 01 (Shutdown time: 01=6s)
    # Mask: 0xFC (1111 1100), OR with 0x01
    new_val=$(( ($current & 0xFC) | 0x01 ))
    /usr/sbin/i2cset -f -y ${AXP_BUS} ${AXP_ADDR} ${PEK_REG} ${new_val}
    logger -t axp221-pek "Configured PEK hard-off to 6s (Reg 0x36: $new_val)"
else
    logger -t axp221-pek "Failed to read PEK register!"
fi

# 2. DISABLE PEK Interrupts (Workaround for stuck IRQ hardware)
# Enabling these on faulty units prevents clean hardware shutdowns.
irq_en=$(/usr/sbin/i2cget -f -y ${AXP_BUS} ${AXP_ADDR} ${IRQ_EN1_REG} 2>/dev/null)
if [ -n "$irq_en" ]; then
    # Disable bit 4 (Short Press) and bit 5 (Long Press) -> Mask 0xCF (1100 1111)
    new_irq_en=$(($irq_en & 0xCF))
    /usr/sbin/i2cset -f -y ${AXP_BUS} ${AXP_ADDR} ${IRQ_EN1_REG} ${new_irq_en}
    logger -t axp221-pek "Disabled PEK IRQs (Reg 0x40: $new_irq_en) to stabilize shutdown logic"
fi

# 3. Aggressively clear pending IRQs (Reg 0x44)
# Some units require multiple writes to clear latched bits
for i in {1..5}; do
    /usr/sbin/i2cset -f -y ${AXP_BUS} ${AXP_ADDR} ${IRQ_STAT1_REG} 0xFF
    sleep 0.1
done
logger -t axp221-pek "Cleared pending IRQs in Reg 0x44"