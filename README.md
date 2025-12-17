# uConsole CM5 on openSUSE MicroOS

This repository contains the drivers, device tree overlays, and configuration scripts required to run **openSUSE MicroOS** on the **ClockworkPi uConsole CM5** (Raspberry Pi Compute Module 5). It addresses critical hardware-specific issues including display voltage, power management, and driver instability.

## System Status

| Feature | Status | Fix Details |
|---------|--------|-------------|
| **Display** | ✅ Stable | **Pin Swap Overlay:** Forces driver to use correct reset logic. **Voltage:** Set to 3.3V (`aldo2`). |
| **Backlight** | ✅ Working | patched driver handles initialization logic. |
| **Power Button (Hold)** | ✅ Working | Hardware Hard-Off set to **4 Seconds** via PMIC register. |
| **Power Button (Tap)** | ❌ Disabled | Disabled due to hardware IRQ stuck-high fault on this unit. |
| **Shutdown** | ✅ Safe | Custom script forces PMIC shutdown via I2C, preventing regulator crashes. |
| **Boot Reliability** | ✅ Stable | BTRFS maintenance timers masked to prevent I/O storms and display underflows. |

## Installation

### 1. Prerequisites
- uConsole CM5 Device
- openSUSE MicroOS (aarch64) installed
- SSH access

### 2. Deploy Configuration & Overlays
Run the deployment script from your host machine:

```bash
./scripts/deploy_overlays_to_device.sh user@uconsole-ip --names clockworkpi-uconsole-cm5
```

### 3. Deploy Power Management
Copy the critical power scripts:

```bash
scp overlay/usr/local/sbin/axp221-poweroff.sh user@device:/usr/local/sbin/
scp overlay/usr/local/sbin/axp221-configure-pek.sh user@device:/usr/local/sbin/
ssh user@device "sudo systemctl daemon-reload && sudo systemctl enable axp221-configure-pek.service"
```
*(Note: `axp221-monitor.service` is disabled by default due to hardware IRQ issues).*

### 4. Enable Sway Session (Optional)
To start Sway automatically after TTY login:

```bash
scp overlay/home/geo/.config/systemd/user/sway.service user@device:~/.config/systemd/user/
ssh user@device "systemctl --user enable sway.service"
```

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


## Known Limitations

*   **Reboot Behavior:** The `reboot` command may fully power off the device instead of restarting it. This is a behavior of the AXP221 PMIC integration on this board. You must press the power button to turn it back on.
*   **Startup Sequence:** The device boots to a **TTY Login Prompt** (text mode). You must log in (user: `geo`) to automatically start the graphical interface (Sway).
*   **Sleep/Hibernate:** **Not Supported.**
    *   **Sleep:** Fails due to missing RTC driver (`/dev/rtc0` not found).
    *   **Hibernate:** Fails due to no Swap space configured.
    *   *Workaround:* Use **Shutdown** (Power Off) to save battery. Boot time is fast.

