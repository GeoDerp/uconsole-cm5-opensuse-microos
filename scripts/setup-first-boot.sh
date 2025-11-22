#!/bin/bash
# setup-first-boot.sh
# Configure a freshly flashed openSUSE MicroOS image for uConsole CM5
#
# This script mounts a flashed eMMC/SD card and configures:
# - User account (username, password, SSH keys)
# - WiFi network (optional)
# - Adds user to wheel/sudo group
# - Enables SSH access
#
# Usage: sudo ./scripts/setup-first-boot.sh [OPTIONS]
#
# Run this AFTER flashing the base MicroOS image but BEFORE first boot.

set -euo pipefail

# Default values
DEVICE=""
USERNAME=""
PASSWORD=""
SSH_PUBKEY=""
SSH_PUBKEY_FILE=""
WIFI_SSID=""
WIFI_PASSWORD=""
MOUNT_POINT="/mnt/uconsole"
AUTO_UNMOUNT=1
INTERACTIVE=1

usage() {
    cat <<EOF
Usage: sudo $0 [OPTIONS]

Configure a freshly flashed openSUSE MicroOS image for uConsole CM5.

Options:
  --device PATH         Block device (e.g., /dev/sda). Required.
  --username NAME       Username to create. Required.
  --password PASS       Password for user (will prompt if not provided)
  --ssh-key "KEY"       SSH public key string
  --ssh-key-file FILE   Path to SSH public key file (e.g., ~/.ssh/id_rsa.pub)
  --wifi-ssid SSID      WiFi network name (optional)
  --wifi-password PASS  WiFi password (optional, will prompt if SSID provided)
  --mount-point PATH    Where to mount partitions (default: /mnt/uconsole)
  --no-interactive      Don't prompt for missing values
  --no-unmount          Leave partitions mounted after setup
  --help                Show this help

Examples:
  # Interactive mode - prompts for everything
  sudo $0 --device /dev/sda

  # Non-interactive with all options
  sudo $0 --device /dev/sda \\
          --username myuser \\
          --password mypassword \\
          --ssh-key-file ~/.ssh/id_rsa.pub \\
          --wifi-ssid "MyNetwork" \\
          --wifi-password "wifipass"

  # Minimal - just user with SSH key
  sudo $0 --device /dev/sda --username myuser --ssh-key-file ~/.ssh/id_rsa.pub

EOF
    exit 0
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "[ERROR] $*" >&2
    exit 1
}

prompt_value() {
    local prompt="$1"
    local var_name="$2"
    local is_secret="${3:-0}"
    local default="${4:-}"
    local current_val="${!var_name:-}"

    if [[ -n "$current_val" ]]; then
        return 0
    fi

    if [[ "$INTERACTIVE" -eq 0 ]]; then
        if [[ -n "$default" ]]; then
            eval "$var_name='$default'"
        fi
        return 0
    fi

    if [[ -n "$default" ]]; then
        prompt="$prompt [$default]"
    fi

    if [[ "$is_secret" -eq 1 ]]; then
        read -rsp "$prompt: " value
        echo
    else
        read -rp "$prompt: " value
    fi

    if [[ -z "$value" && -n "$default" ]]; then
        value="$default"
    fi

    eval "$var_name='$value'"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --device) DEVICE="$2"; shift 2 ;;
        --username) USERNAME="$2"; shift 2 ;;
        --password) PASSWORD="$2"; shift 2 ;;
        --ssh-key) SSH_PUBKEY="$2"; shift 2 ;;
        --ssh-key-file) SSH_PUBKEY_FILE="$2"; shift 2 ;;
        --wifi-ssid) WIFI_SSID="$2"; shift 2 ;;
        --wifi-password) WIFI_PASSWORD="$2"; shift 2 ;;
        --mount-point) MOUNT_POINT="$2"; shift 2 ;;
        --no-interactive) INTERACTIVE=0; shift ;;
        --no-unmount) AUTO_UNMOUNT=0; shift ;;
        --help|-h) usage ;;
        *) error "Unknown option: $1" ;;
    esac
