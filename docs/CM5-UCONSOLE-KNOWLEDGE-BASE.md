# uConsole CM5 Hardware Stabilization on openSUSE MicroOS - Final Report (March 2026)

This document serves as the definitive reference for the hardware stabilization achieved on the ClockworkPi uConsole CM5 running openSUSE MicroOS.

## 1. The "Zombie PMIC" and Physical Over-Current Trip
**Symptom**: The device ignores `reboot` or `poweroff` commands (staying on with a black screen or dimmed green LED), or the keyboard/trackball suddenly stops working and `dmesg` floods with `usb x-portx: over-current condition`.
**Root Cause**: When the battery drops to critical levels (e.g., ~3.4V) during high load, the AXP221 PMIC detects a brownout or power anomaly. It reacts by throwing a physical, analog safety latch that cuts power to peripheral rails (like the USB Hub powering the keyboard). Because this is a hardware latch, the PMIC's internal state machine freezes. It stops responding to I2C reset or shutdown commands from the CPU.
**The Only Solution**: A **60-second battery pull**. You must unplug the charger, remove both batteries, and wait for the green LED to completely extinguish. This drains the capacitors, erases the PMIC's "blown fuse" memory, and allows it to restart fresh. Software cannot fix this state.

## 2. MicroOS Transactional Updates & Driver Breakage
**Symptom**: After a system update, the display stays black and `dmesg` reports `disagrees about version of symbol` for modules like `panel-cwu50`, `ocp8178_bl`, or `snd_soc_rp1_aout`.
**Root Cause**: openSUSE MicroOS uses transactional updates. When the kernel is updated, the internal "Symbol Versions" (CRCs) change. Custom out-of-tree modules built against the old kernel headers will be rejected by the new kernel.
**The Fix**: The deployment pipeline (`scripts/rebuild_and_deploy_offline.sh`) was created to automatically handle this. If the device falls off the network due to an update, it can be plugged in via USB and natively recompiled against the running kernel via a `chroot` using `qemu-aarch64-static`.

## 3. DSI Underflows and Display Pipeline
**Symptom**: The display flashes or tears, and `dmesg` shows `*ERROR* Underflow! (panics=...)`, or the screen remains completely black.
**Root Cause 1 (Underflows)**: The `video=DSI-1:720x1280@60` parameter in the GRUB boot arguments was acting as a VESA override. It forced the DRM subsystem to push the pixel clock to 77MHz, overriding the safe timings built into the `panel-cwu50` driver. This starved the RP1 DSI controller of memory bandwidth.
**Root Cause 2 (Black Screen)**: Disabling the `vc4` graphics core (e.g., via `disable-vc4` overlay) breaks the Pi 5's Hardware Video Scaler pipeline, leaving the `drm-rp1-dsi` driver without a valid pixel source and freezing the U-Boot handoff. 
**The Fix**: 
*   **Base DTB**: We use `device_tree=merged-clockworkpi.dtb` as the monolithic foundation. It correctly maps the `vc4` pipeline to the DSI controller without claiming the GPIOs needed for the PMIC.
*   **GRUB**: Removed the `video=DSI-1...` overrides from GRUB. Blacklisted `vc4` in GRUB (`module_blacklist=vc4`) so `v3d` and `drm-rp1-dsi` load without conflict.
*   **Driver**: Rely on the device tree `rotation = <90>` for orientation.

## 4. Battery Monitoring (The `uconsole_fixup` Hack)
**Symptom**: `/sys/class/power_supply` is empty, meaning the OS has no idea what the battery percentage is.
**Root Cause**: The mainline openSUSE kernel lacks the ClockworkPi-specific `axp22x_cells` MFD patch. The kernel driver finds the PMIC but doesn't spawn the battery or AC child devices.
**The Fix**: The `uconsole_fixup.ko` kernel module was updated to bind to the PMIC via its physical I2C address (`0x34`) instead of relying on Open Firmware strings. This successfully registers the missing platform devices, restoring the battery fuel gauge.

## 5. The "Fake" 11-Day Uptime (RTC Artifact)
**Symptom**: Immediately after a fresh boot, `uptime` reports 11, 12, or 26 days.
**Root Cause**: The CM5 lacks a battery-backed Real Time Clock (RTC). The kernel boots using the Unix epoch (1970) or a historic timestamp saved by systemd. When the network connects, NTP immediately jumps the system clock forward to the present day. This sudden "time travel" confuses the kernel's uptime calculation. **This is expected behavior and is not a bug.**

## 6. Power Management Scripts
All initialization and power monitoring scripts (e.g., `axp221-poweroff.sh`, `uconsole-power-monitor.sh`) now dynamically hunt for the correct software I2C bus (`i2c-13`, `i2c-15`, or `pmic_i2c`). The power monitor gracefully broadcasts warnings to all TTYs at 15% battery and forces a hardware shutdown at 8% (3.55V) to prevent the "Zombie PMIC" state described in Section 1.

## 7. The DSI Starvation Bug (Black Screen)
**Symptom**: The display driver binds perfectly (`fb0` is created), but the physical screen remains black.
**Root Cause**: The `drm-rp1-dsi` driver mathematically calculates a 30MHz DSI byte clock for a 40MHz pixel clock. 3 bytes per pixel (RGB888) × 40MHz / 4 lanes = 30MHz. This provides **0% overhead** for DSI packet headers and sync pulses, starving the DMA engine of bandwidth and dropping frames. Furthermore, assigning incorrect DSI clocks in the device tree caused U-Boot to hard lock.
**The Fix**: Modified `rp1_dsi_dsi.c` to append `* 12 / 10` to the `byte_clock` formula, enforcing a strict 20% DSI bandwidth overhead margin (resulting in a stable 36MHz byte clock).

## 8. DRM Modeset Kernel Panic (Orientation Bug)
**Symptom**: Kernel panic and DRM stack trace during `drm_client_modeset_probe`.
**Root Cause**: The `panel-cwu50` driver manually called `drm_connector_set_panel_orientation()` inside `get_modes()`, attaching a property to an already-registered connector, which is illegal in modern DRM core and triggers a fatal `WARN`.
**The Fix**: Stripped all manual `panel_orientation` logic from the C driver entirely. Rely solely on the `rotation = <90>` property inside the device tree, which the DRM panel bridge parses and applies legally during probe.

## 9. NetworkManager Wi-Fi Renaming Failure
**Symptom**: Wi-Fi initializes flawlessly (driver loads, no errors), but fails to connect to known networks.
**Root Cause**: The kernel predictably renames the Broadcom interface from `wlan0` to `wld0` (`brcmfmac mmc1:0001:1 wld0: renamed from wlan0`). If NetworkManager profiles (`/etc/NetworkManager/system-connections/*.nmconnection`) have `interface-name=wlan0` hardcoded, NM ignores the `wld0` device.
**The Fix**: Delete the `interface-name=` line from all persistent NM connection profiles. Note: on MicroOS, this requires modifying the active `@/etc` BTRFS subvolume.