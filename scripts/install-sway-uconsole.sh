#!/bin/bash
# =============================================================================
# install-sway-uconsole.sh
# Install and configure Sway window manager for ClockworkPi uConsole on
# openSUSE MicroOS (transactional system)
#
# This script installs Sway, Waybar, and supporting tools optimized for:
# - uConsole DSI display (720x1280, rotated to landscape)
# - AXP20x battery/PMIC monitoring
# - ClockworkPI keyboard and trackball
# - OCP8178 backlight control
#
# Usage:
#   Run on the uConsole device:
#   curl -sSL https://raw.githubusercontent.com/GeoDerp/uconsole-cm5-opensuse-microos/master/scripts/install-sway-uconsole.sh | bash
#
#   Or clone the repo and run:
#   ./scripts/install-sway-uconsole.sh
#
# After installation, reboot and Sway will start automatically on TTY1.
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Repository base URL for config files
REPO_BASE="https://raw.githubusercontent.com/GeoDerp/uconsole-cm5-opensuse-microos/master"
CONFIG_BASE="${REPO_BASE}/overlay/etc/skel/.config"

# Check if running on MicroOS
check_system() {
    log_info "Checking system requirements..."
    
    if ! command -v transactional-update &> /dev/null; then
        log_error "This script requires openSUSE MicroOS with transactional-update"
        exit 1
    fi
    
    if [[ $(uname -m) != "aarch64" ]]; then
        log_warn "This script is designed for aarch64 (ARM64) systems"
    fi
    
    # Check for uConsole hardware
    if [[ -d /sys/class/power_supply/axp20x-battery ]]; then
        log_success "AXP20x battery detected (uConsole PMIC)"
    else
        log_warn "AXP20x battery not detected - battery monitoring may not work"
    fi
    
    if [[ -d /sys/class/backlight/backlight@0 ]]; then
        log_success "OCP8178 backlight detected"
    else
        log_warn "Backlight not detected - brightness controls may not work"
    fi
    
    log_success "System check passed"
}

# Install packages via transactional-update
install_packages() {
    log_info "Installing Sway and dependencies..."
    log_info "This will create a new system snapshot. A reboot is required after."
    
    local PACKAGES=(
        # Sway and Wayland
        sway
        swaylock
        swayidle
        swaybg
        
        # Status bar and launcher
        waybar
        wofi
        
        # Terminals and utilities
        kitty
        foot
        brightnessctl
        playerctl
        grim
        slurp
        wl-clipboard
        
        # Audio (PipeWire)
        pipewire
        pipewire-pulseaudio
        pipewire-alsa
        wireplumber
        pavucontrol
        
        # Seat management
        seatd
        
        # Fonts - Noto Emoji for waybar icons, Droid/JetBrains for UI/terminal
        fontawesome-fonts
        google-droid-fonts
        google-noto-coloremoji-fonts
        jetbrains-mono-fonts
        
        # Polkit for privilege escalation
        polkit
    )
    
    log_info "Packages to install: ${PACKAGES[*]}"
    
    sudo transactional-update --non-interactive pkg install "${PACKAGES[@]}"
    
    log_success "Packages installed in new snapshot"
}

# Download config files from repository
download_configs() {
    log_info "Downloading configuration files from repository..."
    
    # Create config directories
    mkdir -p "$HOME/.config/sway"
    mkdir -p "$HOME/.config/waybar"
    mkdir -p "$HOME/.config/foot"
    mkdir -p "$HOME/Pictures"
    
    # Download sway config
    log_info "Downloading sway config..."
    if curl -sSL "${CONFIG_BASE}/sway/config" -o "$HOME/.config/sway/config"; then
        log_success "Sway config downloaded"
    else
        log_error "Failed to download sway config"
        return 1
    fi
    
    # Download waybar config
    log_info "Downloading waybar config..."
    if curl -sSL "${CONFIG_BASE}/waybar/config" -o "$HOME/.config/waybar/config"; then
        log_success "Waybar config downloaded"
    else
        log_error "Failed to download waybar config"
        return 1
    fi
    
    # Download waybar style
    log_info "Downloading waybar style..."
    if curl -sSL "${CONFIG_BASE}/waybar/style.css" -o "$HOME/.config/waybar/style.css"; then
        log_success "Waybar style downloaded"
    else
        log_error "Failed to download waybar style"
        return 1
    fi
    
    # Download foot config
    log_info "Downloading foot config..."
    if curl -sSL "${CONFIG_BASE}/foot/foot.ini" -o "$HOME/.config/foot/foot.ini"; then
        log_success "Foot config downloaded"
    else
        log_error "Failed to download foot config"
        return 1
    fi
    
    # Download kitty config
    log_info "Downloading kitty config..."
    mkdir -p "$HOME/.config/kitty"
    if curl -sSL "${CONFIG_BASE}/kitty/kitty.conf" -o "$HOME/.config/kitty/kitty.conf"; then
        log_success "Kitty config downloaded"
    else
        log_warn "Failed to download kitty config (optional)"
    fi
    
    # Download wofi config
    log_info "Downloading wofi config..."
    mkdir -p "$HOME/.config/wofi"
    if curl -sSL "${CONFIG_BASE}/wofi/config" -o "$HOME/.config/wofi/config" && \
       curl -sSL "${CONFIG_BASE}/wofi/style.css" -o "$HOME/.config/wofi/style.css"; then
        log_success "Wofi config downloaded"
    else
        log_warn "Failed to download wofi config (optional)"
    fi
    
    log_success "All configuration files downloaded"
}

