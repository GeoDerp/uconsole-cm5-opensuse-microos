# uConsole CM5 on openSUSE MicroOS

![alt text](img/uconsole.jpg)

This repository provides device tree overlays, automated configuration scripts, and a driver-fetch tool required to run **openSUSE MicroOS** reliably on the **ClockworkPi uConsole CM5** (Raspberry Pi Compute Module 5). It resolves critical hardware-specific issues including display flickering, power management locks, driver symbol mismatches, and battery monitoring.

> **Note:** The out-of-tree kernel drivers required by the uConsole are licensed under **GPL-2.0** and are _not_ included in this MIT-licensed repository. Run `./scripts/fetch-drivers.sh` to download them from their upstream sources before building.

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

### 1.5. Fetch the Driver Sources
The GPL-licensed kernel drivers are not included in this repository. Fetch them from upstream:
```bash
./scripts/fetch-drivers.sh
```
This downloads the required driver source code from the [ClockworkPi Linux kernel](https://github.com/ak-rex/ClockworkPi-linux), [Raspberry Pi Linux kernel](https://github.com/raspberrypi/linux), and [mainline Linux kernel](https://github.com/torvalds/linux) into `extracted-drivers/`. See [Acknowledgments](#acknowledgments) for full attribution.

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

## Acknowledgments

This project would not exist without the incredible work of the ClockworkPi community and the open-source kernel developers who wrote the drivers this hardware depends on.

### Rex ([@ak-rex](https://github.com/ak-rex))
Rex created and maintains the [ClockworkPi Linux kernel fork](https://github.com/ak-rex/ClockworkPi-linux) (`rpi-6.12.y` branch) — the **single upstream source** for CM5 display, backlight, and panel drivers. The device tree overlay structure, PMIC wiring, and DSI integration in this repository are all directly derived from Rex's kernel work. Without Rex's tireless reverse-engineering and board bring-up, running Linux on the uConsole CM5 would simply not be possible.

### ClockworkPi Community
The [ClockworkPi Forum](https://forum.clockworkpi.com) community provided essential hardware debugging knowledge, boot-log analysis, and real-world testing that informed every fix in this repository. Special thanks to everyone who shared serial console captures, PMIC register dumps, and workaround discoveries.

### Driver Authors (GPL-2.0)
The following kernel drivers are fetched by `./scripts/fetch-drivers.sh` from their original GPL-licensed repositories. All copyright belongs to their respective authors:

| Driver | Authors / Copyright | Source |
|--------|---------------------|--------|
| **RP1 DSI** (`drm-rp1-dsi`) | Copyright (c) 2023 **Raspberry Pi Limited** | [raspberrypi/linux](https://github.com/raspberrypi/linux) |
| **RP1 Audio** (`snd-soc-rp1-aout`) | Copyright (c) 2025 **Raspberry Pi Ltd** | [raspberrypi/linux](https://github.com/raspberrypi/linux) |
| **CWU50 Panel** (`panel-cwu50`) | **ClockworkPi / Clockwork Tech LLC** | [ak-rex/ClockworkPi-linux](https://github.com/ak-rex/ClockworkPi-linux) |
| **CWD686 Panel** (`panel-cwd686`) | **ClockworkPi / Clockwork Tech LLC** | [ak-rex/ClockworkPi-linux](https://github.com/ak-rex/ClockworkPi-linux) |
| **CWU50-CM3 Panel** (`panel-cwu50-cm3`) | Copyright (c) 2021 **Clockwork Tech LLC**, **Max Fierke** | [ak-rex/ClockworkPi-linux](https://github.com/ak-rex/ClockworkPi-linux) |
| **OCP8178 Backlight** (`ocp8178_bl`) | **ClockworkPi** | [ak-rex/ClockworkPi-linux](https://github.com/ak-rex/ClockworkPi-linux) |
| **AXP20x Battery** (`axp20x_battery`) | Copyright (c) 2016 **Free Electrons / NextThing Co.** | [torvalds/linux](https://github.com/torvalds/linux) |
| **AXP20x AC Power** (`axp20x_ac_power`) | Copyright (c) 2016 **Free Electrons** | [torvalds/linux](https://github.com/torvalds/linux) |

---

## License

The scripts, configurations, device tree overlays, and tooling in this repository are licensed under the **MIT License**. See [LICENSE](LICENSE) for details.

The kernel driver source code in `extracted-drivers/` (fetched by `./scripts/fetch-drivers.sh`) is **not part of this repository** — it is downloaded from upstream and is licensed under **GPL-2.0-or-later** by its respective authors.