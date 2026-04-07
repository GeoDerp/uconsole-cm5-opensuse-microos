# uConsole CM5 on openSUSE MicroOS

![alt text](img/uconsole.jpg)

This repository provides the definitive drivers, device tree overlays, and automated configuration scripts required to run **openSUSE MicroOS** reliably on the **ClockworkPi uConsole CM5** (Raspberry Pi Compute Module 5). It resolves critical hardware-specific issues including display flickering, power management locks, driver symbol mismatches, and battery monitoring.

## System Status (April 2026)

| Feature | Status | Fix Details |
|---------|--------|-------------|
| **Display** | ✅ Stable | DSI pixel clock locked at a safe 40MHz. DSI byte clock mathematically assigned a 20% overhead margin (36MHz) to prevent DMA starvation. DRM modeset orientation bug completely stripped from the driver to prevent kernel panics. |
| **Graphics**| ✅ Hardware | Standard `v3d` graphics active. `vc4` blacklisted in Linux but active in firmware for successful U-Boot handoff. Boot screen shows TTY before handing off to Sway/Wayland seamlessly. |
| **Audio**   | ✅ Working | Speakers functional via `snd_soc_rp1_aout`. Drivers rebuilt against current kernel. |
| **Battery Fuel Gauge** | ✅ Functional | Device tree now spawns the `axp221-battery-power-supply` and `axp221-adc` children directly, permanently eliminating the need for the hacky `uconsole_fixup` kernel module! |
| **Wi-Fi**   | ✅ Working | NetworkManager profiles dynamically fixed to ignore the kernel's `wlan0` to `wld0` interface renaming bug. |
| **Input (Keyboard/Trackball)**   | ✅ Working | `dwc2` driver forced to `host` mode. Aggressive VBUS hogs removed to prevent PMIC over-current trips on cold boot. |
| **Power Button** | ✅ Working | `axp221-monitor.service` successfully intercepts a 1.5s Long Press to trigger a graceful OS shutdown, bypassing the buggy 6s hardware kill. |
| **Shutdown** | ✅ Graceful | Handled safely by the OS to ensure all LDO regulators turn off properly, permanently preventing the PMIC zombie state. |
| **Battery Safety**| ✅ Active | Background monitor (`uconsole-power-monitor`) broadcasts warnings to TTY/Wayland at **15%**, and forces a hardware shutdown at **8%** to prevent the PMIC from entering a brownout/zombie state. |
| **MicroSD Slot** | ❌ Not Working | External SD card slot on the mainboard is currently undetected by the RP1 architecture. |
| **Sleep / Hibernate** | ❌ Not Supported | **Sleep:** Fails due to missing deep sleep ACPI support on XHCI. **Hibernate:** Fails due to no Swap space. <br>✅ *Alternative*: System automatically powers off after **30 minutes** of screen inactivity to preserve battery. |

---

## Installation Guide (Offline Flash)

Because openSUSE MicroOS is a transactional OS, installing out-of-tree display drivers *after* booting can be extremely difficult. We have created a seamless **offline installation** process. You will flash the OS, compile the custom drivers on your PC via a `chroot`, and deploy them directly to the CM5 before ever plugging it into the uConsole.

### 1. Flash the OS
1. Connect your CM5 to your PC via USB (using the `rpiboot` tool or a CM4 IO board).
2. Use **Raspberry Pi Imager** to flash the **openSUSE MicroOS (aarch64)** image to the CM5 eMMC.
3. Wait for the flashing to complete. DO NOT boot the CM5 yet!

### 2. Create the Initial User (Combustion)
openSUSE MicroOS has no default user. You must use the Combustion first-boot tool to create one.
1. On your host PC, clone this repository:
   ```bash
   git clone https://github.com/GeoDerp/uconsole-cm5-opensuse-microos.git
   cd uconsole-cm5-opensuse-microos
   ```