# Setup default wallpaper
setup_wallpaper() {
    log_info "Setting up default wallpaper..."
    
    # Create a simple gradient wallpaper if no wallpaper exists
    if [[ ! -f "$HOME/.config/sway/wallpaper.jpg" ]]; then
        if command -v magick &> /dev/null || command -v convert &> /dev/null; then
            # Create a dark gradient wallpaper matching the theme
            log_info "Creating default gradient wallpaper..."
            local convert_cmd="convert"
            command -v magick &> /dev/null && convert_cmd="magick"
            $convert_cmd -size 1280x720 gradient:'#12100d-#2a2520' "$HOME/.config/sway/wallpaper.jpg" 2>/dev/null
            if [[ -f "$HOME/.config/sway/wallpaper.jpg" ]]; then
                log_success "Default wallpaper created"
            else
                log_warn "Could not create wallpaper - using solid color fallback"
            fi
        else
            log_warn "ImageMagick not available - sway will use solid color background"
            log_info "Install ImageMagick later or add your own wallpaper to ~/.config/sway/wallpaper.jpg"
        fi
    else
        log_success "Wallpaper already exists"
    fi
    
    # If user provides a custom wallpaper, resize it for the uConsole display
    if [[ -n "$CUSTOM_WALLPAPER" && -f "$CUSTOM_WALLPAPER" ]]; then
        log_info "Resizing custom wallpaper for uConsole display (1280x720)..."
        if command -v magick &> /dev/null || command -v convert &> /dev/null; then
            local convert_cmd="convert"
            command -v magick &> /dev/null && convert_cmd="magick"
            $convert_cmd "$CUSTOM_WALLPAPER" -resize 1280x720^ -gravity center -extent 1280x720 \
                "$HOME/.config/sway/wallpaper.jpg" 2>/dev/null
            log_success "Custom wallpaper installed and resized"
        else
            cp "$CUSTOM_WALLPAPER" "$HOME/.config/sway/wallpaper.jpg"
            log_warn "Wallpaper copied but not resized (ImageMagick not available)"
            log_info "Large wallpapers may cause display issues - consider resizing to 1280x720"
        fi
    fi
}

# Optional: Install uv and wpgtk for dynamic theming
setup_wpgtk() {
    echo ""
    echo -e "${YELLOW}Optional: Dynamic Theming with wpgtk${NC}"
    echo "wpgtk generates color schemes from your wallpaper."
    echo "This requires installing 'uv' (Python package manager) and 'wpgtk'."
    echo ""
    echo -n "Install wpgtk for dynamic theming? [y/N]: "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        log_info "Skipping wpgtk installation"
        return 0
    fi
    
    log_info "Installing uv (Python package manager)..."
    if curl -LsSf https://astral.sh/uv/install.sh | sh; then
        log_success "uv installed"
    else
        log_error "Failed to install uv"
        return 1
    fi
    
    # Source uv into current shell
    export PATH="$HOME/.local/bin:$PATH"
    
    log_info "Installing wpgtk via uv..."
    if uv tool install wpgtk; then
        log_success "wpgtk installed"
    else
        log_error "Failed to install wpgtk"
        return 1
    fi
    
    # Download wpgtk setup script and templates
    log_info "Downloading wpgtk configuration..."
    mkdir -p "$HOME/.config/wpg/templates"
    
    if curl -sSL "${CONFIG_BASE}/wpg/setup-wpgtk.sh" -o "$HOME/.config/wpg/setup-wpgtk.sh"; then
        chmod +x "$HOME/.config/wpg/setup-wpgtk.sh"
        log_success "wpgtk setup script downloaded"
    else
        log_warn "Failed to download wpgtk setup script"
    fi
    
    echo ""
    echo -e "${YELLOW}wpgtk Post-Install Steps:${NC}"
    echo "  1. Add a wallpaper to ~/Pictures/"
    echo "  2. Run: wpg -a ~/Pictures/your-wallpaper.jpg"
    echo "  3. Run: wpg -s your-wallpaper.jpg"
    echo "  4. Run: ~/.config/wpg/setup-wpgtk.sh (to register templates)"
    echo "  5. Reload sway: swaymsg reload"
    echo ""
    
    log_success "wpgtk setup complete"
}