done

# Must be root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (use sudo)"
fi

# Prompt for required values
prompt_value "Block device (e.g., /dev/sda)" DEVICE
prompt_value "Username" USERNAME

if [[ -z "$DEVICE" ]]; then
    error "Device is required. Use --device or provide interactively."
fi

if [[ -z "$USERNAME" ]]; then
    error "Username is required. Use --username or provide interactively."
fi

# Validate device
if [[ ! -b "$DEVICE" ]]; then
    error "Device $DEVICE does not exist or is not a block device"
fi

# Load SSH key from file if specified
if [[ -n "$SSH_PUBKEY_FILE" && -z "$SSH_PUBKEY" ]]; then
    if [[ -f "$SSH_PUBKEY_FILE" ]]; then
        SSH_PUBKEY=$(cat "$SSH_PUBKEY_FILE")
        log "Loaded SSH key from $SSH_PUBKEY_FILE"
    else
        error "SSH key file not found: $SSH_PUBKEY_FILE"
    fi
fi

# Prompt for optional values
if [[ -z "$SSH_PUBKEY" && "$INTERACTIVE" -eq 1 ]]; then
    echo ""
    echo "SSH public key (optional - paste key or leave empty):"
    read -r SSH_PUBKEY
fi

if [[ -z "$PASSWORD" && "$INTERACTIVE" -eq 1 ]]; then
    prompt_value "Password for $USERNAME (leave empty for SSH-only auth)" PASSWORD 1
fi

if [[ -z "$WIFI_SSID" && "$INTERACTIVE" -eq 1 ]]; then
    prompt_value "WiFi SSID (optional, leave empty to skip)" WIFI_SSID
fi

if [[ -n "$WIFI_SSID" && -z "$WIFI_PASSWORD" && "$INTERACTIVE" -eq 1 ]]; then
    prompt_value "WiFi password" WIFI_PASSWORD 1
fi

# Show configuration
log "=== Configuration ==="
log "Device: $DEVICE"
log "Username: $USERNAME"
log "Password: ${PASSWORD:+(set)}${PASSWORD:-(not set)}"
log "SSH Key: ${SSH_PUBKEY:+(set)}${SSH_PUBKEY:-(not set)}"
log "WiFi SSID: ${WIFI_SSID:-(not configured)}"
log "Mount point: $MOUNT_POINT"
echo ""

if [[ "$INTERACTIVE" -eq 1 ]]; then
    read -rp "Continue? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy] ]]; then
        log "Aborted."
        exit 0
    fi
fi

# Detect partition layout
# MicroOS typically has: p1=EFI/boot, p2=root (or p3 depending on image)
log "Detecting partitions on $DEVICE..."
partprobe "$DEVICE" 2>/dev/null || true
sleep 1

# Find partitions
if [[ -b "${DEVICE}p1" ]]; then
    BOOT_PART="${DEVICE}p1"
    ROOT_PART="${DEVICE}p2"
    # Check if p3 exists (some images use p2 for boot, p3 for root)
    if [[ -b "${DEVICE}p3" ]]; then
        ROOT_PART="${DEVICE}p3"
    fi
elif [[ -b "${DEVICE}1" ]]; then
    BOOT_PART="${DEVICE}1"
    ROOT_PART="${DEVICE}2"
    if [[ -b "${DEVICE}3" ]]; then
        ROOT_PART="${DEVICE}3"
    fi
else
    error "Cannot find partitions on $DEVICE. Is it partitioned?"
fi

log "Boot partition: $BOOT_PART"
log "Root partition: $ROOT_PART"

# Create mount points
mkdir -p "$MOUNT_POINT/root" "$MOUNT_POINT/boot"

# Mount partitions
log "Mounting partitions..."
mount "$ROOT_PART" "$MOUNT_POINT/root"
mount "$BOOT_PART" "$MOUNT_POINT/boot"

