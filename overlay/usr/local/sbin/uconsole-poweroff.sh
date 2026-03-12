#!/bin/bash
# Hardware-enforced poweroff for uConsole CM5
# Forces the PMIC (AXP221) to power down immediately

AXP_BUS=13
AXP_ADDR=0x34

echo "Sending hardware shutdown command to PMIC..."
# Register 0x32, Bit 7: Power Off
# Use -f to force if necessary
/usr/sbin/i2cset -y -f $AXP_BUS $AXP_ADDR 0x32 0x80
