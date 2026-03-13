# uConsole CM5 Hardware Stabilization on openSUSE MicroOS - Final Report (March 2026)

This document serves as the definitive reference for the hardware stabilization achieved on the ClockworkPi uConsole CM5 running openSUSE MicroOS.

## 1. The "Zombie PMIC" and Physical Over-Current Trip
**Symptom**: The device ignores `reboot` or `poweroff` commands (staying on with a black screen or dimmed green LED), or the keyboard/trackball suddenly stops working and `dmesg` floods with `usb x-portx: over-current condition`.
**Root Cause**: When the battery drops to critical levels (e.g., ~3.4V) during high load, the AXP221 PMIC detects a brownout or power anomaly. It reacts by throwing a physical, analog safety latch that cuts power to peripheral rails (like the USB Hub powering the keyboard). Because this is a hardware latch, the PMIC's internal state machine freezes. It stops responding to I2C reset or shutdown commands from the CPU.
**The Only Solution**: A **60-second battery pull**. You must unplug the charger, remove both batteries, and wait for the green LED to completely extinguish. This drains the capacitors, erases the PMIC's "blown fuse" memory, and allows it to restart fresh. Software cannot fix this state.

## 2. MicroOS Transactional Updates & Driver Breakage
**Symptom**: After a system update, the display stays black and `dmesg` reports `disagrees about version of symbol` for modules like `panel-cwu50`, `ocp8178_bl`, or `snd_soc_rp1_aout`.
**Root Cause**: openSUSE MicroOS uses transactional updates. When the kernel is updated, the internal "Symbol Versions" (CRCs) change. Custom out-of-tree modules built against the old kernel headers will be rejected by the new kernel.
**The Fix**: The deployment pipeline (`scripts/deploy_stabilized_config.sh`) was rewritten to automatically handle this. It syncs the C source files to the device, dynamically extracts the active `vmlinux` header file, and natively recompiles every custom driver against the running kernel.

## 3. DSI Underflows (Screen Flickering/Tearing)
**Symptom**: The display flashes or tears, and `dmesg` shows `*ERROR* Underflow! (panics=...)`.
**Root Cause**: The `video=DSI-1:720x1280@60` parameter in the GRUB boot arguments was acting as a VESA override. It forced the DRM subsystem to push the pixel clock to 77MHz, overriding the safe timings built into the `panel-cwu50` driver. This starved the RP1 DSI controller of memory bandwidth.
**The Fix**: Removed the `video=` override from GRUB. The driver now defaults to a safe 40MHz clock with generous blanking, permanently eliminating underflows. The 90-degree landscape rotation (`LEFT_UP`) was hardcoded directly into the driver source. 
*Note: You will see `vc4-drm axi:gpu: [drm] No compatible format found` in `dmesg`. This is **expected and harmless**. It simply means the complex Pi 5 VC4 engine yielded control, allowing `drm-rp1-dsi` to run as a highly stable, standalone DRM device.*

## 4. Battery Monitoring (The `uconsole_fixup` Hack)
**Symptom**: `/sys/class/power_supply` is empty, meaning the OS has no idea what the battery percentage is.
**Root Cause**: The mainline openSUSE kernel lacks the ClockworkPi-specific `axp22x_cells` MFD patch. The kernel driver finds the PMIC but doesn't spawn the battery or AC child devices.
**The Fix**: The `uconsole_fixup.ko` kernel module was updated to bind to the PMIC via its physical I2C address (`0x34`) instead of relying on Open Firmware strings. This successfully registers the missing platform devices, restoring the battery fuel gauge.

## 5. The "Fake" 11-Day Uptime (RTC Artifact)
**Symptom**: Immediately after a fresh boot, `uptime` reports 11, 12, or 26 days.
**Root Cause**: The CM5 lacks a battery-backed Real Time Clock (RTC). The kernel boots using the Unix epoch (1970) or a historic timestamp saved by systemd. When the network connects, NTP immediately jumps the system clock forward to the present day. This sudden "time travel" confuses the kernel's uptime calculation. **This is expected behavior and is not a bug.**

## 6. Power Management Scripts
All initialization and power monitoring scripts (e.g., `axp221-poweroff.sh`, `uconsole-power-monitor.sh`) now dynamically hunt for the correct software I2C bus (`i2c-13`, `i2c-15`, or `pmic_i2c`). The power monitor gracefully broadcasts warnings to all TTYs at 15% battery and forces a hardware shutdown at 8% (3.55V) to prevent the "Zombie PMIC" state described in Section 1.