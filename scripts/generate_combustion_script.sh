#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 <username> <password> [path_to_ssh_pub_key]"
    echo "Generates a Combustion script to create a user on first boot for openSUSE MicroOS."
    echo "Example: $0 uconsole mypassword ~/.ssh/id_rsa.pub"
    exit 1
}

if [ "$#" -lt 2 ]; then
    usage
fi

USERNAME="$1"
PASSWORD="$2"
SSH_KEY_FILE="${3:-}"

OUT_DIR="combustion"
SCRIPT_FILE="$OUT_DIR/script"

mkdir -p "$OUT_DIR"

cat <<EOF > "$SCRIPT_FILE"
#!/bin/bash
# combustion: network

echo "=== Running Combustion First-Boot Setup ==="

# Create user and add to wheel group for sudo access
useradd -m -G wheel -s /bin/bash "$USERNAME"

# Set password
echo "$USERNAME:$PASSWORD" | chpasswd

EOF

if [ -n "$SSH_KEY_FILE" ] && [ -f "$SSH_KEY_FILE" ]; then
    SSH_KEY=$(cat "$SSH_KEY_FILE")
    cat <<EOF >> "$SCRIPT_FILE"
# Set up SSH Key
mkdir -p /home/$USERNAME/.ssh
echo "$SSH_KEY" > /home/$USERNAME/.ssh/authorized_keys
chown -R $USERNAME:$USERNAME /home/$USERNAME/.ssh
chmod 700 /home/$USERNAME/.ssh
chmod 600 /home/$USERNAME/.ssh/authorized_keys
EOF
    echo "Added SSH key to combustion script from: $SSH_KEY_FILE"
fi

chmod +x "$SCRIPT_FILE"

echo "=========================================================="
echo "✅ Combustion script generated at: $SCRIPT_FILE"
echo "=========================================================="
echo "To use this on your uConsole:"
echo "1. Format a USB flash drive with the label 'combustion' (FAT32 or ext4)."
echo "2. Copy the entire 'combustion' folder to the root of the USB drive."
echo "   (The final path must be: [USB_ROOT]/combustion/script)"
echo "3. Plug the USB drive into the uConsole before turning it on for the first time."
echo "4. openSUSE MicroOS will automatically run the script, create your user, and set up SSH!"
echo "=========================================================="
