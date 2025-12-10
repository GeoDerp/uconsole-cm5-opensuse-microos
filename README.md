# uConsole CM5 on openSUSE MicroOS

This repository contains device tree overlays, drivers, and scripts to run the ClockworkPi uConsole with a Raspberry Pi Compute Module 5 (CM5) on openSUSE MicroOS.

## Hardware Status

| Component | Status | Notes |
|-----------|--------|-------|
| Display | ✅ Working | DSI panel via `drm_rp1_dsi` + `panel_cwu50` |
| Backlight | ✅ Working | OCP8178 LED driver via `ocp8178_bl` |
| Keyboard | ✅ Working | USB HID via DWC2 OTG in host mode |
| Trackball | ✅ Working | USB HID via DWC2 OTG in host mode |
| Joystick | ✅ Working | USB HID via DWC2 OTG in host mode |
| Audio | ✅ Working | RP1 I2S output via `snd_soc_rp1_aout` + SPDIF transmitter |
| Battery | ✅ Working | AXP221 PMIC, full monitoring and charging |
| PMIC | ✅ Working | AXP221 on i2c-13 via `i2c-gpio` bit-banging |
| WiFi | ✅ Working | BCM43455 via `brcmfmac` |
| Power Off | ⚠️ Workaround | Requires I2C-based poweroff script (see below) |

## Quick Start

### Prerequisites (Host)

