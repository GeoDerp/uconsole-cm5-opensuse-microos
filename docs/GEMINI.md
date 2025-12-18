# uConsole CM5 Hardware Issues & Workarounds

## Persistent Hardware Faults

### AXP221 PMIC Sensor Status
**Problem History**: Initially, the PMIC reported 0V battery voltage, leading to immediate shutdowns.
**Resolution**: A **Hard Reset** (removing batteries and power for 30s) successfully reset the PMIC internal logic. The ADC is now functional and reports valid voltage (~3.7V-4.2V) via direct I2C reads.
**Current Status**:
*   **Hardware**: **Functional**. Charging, voltage sensing, and power path management are working correctly at the hardware level.
*   **Software (Driver)**: **Probe Failure**. The `axp20x_battery` kernel driver fails to attach to the PMIC device tree node. Consequently, `/sys/class/power_supply` is not populated.
*   **Impact**: Applications like **Waybar** cannot display battery percentage because the standard interface is missing.
*   **Workaround**: Battery status can only be checked manually via `sudo i2cget` commands or the `check_battery_config.sh` tool.

### Power Button Hold Failure
**Problem**: Holding the power button for 4 seconds does not reliably shut down the device. The LED dims, suggesting PMIC reaction, but power is not fully cut, and the system may freeze or display remains black.
**Root Cause**: This appears to be a consequence of the PMIC's unstable state, possibly related to the sensor failure or hardware limitations. While the PEK register (`0x36`) is configured for 4s shutdown, the PMIC may not be responding correctly to the long-press signal. The hardware itself might be faulty.
**Workaround**: Rely on software shutdown (`sudo poweroff`) or a prolonged physical button press (10-15s) as a last resort. The tap function remains disabled due to stuck IRQs.

### Known Limitations
*   **Sleep/Hibernate:** Not supported (missing RTC driver, no swap).
*   **Battery UI:** Battery percentage is not displayed in the taskbar due to driver probe failure (Hardware is working).
*   **USB Devices:** Prone to disconnects (known issue).
*   **Tap Power Button:** Disabled due to stuck hardware interrupt.
### Power Button Update
- Changed Hard Shutdown hold time from 4s to 6s (Register 0x36 = 0x59) to improve reliability against PMIC noise.