2. Run the helper script to generate the setup configuration:
   ```bash
   ./scripts/generate_combustion_script.sh uconsole mypassword ~/.ssh/id_rsa.pub
   ```
3. Format a spare USB flash drive with the label `combustion` (FAT32 or ext4).
4. Copy the generated `combustion` folder to the root of the USB drive. You will plug this into the uConsole during its first boot.

### 3. Mount the Partitions
Ensure the newly flashed CM5 is still connected to your PC via USB.
Mount the **EFI** (boot) and **ROOT** (system) partitions to your host machine.
*(Example for Linux hosts using `udisksctl`):*
```bash
udisksctl mount -b /dev/sda1  # Mounts EFI
udisksctl mount -b /dev/sda2  # Mounts ROOT
```

### 4. Deploy and Compile the Drivers
Run the offline deployment script. Provide the paths to the mounted EFI and ROOT partitions. 
*(Note: You must have `qemu-aarch64-static` installed on your host PC to natively cross-compile the drivers).*

```bash
# Example paths (adjust to match your mount points):
./scripts/install_uconsole_offline.sh /run/media/$USER/EFI /run/media/$USER/ROOT
```

**This script will automatically:**
*   Compile the customized device tree overlays.
*   Copy all configuration files, services, and NetworkManager fixes to the root filesystem.
*   `chroot` into the CM5 using `qemu-aarch64-static`.
*   **Compile all out-of-tree drivers natively** against the target's kernel headers.
*   Install the modules and configure GRUB.

### 5. Boot and Enjoy!
1. The script will safely unmount the partitions when finished.
2. Unplug the CM5 from your PC and install it into your uConsole mainboard.
3. Plug the `combustion` USB drive into the uConsole's external USB port.
4. Turn on the power. The screen will display the scrolling Linux TTY boot logs, automatically create your user account, and hand off seamlessly to the Sway desktop environment!

---

## Critical Troubleshooting

### 🧟 The "Zombie PMIC" (Hardware Over-Current Lock)
**Symptom**: The green LED stays on but the screen is dead, the device ignores `reboot`/`poweroff` commands, OR the keyboard suddenly dies and `dmesg` floods with `usb x-portx: over-current condition`.
**Cause**: If the battery drops too low (~3.4V) under load, the AXP221 PMIC trips a physical, analog safety latch that cuts power to the USB hub. Because it's a hardware latch, the chip's state machine freezes and stops accepting software I2C commands.
**The Fix**: **A 60-Second Battery Pull.**
1. Unplug the USB-C charger.
2. Remove BOTH batteries.
3. Wait at least 60 seconds (The green LED must be completely dark to drain the capacitors).
4. Re-insert and power on. Software cannot "un-blow" this fuse; it must lose voltage entirely.

### ⏳ The "Fake" 11-Day Uptime
**Symptom**: Immediately after a fresh boot, `uptime` reports 11, 12, or 26 days.
**Cause**: The CM5 lacks a battery-backed Real Time Clock (RTC). The kernel boots using the Unix epoch (1970) or a historic timestamp saved by systemd. When the network connects, NTP immediately jumps the system clock forward to the present day. This sudden "time travel" confuses the kernel's uptime calculation. **This is expected behavior and is not a bug.**

### 🛠️ Kernel Updates (Transactional Updates)
When openSUSE automatically updates the system kernel via `transactional-update`, your display and battery drivers will instantly break on the next boot because the kernel ABI symbols changed. If the device falls off the network due to the Wi-Fi driver breaking, you will lose SSH access.
**The Fix**: Unplug the CM5, mount it to your PC via USB, and simply run `./scripts/install_uconsole_offline.sh` again! The script is designed to safely rebuild the drivers against whatever new kernel openSUSE has installed.

## License
The scripts and configurations in this repository are open source.
The kernel drivers in `extracted-drivers/` are derived from the Linux Kernel and Raspberry Pi kernel source, licensed under **GPL-2.0-or-later**.