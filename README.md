# uConsole CM5 on openSUSE MicroOS

This repository contains the necessary drivers, device tree overlays, and configuration scripts to run **openSUSE MicroOS** on the **ClockworkPi uConsole CM5** (Raspberry Pi Compute Module 5).

## Critical Fixes & Status

| Feature | Status | Fix Details |
|---------|--------|-------------|
| **Display** | ✅ Stable | Fixed VCI undervoltage. Configured for 3.3V (`aldo2`) instead of 1.8V. |
| **Power Off** | ✅ Fixed | Implemented direct I2C shutdown script to bypass broken kernel handler. |
| **Power Button** | ✅ Fixed | Added polling daemon (`axp221-monitor`) for graceful shutdown (Tap) and hardware config for Hard-Off (Hold 4s). |
| **Backlight** | ✅ Working | Patched driver to prevent brightness reset loops. |
| **Wifi/BT** | ✅ Working | Standard CM5 support. |
| **Boot Reliability** | ⚠️ Warning | BTRFS maintenance tasks cause I/O storms that can kill the display. **Must mask timers.** |
| **USB Devices** | ⚠️ Unstable | Keyboard/Trackball (DWC2) subject to random disconnects. |

## Installation

### 1. Prerequisites
- uConsole CM5 Device
- openSUSE MicroOS image (aarch64) installed
- SSH access

### 2. Deploy Overlays & Config
Run the deployment script from your host machine:

```bash
./scripts/deploy_overlays_to_device.sh user@uconsole-ip --names clockworkpi-uconsole-cm5
```

### 3. Deploy Power Scripts & Services
Copy the `overlay` directory contents to the device root:

```bash
# Example manual deployment
scp overlay/usr/local/sbin/* user@device:/usr/local/sbin/
scp overlay/etc/systemd/system/* user@device:/etc/systemd/system/
ssh user@device "sudo systemctl daemon-reload && sudo systemctl enable axp221-monitor.service axp221-poweroff.service"
```

### 4. Critical: Disable BTRFS Maintenance
To prevent boot-time display failure due to DMA underflow:

```bash
sudo systemctl mask btrfs-scrub.timer btrfs-balance.timer btrfs-defrag.timer btrfs-trim.timer
```

## Architecture Details

### Display Voltage Fix
The CWU50 panel requires 3.3V on its VCI (Analog) pin. The default CM5 overlay incorrectly supplied 1.8V (`dcdc3`), leading to initialization failures and instability.
**Fix:** `vci-supply = <&reg_aldo2>;` in `clockworkpi-uconsole-cm5-overlay.dts`.

### Panel Reset Logic (Pin Swap)
The `panel-cwu50` driver attempts to detect "Old Panel" vs "New Panel" by reading GPIO10. On this hardware revision, detection is flaky. When "Old Panel" is detected, the driver toggles the ID pin (GPIO10) instead of the Reset pin (GPIO8).
**Fix:** We swapped the pin definitions in the Device Tree:
*   `id-gpio` -> Set to Hardware GPIO8 (Real Reset Pin).
*   `reset-gpio` -> Set to Hardware GPIO10 (Dummy).
*   `pinctrl` -> Pull-Down GPIO8 to force "Old Panel" detection.
Result: The driver thinks it's resetting the ID pin, but it's actually resetting the Panel Reset pin. This ensures reliable initialization.

### Power Button (AXP221)
The BCM2712 GPIO controller cannot easily handle the PMIC's interrupt line in this configuration.
**Fix:**
1.  **Hardware:** `axp221-configure-pek.sh` sets the PMIC's internal "Hard Off" timer to 4 seconds.
2.  **Software:** `axp221-monitor.sh` polls the PMIC IRQ status register (0x44) via I2C to detect short presses and trigger `poweroff`.

### Shutdown Logic
Unbinding the PMIC driver to issue a shutdown command causes a regulator collapse.
**Fix:** `axp221-poweroff.sh` uses `i2cset -f` to write the shutdown command (Reg 0x32 -> 0x80) *without* unbinding the driver, ensuring power stays stable until the PMIC cuts it.

## Known Issues

*   **Display Underflow:** High system load (disk I/O) can starve the DSI display pipeline, causing "Underflow" errors or momentary black screens. Disable heavy background services.
*   **USB Disconnects:** The internal USB hub (keyboard/trackball) connected to the DWC2 controller may disconnect randomly. This is an upstream driver issue.
*   **Uptime Bug:** The CM5 uptime counter may report incorrect values (e.g., 89 days) immediately after boot. Use `dmesg` timestamps for accuracy.