cleanup() {
    if [[ "$AUTO_UNMOUNT" -eq 1 ]]; then
        log "Unmounting partitions..."
        umount "$MOUNT_POINT/boot" 2>/dev/null || true
        umount "$MOUNT_POINT/root" 2>/dev/null || true
        rmdir "$MOUNT_POINT/boot" "$MOUNT_POINT/root" "$MOUNT_POINT" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# Verify it's a MicroOS root
if [[ ! -d "$MOUNT_POINT/root/etc" ]]; then
    error "Root partition doesn't look like a Linux root filesystem"
fi

ROOT="$MOUNT_POINT/root"
BOOT="$MOUNT_POINT/boot"

# === Create user ===
log "Creating user: $USERNAME"

# Generate password hash if password provided
if [[ -n "$PASSWORD" ]]; then
    PASS_HASH=$(openssl passwd -6 "$PASSWORD")
else
    # Lock password (SSH key only)
    PASS_HASH="!"
fi

# Get next available UID (start at 1000)
NEXT_UID=1000
if [[ -f "$ROOT/etc/passwd" ]]; then
    while grep -q ":$NEXT_UID:" "$ROOT/etc/passwd" 2>/dev/null; do
        ((NEXT_UID++))
    done
fi

# Add user to passwd
if ! grep -q "^${USERNAME}:" "$ROOT/etc/passwd" 2>/dev/null; then
    echo "${USERNAME}:x:${NEXT_UID}:${NEXT_UID}:${USERNAME}:/home/${USERNAME}:/bin/bash" >> "$ROOT/etc/passwd"
    log "Added $USERNAME to /etc/passwd (UID: $NEXT_UID)"
else
    log "User $USERNAME already exists in /etc/passwd"
fi

# Add to shadow
if ! grep -q "^${USERNAME}:" "$ROOT/etc/shadow" 2>/dev/null; then
    echo "${USERNAME}:${PASS_HASH}:19700:0:99999:7:::" >> "$ROOT/etc/shadow"
    log "Added $USERNAME to /etc/shadow"
fi

# Create group
if ! grep -q "^${USERNAME}:" "$ROOT/etc/group" 2>/dev/null; then
    echo "${USERNAME}:x:${NEXT_UID}:" >> "$ROOT/etc/group"
    log "Created group $USERNAME"
fi

# Add to wheel group for sudo
if grep -q "^wheel:" "$ROOT/etc/group"; then
    if ! grep "^wheel:" "$ROOT/etc/group" | grep -q "$USERNAME"; then
        sed -i "s/^wheel:\(.*\)/wheel:\1,${USERNAME}/" "$ROOT/etc/group"
        # Clean up double commas or trailing commas
        sed -i 's/,:,/,/g; s/::/:/' "$ROOT/etc/group"
        sed -i "s/^wheel:x:\([0-9]*\):,/wheel:x:\1:/" "$ROOT/etc/group"
        log "Added $USERNAME to wheel group"
    fi
else
    echo "wheel:x:10:${USERNAME}" >> "$ROOT/etc/group"
    log "Created wheel group with $USERNAME"
fi

# Create home directory
HOME_DIR="$ROOT/home/${USERNAME}"
mkdir -p "$HOME_DIR"
chown "$NEXT_UID:$NEXT_UID" "$HOME_DIR"
chmod 700 "$HOME_DIR"
log "Created home directory: /home/${USERNAME}"

# === Setup SSH key ===
if [[ -n "$SSH_PUBKEY" ]]; then
    log "Configuring SSH key..."
    SSH_DIR="$HOME_DIR/.ssh"
    mkdir -p "$SSH_DIR"
    echo "$SSH_PUBKEY" >> "$SSH_DIR/authorized_keys"
    chmod 700 "$SSH_DIR"
    chmod 600 "$SSH_DIR/authorized_keys"
    chown -R "$NEXT_UID:$NEXT_UID" "$SSH_DIR"
    log "Added SSH key to /home/${USERNAME}/.ssh/authorized_keys"
fi

# Ensure sshd is enabled
if [[ -d "$ROOT/etc/systemd/system/multi-user.target.wants" ]]; then
    if [[ ! -L "$ROOT/etc/systemd/system/multi-user.target.wants/sshd.service" ]]; then
        ln -sf /usr/lib/systemd/system/sshd.service \
            "$ROOT/etc/systemd/system/multi-user.target.wants/sshd.service"
        log "Enabled sshd.service"
    fi
fi

# === Configure WiFi ===
if [[ -n "$WIFI_SSID" ]]; then
    log "Configuring WiFi: $WIFI_SSID"
    
    # NetworkManager connection file
    NM_CONN_DIR="$ROOT/etc/NetworkManager/system-connections"
    mkdir -p "$NM_CONN_DIR"
    
    cat > "$NM_CONN_DIR/${WIFI_SSID}.nmconnection" <<EOF
[connection]
id=${WIFI_SSID}
uuid=$(uuidgen)
type=wifi
autoconnect=true

[wifi]
mode=infrastructure
ssid=${WIFI_SSID}

[wifi-security]
auth-alg=open
key-mgmt=wpa-psk
psk=${WIFI_PASSWORD}

[ipv4]
method=auto

[ipv6]
method=auto
EOF
    
    chmod 600 "$NM_CONN_DIR/${WIFI_SSID}.nmconnection"
    log "Created WiFi connection: $WIFI_SSID"
fi

# === Copy uConsole configuration files ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

if [[ -d "$REPO_DIR/overlay" ]]; then
    log "Copying uConsole configuration files..."
    
    # Copy boot files
    if [[ -f "$REPO_DIR/overlay/boot/efi/extraconfig.txt" ]]; then
        cp "$REPO_DIR/overlay/boot/efi/extraconfig.txt" "$BOOT/"
        log "Copied extraconfig.txt"
    fi
    
    # Copy device tree
    if [[ -f "$REPO_DIR/merged-clockworkpi.dtb" ]]; then
        cp "$REPO_DIR/merged-clockworkpi.dtb" "$BOOT/"
        log "Copied merged-clockworkpi.dtb"
    fi
    
    # Copy overlays
    if [[ -d "$REPO_DIR/overlays" ]]; then
        mkdir -p "$BOOT/overlays"
        for dtbo in "$REPO_DIR"/overlays/*.dtbo; do
            if [[ -f "$dtbo" ]]; then
                cp "$dtbo" "$BOOT/overlays/"
                log "Copied $(basename "$dtbo")"
            fi
        done
    fi
    
    # Copy etc files
    if [[ -d "$REPO_DIR/overlay/etc" ]]; then
        cp -r "$REPO_DIR/overlay/etc/"* "$ROOT/etc/" 2>/dev/null || true
        log "Copied /etc configuration files"
    fi
    
    # Copy usr files
    if [[ -d "$REPO_DIR/overlay/usr" ]]; then
        mkdir -p "$ROOT/usr/local/bin"
        if [[ -f "$REPO_DIR/overlay/usr/local/bin/uconsole-backlight-init.sh" ]]; then
            cp "$REPO_DIR/overlay/usr/local/bin/uconsole-backlight-init.sh" "$ROOT/usr/local/bin/"
            chmod +x "$ROOT/usr/local/bin/uconsole-backlight-init.sh"
            log "Copied uconsole-backlight-init.sh"
        fi
    fi
fi

# Sync to ensure all writes complete
sync

log ""
log "=== Setup Complete ==="
log ""
log "User '$USERNAME' created with:"
log "  - Home directory: /home/$USERNAME"
log "  - Added to wheel group (sudo access)"
[[ -n "$SSH_PUBKEY" ]] && log "  - SSH key configured"
[[ -n "$PASSWORD" ]] && log "  - Password set"
[[ -n "$WIFI_SSID" ]] && log "  - WiFi configured: $WIFI_SSID"
log ""
log "uConsole CM5 files copied to boot partition."
log ""
log "Next steps:"
log "  1. Safely eject the device"
log "  2. Insert CM5 into uConsole and power on"
log "  3. Connect via SSH: ssh $USERNAME@<device-ip>"
log "  4. Build drivers on device: ./scripts/deploy_and_build_drivers.sh"
log ""
