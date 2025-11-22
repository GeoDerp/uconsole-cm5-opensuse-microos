#!/bin/bash
# verify_uconsole_hardware.sh - Verify all uConsole CM5 hardware on openSUSE MicroOS
#
# This script checks all uConsole hardware components and reports their status.
# Run this on the uConsole device after booting with the customized device tree.
#
# Usage: ./verify_uconsole_hardware.sh [--json]

set -euo pipefail

JSON_OUTPUT=false
if [[ "${1:-}" == "--json" ]]; then
    JSON_OUTPUT=true
fi

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

declare -A RESULTS

check_pass() {
    local component="$1"
    local message="$2"
    RESULTS["$component"]="PASS:$message"
    if ! $JSON_OUTPUT; then
        echo -e "${GREEN}[PASS]${NC} $component: $message"
    fi
}

check_fail() {
    local component="$1"
    local message="$2"
    RESULTS["$component"]="FAIL:$message"
    if ! $JSON_OUTPUT; then
        echo -e "${RED}[FAIL]${NC} $component: $message"
    fi
}

check_warn() {
    local component="$1"
    local message="$2"
    RESULTS["$component"]="WARN:$message"
    if ! $JSON_OUTPUT; then
        echo -e "${YELLOW}[WARN]${NC} $component: $message"
    fi
}

print_header() {
    if ! $JSON_OUTPUT; then
        echo ""
        echo "=============================================="
        echo "  uConsole CM5 Hardware Verification"
        echo "  openSUSE MicroOS"
        echo "=============================================="
        echo ""
    fi
}

# Check Display
check_display() {
    local status=""
    
    # Check DRM connector status
    if [[ -f /sys/class/drm/card1-DSI-1/status ]]; then
        status=$(cat /sys/class/drm/card1-DSI-1/status)
    elif [[ -f /sys/class/drm/card0-DSI-1/status ]]; then
        status=$(cat /sys/class/drm/card0-DSI-1/status)
    else
        # Try to find any DSI connector
        status=$(cat /sys/class/drm/*/status 2>/dev/null | head -1 || echo "unknown")
    fi
    
    # Check drivers
    local dsi_loaded=$(lsmod | grep -c drm_rp1_dsi || echo "0")
    local panel_loaded=$(lsmod | grep -c panel_cwu50 || echo "0")
    
    if [[ "$status" == "connected" ]] && [[ "$dsi_loaded" -gt 0 ]] && [[ "$panel_loaded" -gt 0 ]]; then
        check_pass "Display" "Connected, drm_rp1_dsi + panel_cwu50 loaded"
    elif [[ "$status" == "connected" ]]; then
        check_warn "Display" "Connected but some drivers may be missing"
    else
        check_fail "Display" "Status: $status, DSI: $dsi_loaded, Panel: $panel_loaded"
    fi
}

# Check Backlight
check_backlight() {
    if [[ -d /sys/class/backlight/backlight@0 ]]; then
        local brightness=$(cat /sys/class/backlight/backlight@0/brightness)
        local max=$(cat /sys/class/backlight/backlight@0/max_brightness)
        local ocp_loaded=$(lsmod | grep -c ocp8178_bl || echo "0")
        
        if [[ "$ocp_loaded" -gt 0 ]]; then
            check_pass "Backlight" "ocp8178_bl driver, brightness: $brightness/$max"
        else
            check_warn "Backlight" "Working ($brightness/$max) but ocp8178_bl not loaded"
        fi
    else
        check_fail "Backlight" "No backlight device found"
    fi
}

# Check Battery/PMIC
check_battery() {
    if [[ -d /sys/class/power_supply/axp20x-battery ]]; then
        local status=$(cat /sys/class/power_supply/axp20x-battery/status 2>/dev/null || echo "Unknown")
        local capacity=$(cat /sys/class/power_supply/axp20x-battery/capacity 2>/dev/null || echo "0")
        local voltage_raw=$(cat /sys/class/power_supply/axp20x-battery/voltage_now 2>/dev/null || echo "0")
        local voltage=$(echo "scale=3; $voltage_raw / 1000000" | bc)
        
        check_pass "Battery" "$status, ${capacity}%, ${voltage}V"
    else
        check_fail "Battery" "No battery device found (axp20x-battery missing)"
    fi
}

# Check PMIC (AXP221)
check_pmic() {
    if [[ -d /sys/bus/i2c/devices/13-0034 ]]; then
        local axp_loaded=$(lsmod | grep -c axp20x_i2c || echo "0")
        local regulators=$(ls /sys/bus/i2c/devices/13-0034/regulator/ 2>/dev/null | wc -l || echo "0")
        
        if [[ "$axp_loaded" -gt 0 ]]; then
            check_pass "PMIC" "AXP221 at i2c-13:0x34, $regulators regulators"
        else
            check_warn "PMIC" "Device found but axp20x_i2c not loaded"
        fi
    else
        check_fail "PMIC" "AXP221 not found on i2c-13"
    fi
}

# Check I2C-GPIO
check_i2c_gpio() {
    local i2c_gpio_loaded=$(lsmod | grep -c i2c_gpio || echo "0")
    local i2c_13_exists=$(ls /sys/bus/i2c/devices/ | grep -c "^i2c-13$" || echo "0")
    
    if [[ "$i2c_gpio_loaded" -gt 0 ]] && [[ "$i2c_13_exists" -gt 0 ]]; then
        check_pass "I2C-GPIO" "i2c-gpio driver loaded, i2c-13 bus available"
    elif [[ "$i2c_gpio_loaded" -gt 0 ]]; then
        check_warn "I2C-GPIO" "Driver loaded but i2c-13 not found"
    else
        check_fail "I2C-GPIO" "i2c-gpio driver not loaded"
    fi
}

# Check WiFi
check_wifi() {
    if ip link show wlan0 &>/dev/null; then
        local state=$(cat /sys/class/net/wlan0/operstate 2>/dev/null || echo "unknown")
        local ip_addr=$(ip -4 addr show wlan0 2>/dev/null | grep -oP 'inet \K[\d.]+' || echo "none")
        
        if [[ "$state" == "up" ]] && [[ "$ip_addr" != "none" ]]; then
            check_pass "WiFi" "wlan0 UP, IP: $ip_addr"
        elif [[ "$state" == "up" ]]; then
            check_warn "WiFi" "wlan0 UP but no IP address"
        else
            check_warn "WiFi" "wlan0 exists but state: $state"
        fi
    else
        check_fail "WiFi" "wlan0 interface not found"
    fi
}

# Check USB
check_usb() {
    local usb_count=$(ls /sys/bus/usb/devices/ 2>/dev/null | grep -v "^usb" | grep -v ":" | wc -l)
    local xhci_loaded=$(lsmod | grep -c xhci_hcd || echo "0")
    local hubs=$(ls /sys/bus/usb/devices/ 2>/dev/null | grep "^usb" | wc -l)
    
    if [[ "$usb_count" -gt 0 ]]; then
        check_pass "USB" "$usb_count downstream device(s), $hubs root hub(s)"
    elif [[ "$xhci_loaded" -gt 0 ]] && [[ "$hubs" -gt 0 ]]; then
        check_warn "USB" "Controllers working ($hubs hubs) but no devices detected"
    else
        check_fail "USB" "USB subsystem not working"
    fi
}

# Check USB Keyboard (specific check)
check_usb_keyboard() {
    # Look for ClockworkPi uConsole keyboard
    local kbd_found=$(cat /sys/bus/usb/devices/*/product 2>/dev/null | grep -ci "uconsole\|clockwork" || echo "0")
    local hid_loaded=$(lsmod | grep -c "^hid " || lsmod | grep -c "hid_generic" || echo "0")
    
    if [[ "$kbd_found" -gt 0 ]]; then
        check_pass "USB Keyboard" "uConsole keyboard detected"
    else
        # This is expected to fail on CM5 due to hardware limitation
        check_warn "USB Keyboard" "Not detected - CM5 adapter limitation (see README)"
    fi
}

