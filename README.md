# uConsole CM5 on openSUSE MicroOS

This repository contains the drivers, device tree overlays, and configuration scripts required to run **openSUSE MicroOS** on the **ClockworkPi uConsole CM5** (Raspberry Pi Compute Module 5). It addresses critical hardware-specific issues including display voltage, power management, and driver instability.

## System Status

| Feature | Status | Fix Details |
|---------|--------|-------------|
| **Display** | ✅ Stable | **Pin Swap Overlay:** Forces driver to use correct reset logic. **Voltage:** Set to 3.3V (`aldo2`). |
| **Backlight** | ✅ Working | patched driver handles initialization logic. |
| **Power Button (Hold)** | ✅ Working | Hardware Hard-Off set to **4 Seconds** via PMIC register. |
| **Power Button (Tap)** | ✅ Working* | Software daemon polls PMIC for graceful shutdown. *Requires functioning I2C bus.* |
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
Copy the critical power scripts and services:

```bash
scp overlay/usr/local/sbin/* user@device:/usr/local/sbin/
scp overlay/etc/systemd/system/axp221-monitor.service user@device:/etc/systemd/system/
ssh user@device "sudo systemctl daemon-reload && sudo systemctl enable axp221-monitor.service axp221-configure-pek.service"
```

### 4. Enable Sway Session (Optional)
To replace the fragile console autologin with a robust graphical session:

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
**Problem:** Pressing the power button to turn *on* the device latches the "Short Press" interrupt bit in the AXP221 PMIC. When Linux boots, the polling script reads this "1" and immediately triggers a shutdown.
**Solution:** The `axp221-monitor.sh` script now implements a **Safety Interlock**:
1.  Waits for I2C bus availability.
2.  Attempts to clear the IRQ register (`0x44`) up to 5 times.
3.  **Fatal Exit:** If the IRQ cannot be cleared (stuck high), the script **exits** instead of entering the monitoring loop. This prevents the infinite reboot cycle.
4.  **Safety Delay:** A 30-second sleep is added before the first poll to allow user intervention.

### 3. Driver Unbind Crash
**Problem:** The standard `shutdown` command attempts to unbind device drivers. Unbinding the AXP20x I2C driver kills all child regulators immediately, cutting power to the CPU/RAM before the filesystem syncs.
**Solution:** The `axp221-poweroff.sh` script uses `i2cset -f` (Force Mode) to write the shutdown command directly to the PMIC *without* unbinding the driver. This maintains system power stability until the very last moment.
