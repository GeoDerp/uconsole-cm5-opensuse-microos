# uConsole CM5 Sway Setup

This directory contains sway and waybar configurations optimized for the ClockworkPi uConsole with CM5 running openSUSE MicroOS.

## Hardware Support

- **Display**: 720x1280 DSI panel (rotated to 1280x720 landscape)
- **Keyboard**: ClockworkPI uConsole Keyboard (USB HID)
- **Trackball**: ClockworkPI uConsole Mouse (USB HID)
- **Battery**: AXP20x PMIC (axp20x-battery)
- **Backlight**: OCP8178 (backlight@0) with 9 brightness levels
- **Audio**: PipeWire + WirePlumber

## Installation

### 1. Install packages (MicroOS transactional-update)

```bash
sudo transactional-update --non-interactive pkg install sway waybar foot brightnessctl pipewire pipewire-pulseaudio wireplumber playerctl wl-clipboard grim slurp swaylock swayidle fontawesome-fonts google-droid-fonts xdg-desktop-portal-wlr seatd
sudo reboot
```

### 2. Configure seatd

```bash
# Create seat group and add user
sudo groupadd -r seat
sudo usermod -aG seat $USER

# Create seatd systemd service
sudo tee /etc/systemd/system/seatd.service << 'EOF'
[Unit]
Description=Seat management daemon
Documentation=man:seatd(1)

[Service]
Type=simple
ExecStart=/usr/bin/seatd -g seat
Restart=always
RestartSec=1

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now seatd
```

### 3. Configure autologin (optional)

```bash
sudo mkdir -p /etc/systemd/system/getty@tty1.service.d/
sudo tee /etc/systemd/system/getty@tty1.service.d/autologin.conf << 'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\u' --noclear --autologin YOUR_USERNAME %I $TERM
EOF
```

### 4. Deploy configurations

```bash
mkdir -p ~/.config/sway ~/.config/waybar ~/.config/foot

# Copy from this directory
cp sway/config ~/.config/sway/
cp waybar/config ~/.config/waybar/
cp waybar/style.css ~/.config/waybar/
cp foot/foot.ini ~/.config/foot/
```

### 5. Auto-start sway

Add to `~/.bash_profile`:

```bash
if [ -z "$WAYLAND_DISPLAY" ] && [ "$XDG_VTNR" = "1" ]; then
    export LIBSEAT_BACKEND=seatd
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    exec sway
fi
```

### 6. Reboot

```bash
sudo reboot
```

## Key Bindings

| Key Combo | Action |
|-----------|--------|
| Alt+Enter | Open terminal (foot) |
| Alt+d | Open app launcher (wofi) |
| Alt+Shift+q | Close window |
| Alt+Shift+r | Reload sway config |
| Alt+h/j/k/l | Focus left/down/up/right |
| Alt+1-5 | Switch workspace |
| Alt+Shift+1-5 | Move window to workspace |
| Alt+f | Toggle fullscreen |
| Alt+Shift+Space | Toggle floating |
| Alt+r | Enter resize mode |
| Alt+] | Brightness up |
| Alt+[ | Brightness down |
| Print | Screenshot |
| Mod4+l | Lock screen |

## Waybar Modules

- **Workspaces**: Current workspace indicator
- **Clock**: Time (click for date)
- **PulseAudio**: Volume control (scroll to adjust, click to mute)
- **Backlight**: Screen brightness (scroll to adjust)
- **Battery**: AXP20x battery status with charging indicator

## Files

- `sway/config` - Main sway configuration
- `waybar/config` - Waybar modules and layout
- `waybar/style.css` - Waybar theme (dark, compact for small screen)
- `foot/foot.ini` - Terminal configuration (dark theme, compact)

## Troubleshooting

### Sway won't start

Check seatd is running:
```bash
systemctl status seatd
```

Check user is in seat group:
```bash
groups $USER
```

### Display not rotating

The display should auto-rotate via `transform 90` in sway config. Check:
```bash
swaymsg -t get_outputs
```

### Battery not showing

Ensure AXP20x driver is loaded:
```bash
ls /sys/class/power_supply/
# Should show axp20x-battery
```

### Brightness controls not working

Check backlight device:
```bash
ls /sys/class/backlight/
brightnessctl -d 'backlight@0' set +1
```
