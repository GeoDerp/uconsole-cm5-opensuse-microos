#!/bin/bash
# AXP221 PMIC poweroff via I2C (Force Mode)
# Direct write to PMIC without unbinding drivers to maintain stability.

# Ensure i2c-dev is loaded
/usr/sbin/modprobe i2c-dev 2>/dev/null

AXP_BUS=13
AXP_ADDR=0x34
OFF_CTRL_REG=0x32
OFF_BIT=0x80

# Sync filesystems first
sync
sync

# Log the poweroff attempt
logger -t axp221-poweroff "Triggering aggressive AXP221 hardware power-off"

# 1. Kill Backlight immediately to give visual feedback
echo 0 > /sys/class/backlight/backlight@0/brightness 2>/dev/null

# 2. Release I2C bus by unbinding the kernel driver
# This prevents "Device or resource busy" errors
echo "13-0034" > /sys/bus/i2c/drivers/axp20x-i2c/unbind 2>/dev/null

# 3. Disable ALL PMIC Interrupts globally to "calm" the hardware logic
# This targets Regs 0x40, 0x41, 0x42, 0x43 (IRQ Enable 1-4)
for reg in 0x40 0x41 0x42 0x43; do
    /usr/sbin/i2cset -f -y ${AXP_BUS} ${AXP_ADDR} ${reg} 0x00 2>/dev/null
done

# 4. Disable ALL regulators manually to prevent "dimmed LED" state
# Reg 0x10 (DCDC1-5), 0x12 (ALDO1-3), 0x13 (ELDO1-3, DLDO1-4)
for reg in 0x10 0x12 0x13; do
    /usr/sbin/i2cset -f -y ${AXP_BUS} ${AXP_ADDR} ${reg} 0x00 2>/dev/null
done

# 5. Attempt to clear stuck IRQs one last time (Reg 0x44-0x47)
for reg in 0x44 0x45 0x46 0x47; do
    /usr/sbin/i2cset -f -y ${AXP_BUS} ${AXP_ADDR} ${reg} 0xFF 2>/dev/null
done

# 6. Issue poweroff command to AXP221 (Reg 0x32 -> 0x80)
/usr/sbin/i2cset -f -y ${AXP_BUS} ${AXP_ADDR} ${OFF_CTRL_REG} ${OFF_BIT}

# Should not reach here
sleep 2
# Final fallback if first attempt failed
/usr/sbin/i2cset -f -y ${AXP_BUS} ${AXP_ADDR} ${OFF_CTRL_REG} ${OFF_BIT}

