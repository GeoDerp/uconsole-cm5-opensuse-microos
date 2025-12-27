# uConsole CM5 on openSUSE MicroOS

![alt text](img/uconsole.jpg)

This repository contains the drivers, device tree overlays, and configuration scripts required to run **openSUSE MicroOS** on the **ClockworkPi uConsole CM5** (Raspberry Pi Compute Module 5). It addresses critical hardware-specific issues including display voltage, power management, and driver instability.

## System Status

| Feature | Status | Fix Details |
|---------|--------|-------------|
| **Display** | ✅ Stable | **Relaxed Timings:** Htotal increased to 1100 to eliminate DSI Underflow errors. **Voltage:** Set to 3.3V (`aldo2`). |
| **Graphics**| ⚠️ Software | **Tearing Fix:** Use `pixman` renderer and disable hardware cursors in Sway. V3D Hardware acceleration still unstable (-110 timeout). |
| **Audio**   | ✅ Working | **Simple-Card:** Enabled via `spdif-transmitter` and `simple-audio-card` nodes in DTS. |
| **Battery** | ✅ Functional | **AXP20x Battery:** Enabled via `uconsole_fixup` kernel module to populate sysfs. |
| **Input**   | ✅ Working | **DWC2:** Enabled in DTS to support internal keyboard/trackball hub. |
| **Power Button** | ⚠️ Limited | Physical 6s hold unreliable on this unit due to **stuck hardware interrupts** (Reg 0x44=0xFF). |
| **Shutdown** | ✅ Aggressive | Forced PMIC shutdown via I2C (`axp221-poweroff.sh`) unbinds driver to bypass I2C bus locks. |
| **Battery Safety**| ✅ Active | Background monitor (`uconsole-power-monitor`) force-shuts down at 8% or on sensor loss. |
| **Boot Reliability**| ✅ Stable | BTRFS maintenance timers masked to prevent I/O storms and display underflows. |

## Installation (Fresh Install)

Follow these steps to set up a new openSUSE MicroOS installation on the uConsole CM5.

### 1. Prepare the OS
1.  Flash the **openSUSE MicroOS (aarch64)** image to your CM5 eMMC or SD card.
2.  Boot the device. Connect a USB keyboard/mouse and HDMI display if the internal screen is not yet working.
3.  Connect to Wi-Fi/Ethernet.
4.  Enable SSH: `sudo systemctl enable --now sshd`.

### 2. Prepare the Host
On your computer (Linux/macOS), clone this repository:
```bash
git clone https://github.com/GeoDerp/uconsole-cm5-opensuse-microos.git
cd uconsole-cm5-opensuse-microos
```

### 3. Deploy Configuration & Overlays
Run the deployment script to install the device tree overlays and base configuration. This fixes the display voltage and pinout.
```bash
# Replace 'user' and 'ip' with your device's details
./scripts/deploy_overlays_to_device.sh user@ip --names clockworkpi-uconsole-cm5
```
*The device will reboot.*

### 4. Build & Install Drivers
Run the driver build script. This compiles the custom kernel modules (`panel-cwu50`, `ocp8178_bl`, `drm-rp1-dsi`) on the device to match the running kernel.
```bash
./scripts/deploy_and_build_drivers_snapshot.sh user@ip
```
*The device will reboot again.*

### 5. Deploy Power Management & Services
Copy the critical power management scripts and enable the necessary services.
```bash
# Copy scripts
scp overlay/usr/local/sbin/* user@ip:/usr/local/sbin/
scp overlay/usr/local/bin/uconsole-backlight-init.sh user@ip:/usr/local/bin/

# Copy service files
scp overlay/etc/systemd/system/axp221-monitor.service user@ip:/etc/systemd/system/
scp overlay/etc/systemd/logind.conf.d/uconsole-power.conf user@ip:/etc/systemd/logind.conf.d/

# Enable services
ssh user@ip "sudo chmod +x /usr/local/sbin/*.sh /usr/local/bin/*.sh"
ssh user@ip "sudo restorecon -v /usr/local/sbin/* /usr/local/bin/*"
ssh user@ip "sudo systemctl daemon-reload"
ssh user@ip "sudo systemctl enable axp221-configure-pek.service uconsole-backlight.service"
# Note: axp221-monitor.service is disabled by default due to hardware IRQ issues on some units.
```

