
---

## Session Log: 2025-12-15 (Display & PMIC Voltage Fix)

### Critical Display Fix (Voltage Mismatch)
**Problem**: Display was unstable/black screen.
**Root Cause**: The device tree overlay configured the panel VCI supply to `reg_dcdc3` (1.8V), but the CWU50 panel requires `reg_aldo2` (3.3V).
**Solution**: Patched `clockworkpi-uconsole-cm5-overlay.dts` to use `&reg_aldo2` for `vci-supply`.

### PMIC Probe Fix
**Problem**: `axp20x-i2c` driver failed to probe due to IRQ conflict.
**Solution**: Commented out IRQ/interrupt properties in the PMIC device tree node. This allowed the driver to load in polling mode, enabling battery monitoring and power control.

---

## Session Log: 2025-12-17 (Final Hardware Stabilization)

### Display Reliability (Pin Swap Workaround)
**Problem**: Display initialization was flaky on boot due to a race condition between the 3.3V regulator ramp-up and the driver's reset signal.
**Solution**: Implemented a **GPIO Pin Swap** in the Device Tree overlay:
- `reset-gpio` mapped to dummy GPIO 10.
- `id-gpio` mapped to real Reset GPIO 8.
- Configured GPIO 8 with pull-down to force "Old Panel" detection.
**Result**: The driver detects "Old Panel" and toggles the "ID Pin" (physically the Reset Pin) with a timing sequence that reliably resets the panel on every boot.

### Power Button Finalization
**Hold (Hard Off)**:
- Configured AXP221 Register `0x36` to `0x58` (4s shutdown time, shutdown function enabled).
- Validated via `i2cget`.

**Tap (Soft Off)**:
- **Status**: **DISABLED**.
- **Reason**: The PMIC IRQ Status register (`0x44`) bit for Short Press is physically stuck HIGH (`0xFF` readback) on this unit.
- **Mitigation**: The `axp221-monitor.sh` script detects this stuck state on startup and **exits** to prevent an infinite shutdown loop.

### Backlight Driver Loading
**Problem**: Backlight was off because the kernel module was compiled for an older kernel version.
**Solution**:
1. Rebuilt drivers on-device using `deploy_and_build_drivers_snapshot.sh`.
2. Updated `uconsole.conf` to remove hardcoded paths (allow `modprobe` to find correct module).
3. Updated `uconsole-backlight-init.sh` to use `modprobe` and handle power cycling correctly.

### Startup Sequence
**Configuration**:
- **Default**: Boot to TTY1 (Text Console) with `getty`.
- **Graphical**: User logs in -> `systemd --user` starts `sway.service` automatically.
- **Swaylock**: Engages on Sway startup (security default).

**Final State**:
- **Display**: 100% Reliable.
- **Backlight**: Functional.
- **Shutdown**: Functional.
- **Sleep/Hibernate**: Not supported (Hardware limitation).
