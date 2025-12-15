#!/bin/bash
# AXP221 PMIC poweroff via I2C (Force Mode)
# Direct write to PMIC without unbinding drivers to maintain stability.

# Ensure i2c-dev is loaded
/usr/sbin/modprobe i2c-dev 2>/dev/null

AXP_BUS=13
AXP_ADDR=0x34
OFF_CTRL_REG=0x32
OFF_BIT=0x80

# Sync filesystems first (redundant if run by systemd-shutdown, but safe)
sync
sync

# Log the poweroff attempt
logger -t axp221-poweroff "Triggering AXP221 hardware power-off via I2C (Reg 0x32 -> 0x80)"

# Issue poweroff command to AXP221
# Force access with -f to bypass bound kernel driver
/usr/sbin/i2cset -f -y ${AXP_BUS} ${AXP_ADDR} ${OFF_CTRL_REG} ${OFF_BIT}

# Should not reach here - PMIC should have cut power immediately
sleep 5
logger -t axp221-poweroff "WARNING: Power-off command sent but system still running!"
