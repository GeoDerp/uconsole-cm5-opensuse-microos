#!/bin/bash
# Setup wpgtk templates for uConsole CM5 Sway
# This script registers templates and applies the initial theme
# wpgtk is OPTIONAL - the configs work without it using fixed colors

set -e

WALLPAPER_DIR="$HOME/.config/sway"
WALLPAPER="$WALLPAPER_DIR/wallpaper.jpg"

# Ensure uv/wpg are in PATH
export PATH="$HOME/.local/bin:$PATH"

# Check if wpg is available
if ! command -v wpg &> /dev/null; then
    echo "wpg not found. Installing wpgtk via uv..."
    
    # Check if uv is installed
    if ! command -v uv &> /dev/null; then
        echo "Installing uv..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
        source "$HOME/.local/bin/env" 2>/dev/null || true
    fi
    
    # Install wpgtk using uv
    uv tool install wpgtk
    echo "wpgtk installed successfully."
fi

# Create directories if they don't exist
mkdir -p "$HOME/.config/sway"
mkdir -p "$HOME/.config/waybar"
mkdir -p "$HOME/.config/kitty"
mkdir -p "$HOME/.config/wofi"

echo "Registering wpgtk templates..."

# Add templates to wpgtk
# Template syntax: wpg -ta <config_file>
# wpgtk will track these files and replace {color0}, {color15}, etc. with actual colors
wpg -ta "$HOME/.config/waybar/style.css" 2>/dev/null || true
wpg -ta "$HOME/.config/kitty/kitty.conf" 2>/dev/null || true
wpg -ta "$HOME/.config/wofi/style.css" 2>/dev/null || true

echo "Templates registered."

# Check if wallpaper exists
if [ ! -f "$WALLPAPER" ]; then
    echo "Warning: Wallpaper not found at $WALLPAPER"
    echo "Please copy your wallpaper to $WALLPAPER and run:"
    echo "  $0"
    echo ""
    echo "Or specify a different wallpaper:"
    echo "  wpg -a /path/to/wallpaper.jpg"
    echo "  wpg -s /path/to/wallpaper.jpg"
    exit 0
fi

# Add wallpaper to wpgtk and set as active theme
echo "Adding wallpaper and generating colorscheme..."
wpg -a "$WALLPAPER"

echo "Applying theme from wallpaper..."
wpg -s "$WALLPAPER"

# Extract colors for sway config (sway config can't use wpgtk templates due to {} syntax)
echo ""
echo "Colors extracted from wallpaper:"
cat ~/.config/wpg/schemes/*.json 2>/dev/null | grep -E '"color[0-9]+"|"background"|"foreground"' | head -20

echo ""
echo "wpgtk setup complete!"
echo ""
echo "NOTE: Sway config uses fixed colors (extracted from wallpaper)."
echo "To update sway colors, edit ~/.config/sway/config and update the color variables."
echo ""
echo "To change themes:"
echo "  wpg -s /path/to/new/wallpaper.jpg"
echo ""
echo "To adjust colors:"
echo "  wpg -A /path/to/wallpaper.jpg  (auto-adjust)"
echo "  wpg (launch GUI if available)"
echo ""
echo "Please reload sway (Mod+Shift+c) to apply changes."
