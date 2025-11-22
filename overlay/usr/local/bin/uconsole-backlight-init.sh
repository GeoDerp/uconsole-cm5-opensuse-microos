#!/bin/bash
# uConsole display and backlight initialization
# This script is run at boot by uconsole-backlight.service

# Fix SELinux context for custom modules (MicroOS has SELinux)
for ko in /var/lib/modules-overlay/*.ko; do
    [ -f "$ko" ] && chcon -t modules_object_t "$ko" 2>/dev/null
done

# Load backlight driver if not loaded
# The ocp8178_bl module controls the backlight via GPIO9 on RP1
if ! lsmod | grep -q ocp8178_bl; then
    modprobe ocp8178_bl 2>/dev/null || insmod /var/lib/modules-overlay/ocp8178_bl.ko 2>/dev/null
fi

# Wait for backlight device to appear
count=0
while [ ! -e /sys/class/backlight/backlight@0/brightness ] && [ $count -lt 30 ]; do
    sleep 0.5
    count=$((count + 1))
done

# Set brightness to trigger GPIO output mode and illuminate display
# The OCP8178 driver needs a brightness write to properly set GPIO direction
if [ -e /sys/class/backlight/backlight@0/brightness ]; then
    echo 8 > /sys/class/backlight/backlight@0/brightness 2>/dev/null
fi

# Bind framebuffer console to DRM display
# This enables text console output on the display
if [ -e /sys/class/vtconsole/vtcon1/bind ]; then
    echo 1 > /sys/class/vtconsole/vtcon1/bind 2>/dev/null
fi

exit 0