### 6. Configure User Session (Sway)
MicroOS boots to a TTY by default. Configure Sway to start automatically upon login to TTY1.
```bash
# Add auto-start logic to .bash_profile
ssh user@ip "cat >> ~/.bash_profile << 'EOF'

# Auto-start Sway on TTY1
if [ -z \"\$WAYLAND_DISPLAY\" ] && [ \"\$XDG_VTNR\" = \"1\" ]; then
    export XDG_RUNTIME_DIR=\"/run/user/\$(id -u)\"
    export LIBSEAT_BACKEND=seatd
    exec sway
fi
EOF"
```
*Alternatively, you can run `./scripts/install-sway-uconsole.sh` on the device, which automates this and installs Sway/Waybar/Config.*

### 7. Finalize
Reboot the device.
1.  Log in at the TTY prompt.
2.  Sway should start automatically.
3.  The screen should be active and backlight adjustable.


## Troubleshooting & Safety

### 🛑 Boot Loop Recovery
If the device shuts down immediately after boot (Power Button Monitor false positive):
1.  Connect a USB keyboard.
2.  Power on and hold `Shift` or press `Esc` to access GRUB.
3.  Edit the boot entry: Add `systemd.unit=rescue.target`.
4.  Boot (F10).
5.  Disable the monitor: `systemctl disable axp221-monitor.service`.

### 📺 Black Screen
*   **Locked:** The screen is likely just locked by Swaylock. Type your password and press Enter.
*   **Backlight Off:** If `dmesg` says backlight is on but screen is dark, reload the driver: `sudo rmmod ocp8178_bl && sudo modprobe ocp8178_bl`.

## Hardware Differences: CM4 vs CM5

The uConsole CM5 (Compute Module 5) introduces significant architectural changes compared to the CM4 version.

1.  **PMIC Integration:**
    *   **CM4:** Uses the **AXP228** PMIC.
    *   **CM5:** Uses the **AXP221** PMIC. While similar, register definitions for IRQs and power control differ slightly. The CM5 requires specific handling for the "Power Button" interrupt to avoid boot loops.

2.  **Display Pipeline (DSI):**
    *   **CM4:** Uses the standard **VC4** (VideoCore 4) DRM driver.
    *   **CM5:** Uses the Raspberry Pi 5 **RP1** I/O controller. The DSI interface is managed by the `drm-rp1-dsi` driver, which is distinct from the VC4 pipeline. This requires a specific kernel module (`drm_rp1_dsi`) not present in mainline kernels yet.

3.  **Panel Voltage:**
    *   The **CWU50** panel on the CM5 adapter board requires a **3.3V** supply on `aldo2`. The default (or CM4-derived) configuration often sets this to 1.8V, causing the panel controller to crash or fail initialization. This is fixed via the `clockworkpi-uconsole-cm5.dtbo` overlay.

## Lessons Learnt & Architecture

### 1. Display Reset Race Condition
**Problem:** The `panel-cwu50` driver toggles the Reset pin too early during boot, while the 3.3V regulator is still ramping up. The panel ignores this "weak" reset and fails to initialize.
**Solution:** We implemented a **GPIO Pin Swap** in the Device Tree. We mapped the "ID Pin" to the real Hardware Reset pin and pulled it LOW. This forces the driver into "Old Panel" detection mode, which triggers a specific toggle sequence on the "ID Pin" (actually the Reset Pin). This alternative sequence proves physically robust on every boot.

### 2. PMIC Interrupt Latching (The Boot Loop)
**Problem:** Pressing the power button to turn *on* the device latches the "Short Press" interrupt bit in the AXP221 PMIC. On some units, this bit gets stuck HIGH (`0xFF` readback), causing the monitoring script to think the button is constantly pressed.
**Solution:** The `axp221-monitor.sh` script implements a safety check. If it cannot clear the IRQ on startup, it **exits** instead of entering the monitoring loop. This prevents the infinite reboot cycle, but disables the "Tap" functionality.