# Print summary
print_summary() {
    if $JSON_OUTPUT; then
        echo "{"
        local first=true
        for key in "${!RESULTS[@]}"; do
            if ! $first; then echo ","; fi
            first=false
            local value="${RESULTS[$key]}"
            local status="${value%%:*}"
            local message="${value#*:}"
            echo "  \"$key\": {\"status\": \"$status\", \"message\": \"$message\"}"
        done
        echo "}"
    else
        echo ""
        echo "=============================================="
        echo "  Summary"
        echo "=============================================="
        
        local pass_count=0
        local fail_count=0
        local warn_count=0
        
        for key in "${!RESULTS[@]}"; do
            local status="${RESULTS[$key]%%:*}"
            case "$status" in
                PASS) ((pass_count++)) ;;
                FAIL) ((fail_count++)) ;;
                WARN) ((warn_count++)) ;;
            esac
        done
        
        echo ""
        echo -e "  ${GREEN}PASS${NC}: $pass_count"
        echo -e "  ${YELLOW}WARN${NC}: $warn_count"
        echo -e "  ${RED}FAIL${NC}: $fail_count"
        echo ""
        
        if [[ $fail_count -eq 0 ]]; then
            echo -e "${GREEN}All critical hardware checks passed!${NC}"
        else
            echo -e "${RED}Some hardware checks failed. See details above.${NC}"
        fi
        echo ""
    fi
}

# Main
print_header
check_display
check_backlight
check_battery
check_pmic
check_i2c_gpio
check_wifi
check_usb
check_usb_keyboard
print_summary

# Exit with error if any critical component failed
for key in "Display" "Battery" "PMIC"; do
    if [[ "${RESULTS[$key]:-}" == FAIL:* ]]; then
        exit 1
    fi
done

exit 0