# Setup seatd for Wayland seat management
setup_seatd() {
    log_info "Setting up seatd for seat management..."
    
    # Create seat group if it doesn't exist
    if ! getent group seat > /dev/null 2>&1; then
        log_info "Creating 'seat' group..."
        sudo groupadd seat
    fi
    
    # Add current user to seat group
    local CURRENT_USER="${SUDO_USER:-$USER}"
    if ! groups "$CURRENT_USER" | grep -q seat; then
        log_info "Adding $CURRENT_USER to 'seat' group..."
        sudo usermod -aG seat "$CURRENT_USER"
    fi
    
    # Create seatd service
    sudo tee /etc/systemd/system/seatd.service > /dev/null << 'SEATDSERVICE'
[Unit]
Description=Seat management daemon
Documentation=man:seatd(1)
Before=graphical.target

[Service]
Type=simple
ExecStart=/usr/bin/seatd -g seat
Restart=always
RestartSec=1

[Install]
WantedBy=multi-user.target
SEATDSERVICE

    sudo systemctl daemon-reload
    sudo systemctl enable seatd.service
    
    log_success "seatd service configured"
}

# Setup auto-start sway on login
setup_sway_autostart() {
    log_info "Configuring auto-start Sway on login..."
    
    # Create .bash_profile for auto-starting sway (avoid duplicates)
    if ! grep -q "Auto-start Sway" "$HOME/.bash_profile" 2>/dev/null; then
        cat >> "$HOME/.bash_profile" << 'BASHPROFILE'

# Auto-start Sway on TTY1
if [ -z "$WAYLAND_DISPLAY" ] && [ "$XDG_VTNR" = "1" ]; then
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    export LIBSEAT_BACKEND=seatd
    exec sway
fi
BASHPROFILE
    fi
    
    log_success "Sway configured to start after login on TTY1"
}

# Print post-install instructions
print_instructions() {
    echo ""
    echo "=============================================="
    echo -e "${GREEN}Installation Complete!${NC}"
    echo "=============================================="
    echo ""
    echo "A system reboot is required to activate the new snapshot."
    echo ""
    echo -e "${YELLOW}Key bindings:${NC}"
    echo "  Alt+Return     - Open terminal"
    echo "  Alt+d          - Application launcher (wofi)"
    echo "  Alt+Shift+q    - Close window"
    echo "  Alt+1-9        - Switch workspace"
    echo "  Alt+Shift+e    - Exit Sway"
    echo "  Alt+[ / Alt+]  - Brightness down/up"
    echo "  Print          - Screenshot"
    echo ""
    echo -e "${YELLOW}Hardware notes:${NC}"
    echo "  - Trackball sensitivity may vary (hardware limitation)"
    echo "  - Brightness has 10 levels (0-9)"
    echo "  - Battery status from AXP20x PMIC"
    echo ""
    echo -e "${YELLOW}Config files:${NC}"
    echo "  ~/.config/sway/config      - Sway window manager"
    echo "  ~/.config/waybar/          - Status bar"
    echo "  ~/.config/kitty/kitty.conf - Terminal (default)"
    echo "  ~/.config/foot/foot.ini    - Terminal (fallback)"
    echo "  ~/.config/wpg/             - wpgtk theming (optional)"
    echo ""
    echo -n -e "${BLUE}Reboot now? [y/N]:${NC} "
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        log_info "Rebooting..."
        sudo reboot
    else
        echo "Run 'sudo reboot' when ready to apply changes."
    fi
}

# Main installation flow
main() {
    echo "=============================================="
    echo "  uConsole Sway Installation Script"
    echo "  For openSUSE MicroOS on ClockworkPi uConsole"
    echo "=============================================="
    echo ""
    echo "Repository: https://github.com/GeoDerp/uconsole-cm5-opensuse-microos"
    echo ""
    
    check_system
    
    echo ""
    echo -e "${YELLOW}This will install Sway and configure it for uConsole.${NC}"
    echo -e "${YELLOW}A reboot will be required after installation.${NC}"
    echo ""
    echo -n "Continue? [y/N]: "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi
    
    install_packages
    download_configs
    setup_wallpaper
    setup_seatd
    setup_sway_autostart
    setup_wpgtk
    
    print_instructions
}

# Run main function
main "$@"