### 3. Driver Unbind Crash
**Problem:** The standard `shutdown` command attempts to unbind device drivers. Unbinding the AXP20x I2C driver kills all child regulators immediately, cutting power to the CPU/RAM before the filesystem syncs.
**Solution:** The `axp221-poweroff.sh` script uses `i2cset -f` (Force Mode) to write the shutdown command directly to the PMIC *without* unbinding the driver. This maintains system power stability until the very last moment.

### 4. MicroOS Driver Persistence
**Problem:** openSUSE MicroOS has a read-only root filesystem and manages kernel updates via snapshots. Standard `make install` fails because `/lib/modules` is read-only during runtime.
**Solution:**
*   **Build:** We run the build process *inside* a `transactional-update run` shell (`scripts/deploy_and_build_drivers_snapshot.sh`). This allows writing to `/lib/modules` in a new snapshot.
*   **Persistence:** We backup the compiled `.ko` files to `/var/lib/modules-overlay/`.
*   **Boot Fallback:** The `uconsole-backlight-init.sh` script uses a robust `load_module` function. It attempts `modprobe` first (standard path). If that fails (e.g., after a kernel upgrade where modules are missing), it falls back to `insmod` using the preserved files in `/var/lib/modules-overlay/`. This ensures the display works even if the kernel driver database is desynchronized.
*   **Kernel Upgrades:** When the system kernel is updated (via `transactional-update up`), the binary drivers in `/lib/modules` will become obsolete. You **must** re-run `./scripts/deploy_and_build_drivers_snapshot.sh` to rebuild the drivers for the new kernel version. The fallback mechanism will keep the display alive to allow this maintenance.


### 5. Display Tearing & "Square Glitches"
**Problem:** Sway/Wayland exhibit massive screen tearing and "square glitches" (corrupted tiles) when opening windows or moving the mouse. This is caused by the RP1 DSI controller timing out (Underflow) or tiling modifier mismatches in the V3D hardware.
**Solution:**
1.  **Relaxed Timings:** We increased the horizontal total pixels from 800 to 1100 in the `panel-cwu50` driver. This lowers the refresh rate to ~34Hz but gives the RP1 DMA enough bandwidth to avoid underflows.
2.  **Software Rendering:** Until the BCM2712 V3D driver stabilizes, we force Sway to use the `pixman` renderer and disable hardware cursors. Add these to your `.bash_profile`:
    ```bash
    export WLR_RENDERER=pixman
    export WLR_NO_HARDWARE_CURSORS=1
    export WLR_DRM_DEVICES=/dev/dri/card1:/dev/dri/card0
    ```
    This provides a completely smooth, tear-free desktop experience.

## Known Limitations

*   **Reboot Behavior:** The `reboot` command may fully power off the device instead of restarting it. This is a behavior of the AXP221 PMIC integration on this board. You must press the power button to turn it back on.
*   **Startup Sequence:** The device boots to a **TTY Login Prompt** (text mode). You must log in (user: `geo`) to automatically start the graphical interface (Sway).
*   **Sleep/Hibernate:** **Not Supported.**
    *   **Sleep:** Fails due to missing RTC driver (`/dev/rtc0` not found).
    *   **Hibernate:** Fails due to no Swap space configured.
    *   *Workaround:* Use **Shutdown** (Power Off) to save battery. Boot time is fast.
*   **MicroSD Card Slot:** **Not functional.** The external SD card slot on the uConsole mainboard is not currently detected by the CM5/RP1 configuration.
*   **USB Devices:** Working (Keyboard, Trackball, External Storage).

## Todo
- [ ] smooth out trackball

## Credits
- **Rex & The ClockworkPi Community:** For the initial CM5 hardware investigation and device tree overlays.
- **ClockworkPi:** For the uConsole hardware.
- **openSUSE:** For the MicroOS platform.
- **Raspberry Pi:** For the RP1 drivers and CM5 support.

## License
The scripts and configurations in this repository are open source.
The kernel drivers in `extracted-drivers/` are derived from the Linux Kernel and Raspberry Pi kernel source, licensed under **GPL-2.0-or-later**.