- openSUSE MicroOS aarch64 raw image: [download](https://download.opensuse.org/ports/aarch64/tumbleweed/appliances/)
- `dtc` (device-tree-compiler)
- SSH access to the uConsole

### Flashing the Image

1. Download the openSUSE MicroOS Raspberry Pi image
2. Flash to CM5's eMMC using `rpiboot` + `dd`:

```bash
# Put CM5 in USB boot mode, then:
sudo rpiboot
# Wait for /dev/sda to appear
sudo dd if=openSUSE-MicroOS.aarch64-*.raw of=/dev/sda bs=4M status=progress conv=fsync
sudo sync
```

3. Mount the boot partition and copy the device tree:

```bash
sudo mount /dev/sda1 /mnt
sudo cp merged-clockworkpi.dtb /mnt/
```

4. Configure extraconfig.txt for uConsole CM5:

```bash
sudo tee /mnt/extraconfig.txt << 'EOF'
# uConsole CM5 configuration
device_tree=merged-clockworkpi.dtb
dtoverlay=usb-vbus-hog
dtoverlay=uconsole-audio
# Enable DWC2 USB controller for internal keyboard/trackball
dtoverlay=dwc2,dr_mode=host
EOF
sudo umount /mnt
```

5. Boot the uConsole and SSH in

> **Note:** After flashing, you will need to insert the CM5 into a Raspberry Pi CM5 IO Board (or similar carrier board with Ethernet/USB) for initial configuration. The uConsole's internal keyboard and display require drivers that aren't available until after the first boot setup is complete. Once configured with SSH keys and network access, you can move the CM5 to the uConsole.

### First Boot Setup (Recommended)

Use the setup script to configure user, SSH keys, and WiFi before first boot:

```bash
# After flashing the image and before removing from host:
sudo ./scripts/setup-first-boot.sh --device /dev/sda

# Or with all options:
sudo ./scripts/setup-first-boot.sh --device /dev/sda \
   --username myuser \
   --ssh-key-file ~/.ssh/id_rsa.pub \
   --wifi-ssid "MyNetwork" \
   --wifi-password "mypassword"
```

This script:
- Creates your user account with sudo access (wheel group)
- Configures SSH authorized_keys
- Sets up WiFi (optional)
- Copies all uConsole configuration files to the boot partition

### Required Systemd Services

The uConsole requires a few systemd services for proper operation:

```bash
# Create backlight initialization service
sudo tee /etc/systemd/system/uconsole-backlight.service << 'EOF'
[Unit]
Description=Initialize uConsole display and backlight at boot
After=systemd-modules-load.service local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/uconsole-backlight-init.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Create the init script
sudo tee /usr/local/bin/uconsole-backlight-init.sh << 'EOF'
#!/bin/bash
# Fix SELinux context for custom modules
for ko in /var/lib/modules-overlay/*.ko; do
   [ -f "$ko" ] && chcon -t modules_object_t "$ko" 2>/dev/null
done

# Load backlight driver if not loaded
if ! lsmod | grep -q ocp8178_bl; then
   modprobe ocp8178_bl 2>/dev/null || insmod /var/lib/modules-overlay/ocp8178_bl.ko 2>/dev/null
fi

# Wait for backlight and set brightness
count=0
while [ ! -e /sys/class/backlight/backlight@0/brightness ] && [ $count -lt 30 ]; do
   sleep 0.5; count=$((count + 1))
done
[ -e /sys/class/backlight/backlight@0/brightness ] && echo 8 > /sys/class/backlight/backlight@0/brightness

# Bind framebuffer console
[ -e /sys/class/vtconsole/vtcon1/bind ] && echo 1 > /sys/class/vtconsole/vtcon1/bind
EOF
sudo chmod +x /usr/local/bin/uconsole-backlight-init.sh
sudo systemctl enable uconsole-backlight.service
```

### Configuring Modprobe for Custom Modules

Since the ocp8178_bl module needs to be loaded from /var on MicroOS:

```bash
sudo tee /etc/modprobe.d/uconsole.conf << 'EOF'
# Load ocp8178_bl from overlay location
install ocp8178_bl /sbin/insmod /var/lib/modules-overlay/ocp8178_bl.ko
EOF
```

### Installing Drivers

The display and PMIC drivers are out-of-tree kernel modules. Deploy them to the device:

```bash
./scripts/deploy_and_build_drivers.sh <device_ip> <username> <ssh_key>
# Example:
./scripts/deploy_and_build_drivers.sh 192.168.1.100 myuser ~/.ssh/id_rsa
```

This will:
- Copy driver sources to the device
- Build them against the running kernel
- Install to `/lib/modules/$(uname -r)/extra/`
- Update module dependencies

> **Important**: On MicroOS, module installation happens in a new snapshot. You **must reboot** after installation for the display drivers to work. Without a reboot, you'll only see the backlight with no display content.

### Verifying Hardware

Run the hardware verification script on the uConsole:

```bash
./scripts/verify_uconsole_hardware.sh
```

Or via SSH:

```bash
ssh <user>@<device_ip> 'bash -s' < scripts/verify_uconsole_hardware.sh
```

## Technical Notes

### DWC2 USB Controller

The CM5 has the DWC2 USB OTG controller disabled by default (the CM4 had it enabled). The uConsole's internal USB hub (which hosts the keyboard MCU) connects to this legacy USB port, not the new DWC3 controllers via RP1.

The fix is to add `dtoverlay=dwc2,dr_mode=host` to extraconfig.txt, which enables the DWC2 controller at `usb@480000` in host mode.

### OCP8178 Backlight Driver

The OCP8178 is a 1-wire protocol LED driver. A fix was needed for the RP1 pinctrl driver - the GPIO requested as output wasn't always being set to output mode on boot. The fix adds an explicit `gpiod_direction_output()` call in `entry_1wire_mode()`.

### SELinux on MicroOS

MicroOS has SELinux enabled. Custom kernel modules in `/var/lib/modules-overlay/` need the correct SELinux context (`modules_object_t`) to be loaded. The `uconsole-backlight-init.sh` script handles this.

### Audio Driver

The RP1 audio output driver (`snd_soc_rp1_aout`) is required for audio. It provides the CPU DAI for the simple-audio-card which uses an SPDIF transmitter codec. The driver is loaded via modprobe install command from `/var/lib/modules-overlay/`.

There's a clock reparent warning during probe (`failed to reparent clk_audio_out to pll_audio_sec: -22`) but audio still works.

## Repository Structure

```
├── merged-clockworkpi.dtb     # Main device tree blob for CM5
├── merged-clockworkpi.dts     # Device tree source
├── overlay/                   # Files to deploy to target system
│   ├── boot/efi/extraconfig.txt
│   ├── etc/modprobe.d/uconsole.conf
│   ├── etc/modules-load.d/uconsole.conf
│   ├── etc/systemd/system/uconsole-backlight.service
│   ├── etc/systemd/system/axp221-poweroff.service
│   ├── etc/systemd/system/axp221-configure-pek.service
│   ├── usr/local/bin/uconsole-backlight-init.sh
│   └── usr/local/sbin/axp221-*.sh
├── overlays/                   # Device tree overlays
│   ├── usb-vbus-hog.dts       # USB VBUS GPIO enable
│   ├── uconsole-audio.dts     # Audio card configuration
│   └── rp1-i2c1-fix.dts       # I2C fix overlay
├── extracted-drivers/          # Out-of-tree kernel modules
│   ├── panel-cwu50/           # CWU50 DSI panel driver
│   ├── ocp8178_bl/            # OCP8178 backlight driver (with GPIO fix)
│   ├── rp1_aout/              # RP1 audio output driver
│   ├── axp20x_battery/        # AXP20x battery driver
│   └── axp20x_ac_power/       # AXP20x AC power driver
├── scripts/
│   ├── verify_uconsole_hardware.sh  # Hardware verification
│   ├── deploy_and_build_drivers.sh  # Driver deployment
│   ├── deploy_to_device.sh          # General file deployment
│   └── ...
└── kernel-patch/               # Kernel patches for reference
```

## Device Tree Configuration

The `merged-clockworkpi.dtb` includes:

- **DSI Panel**: CWU50 5" display at `/soc/axi/pcie@120000/.../dsi@0/panel@0`
- **PMIC**: AXP221 at `/i2c0if/pmic@34` via i2c-gpio (GPIO 0/1 on RP1)
- **Backlight**: OCP8178 LED driver with PWM control
- **USB VBUS**: GPIO 42/43 on RP1 for USB power enable (configured as output-high)

### Key Device Tree Nodes

```dts
// I2C-GPIO for PMIC communication
i2c0if {
   compatible = "i2c-gpio";
   gpios = <&rp1_gpio 0 GPIO_ACTIVE_HIGH>,  // SDA
         <&rp1_gpio 1 GPIO_ACTIVE_HIGH>;  // SCL
   
   pmic@34 {
      compatible = "x-powers,axp221";
      // Battery, regulators, ADC, etc.
   };
};

// DSI Panel
panel@0 {
   compatible = "clockwork,cwu50";
   // 720x1280 @ 60Hz via RP1 DSI
};
```

## Troubleshooting

### Keyboard/Trackball Not Working

The internal USB keyboard and trackball require the DWC2 USB controller in host mode.

1. Verify DWC2 overlay is enabled in `/boot/efi/extraconfig.txt`:
   ```bash
   grep dwc2 /boot/efi/extraconfig.txt
   # Should show: dtoverlay=dwc2,dr_mode=host
   ```

2. Check USB devices:
   ```bash
   lsusb | grep -i uconsole
   # Should show: Bus 001 Device 00X: ID 1eaf:0024 Leaflabs uConsole
   ```

3. Check input devices:
   ```bash
   ls /dev/input/by-id/ | grep uConsole
   # Should show keyboard, mouse, joystick entries
   ```

### Backlight Not Working

1. Check the backlight service:
   ```bash
   systemctl status uconsole-backlight.service
   ```

2. Check GPIO state (should be "out hi"):
   ```bash
   sudo cat /sys/kernel/debug/gpio | grep backlight
   # Should show: gpio-9 (GPIO9 |backlight-control) out hi
   ```

3. Manually set brightness:
   ```bash
   echo 8 | sudo tee /sys/class/backlight/backlight@0/brightness
   ```

### Display Not Working (Backlight Only)

If you see only the backlight but no display content after boot:

1. **Reboot required after module installation**: On MicroOS, after installing kernel modules via `transactional-update`, you must reboot for changes to take effect. The display drivers won't work until the new snapshot is active.

2. Check for deferred probe timeout in dmesg:
   ```bash
   sudo dmesg | grep -i "deferred probe timeout"
   # If you see this for drm-rp1-dsi, the panel module may not have loaded in time
   ```
   
   **Note**: A 60-second boot delay is expected due to a circular dependency between the DSI controller and panel in the device tree. The kernel's `fw_devlink` defers probing until `deferred_probe_timeout` expires. To reduce this delay, set `deferred_probe_timeout=5` in `/etc/default/grub` and regenerate the GRUB config.

3. Check driver loading:
   ```bash
   lsmod | grep -E "drm_rp1_dsi|panel_cwu50"
   # Both modules should be loaded
   ```

4. Check DRM connector status:
   ```bash
   cat /sys/class/drm/card0-DSI-1/status
   # Should show: connected
   ```

5. Verify panel initialization in dmesg:
   ```bash
   sudo dmesg | grep -i cwu50
   # Should show: "Detected old panel type" and "rp1dsi_host_attach"
   ```

6. If modules loaded but display still blank, try rebinding:
   ```bash
   echo 1f00130000.dsi | sudo tee /sys/bus/platform/drivers/drm-rp1-dsi/unbind
   sleep 1
   echo 1f00130000.dsi | sudo tee /sys/bus/platform/drivers/drm-rp1-dsi/bind
   ```

### Battery/PMIC Not Working

1. Check i2c-gpio driver:
   ```bash
   lsmod | grep i2c_gpio
   ```

2. Check I2C bus:
   ```bash
   ls /sys/bus/i2c/devices/
   # Should show i2c-13 and 13-0034
   ```

3. Check power supply:
   ```bash
   cat /sys/class/power_supply/axp20x-battery/status
   ```

### Battery-Only Boot Not Working

The uConsole may not boot when running on battery alone (without USB power connected). This is a **bootloader/firmware-level issue**, not a Linux kernel driver issue.

**Root Cause**: The AXP221 PMIC registers that configure power-on sources are set by the Linux kernel driver *after* boot - but if the PMIC doesn't allow battery power-on, the system never boots far enough for the driver to load.

**Workaround**:
1. Always connect USB power for initial boot
2. Once booted, the kernel driver configures the PMIC for future battery boots
3. As long as the battery doesn't fully discharge, subsequent battery boots should work

**Known PMIC registers affected**:
- `AXP20X_VBUS_IPSOUT_MGMT (0x30)` - VBUS/IPSOUT power path
- `AXP20X_OFF_CTRL (0x32)` - Power-off control (bit 3 = battery power enable, bit 7 = power off)
- `AXP20X_PEK_KEY (0x36)` - Power Enable Key configuration (bits 0-1 = shutdown timeout)

### Shutdown/Reboot Doesn't Power Off Device

If `shutdown` or `reboot` commands halt the system but the power LED stays on:

**Cause**: The AXP221 PMIC IRQ is disabled in the device tree (to fix probe failures with RP1 GPIO). This also disables the kernel's normal power-off handler.

**Solution**: Install the I2C-based poweroff scripts from the overlay directory:

1. Copy the scripts to the device:
   ```bash
   sudo install -m 755 overlay/usr/local/sbin/axp221-poweroff.sh /usr/local/sbin/
   sudo install -m 755 overlay/usr/local/sbin/axp221-configure-pek.sh /usr/local/sbin/
   sudo install -m 644 overlay/etc/systemd/system/axp221-*.service /etc/systemd/system/
   sudo systemctl enable axp221-poweroff.service axp221-configure-pek.service
   ```

2. Configure the hardware power button (4-second hold to force power off):
   ```bash
   sudo /usr/local/sbin/axp221-configure-pek.sh
   ```

3. For manual power off via I2C:
   ```bash
   sudo i2cset -y 13 0x34 0x32 0x80
   ```

### No Network After Boot

1. Check WiFi interface:
   ```bash
   ip link show wlan0
   ```

2. Check wpa_supplicant:
   ```bash
   sudo systemctl status wpa_supplicant
   ```

## Sway Desktop Environment

The repository includes a complete Sway configuration optimized for the uConsole CM5, including:

- **Sway**: Wayland compositor with DSI display rotation
- **Waybar**: Status bar with battery, backlight, WiFi, and audio modules
- **wofi**: Application launcher
- **kitty**: GPU-accelerated terminal (primary)
- **foot**: Lightweight Wayland terminal (fallback)
- **swaylock**: Screen locker with visible indicator ring
- **swayidle**: Idle management for screen timeout and suspend

### Installing Sway

Run the installation script on the uConsole:

```bash
# Option 1: Direct install (downloads from GitHub)
curl -sSL https://raw.githubusercontent.com/GeoDerp/uconsole-cm5-opensuse-microos/master/scripts/install-sway-uconsole.sh | bash

# Option 2: Clone and run locally
git clone https://github.com/GeoDerp/uconsole-cm5-opensuse-microos.git
cd uconsole-cm5-opensuse-microos
./scripts/install-sway-uconsole.sh
```

After installation, **reboot** to activate the new snapshot with Sway packages.

### Post-Install Configuration

1. Start Sway manually after reboot:
   ```bash
   sway
   ```

2. Or configure auto-start on TTY1 by adding to `~/.bash_profile`:
   ```bash
   if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
       exec sway
   fi
   ```

### Key Bindings

The configuration uses **Alt** as the modifier key for compatibility with uConsole's compact keyboard:

| Key Binding | Action |
|-------------|--------|
| `Alt+Return` | Open terminal (kitty) |
| `Alt+d` | Open app launcher (wofi) |
| `Alt+Shift+q` | Close focused window |
| `Alt+h/j/k/l` | Focus left/down/up/right |
| `Alt+Shift+h/j/k/l` | Move window left/down/up/right |
| `Alt+1-0` | Switch to workspace 1-10 |
| `Alt+Shift+1-0` | Move window to workspace 1-10 |
| `Alt+[` | Decrease brightness |
| `Alt+]` | Increase brightness |
| `Alt+Shift+[` | Decrease volume |
| `Alt+Shift+]` | Increase volume |
| `Alt+b` | Toggle waybar |
| `Alt+f` | Fullscreen |
| `Alt+v` | Split vertical |
| `Alt+g` | Split horizontal |
| `Alt+Shift+c` | Reload sway config |
| `Alt+Shift+e` | Exit sway |
| `Alt+Escape` | Lock screen |
| `Alt+Shift+p` | Power off (with confirmation) |
| `Alt+Shift+s` | Suspend |

#### uConsole Fn Key Notes

The uConsole keyboard firmware handles Fn key combinations internally. Some key combinations:

| Fn + Key | Action |
|----------|--------|
| `Fn+[` / `Fn+]` | Brightness down/up (via XF86 keys) |
| `Fn+Volume` | Mute toggle |
| `Fn+o` | Print screen |
| `Fn+i` | Insert |
| `Fn+h/j/k/u` | Home/End/PageDown/PageUp |
| `Fn+Esc` | **Keyboard lock** (internal, NOT passed to Linux) |

> **Note**: `Fn+Esc` locks the keyboard at the firmware level and does NOT send an event to Linux. Use `Alt+Escape` for lock screen instead.

See `docs/CM5-UCONSOLE-KNOWLEDGE-BASE.md` for complete Fn key reference.

### Lock Screen

The screen locks automatically after 5 minutes of inactivity and on boot. To lock manually:

```bash
swaylock
# Or use: Alt+Escape
```

### Optional: wpgtk Dynamic Theming

For dynamic color themes based on your wallpaper, install wpgtk:

```bash
./scripts/install-sway-uconsole.sh --with-wpgtk
```

Then set a wallpaper:
```bash
wpg -s ~/Pictures/wallpaper.jpg
sway reload
```

## License

MIT License - see [LICENSE](LICENSE) for details.

Note: Kernel driver sources in `extracted-drivers/` are derived from the Linux
kernel and ClockworkPi and retain their original GPL-2.0 license.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## Credits

- **[Rex](https://github.com/clockworkpi)** - CM5 hardware support and uConsole kernel patches 🙏
- ClockworkPi for the uConsole hardware and original CM4 software
- Raspberry Pi Foundation for the CM5/BCM2712/RP1 and device tree sources
- Wallpaper: [*Still Life with Artichokes and a Parrot*](https://www.nga.gov/artworks/102987-still-life-artichokes-and-parrot) - Luis Egidio Meléndez, 1775-1780, National Gallery of Art


