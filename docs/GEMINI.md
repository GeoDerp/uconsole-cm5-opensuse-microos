# uConsole CM5 Hardware Issues & Workarounds

## Persistent Hardware Faults

### AXP221 PMIC Sensor Failure
**Problem**: The device's AXP221 PMIC consistently reports zero battery voltage (`0x00` in registers 0x72/0x73) and fails to initialize its ADC, despite detecting battery presence. This leads to:
*   **Instant Power Off:** The PMIC cuts power immediately when AC is removed, believing the battery is critically low or shorted.
*   **No Battery Boot:** Prevents booting on battery power alone.
**Diagnosis**: This is a critical hardware fault, likely in the PMIC's ADC or battery sensing circuit. Software fixes cannot restore this hardware function.
**Solution**: **Mandatory Hard Reset**. Requires physically removing batteries and AC power, holding the power button for 30s, then reassembling. This *may* unstick the PMIC's internal state. If the issue persists after multiple resets, the PMIC chip may be damaged.

### Power Button Hold Failure
**Problem**: Holding the power button for 4 seconds does not reliably shut down the device. The LED dims, suggesting PMIC reaction, but power is not fully cut, and the system may freeze or display remains black.
**Root Cause**: This appears to be a consequence of the PMIC's unstable state, possibly related to the sensor failure or hardware limitations. While the PEK register (`0x36`) is configured for 4s shutdown, the PMIC may not be responding correctly to the long-press signal. The hardware itself might be faulty.
**Workaround**: Rely on software shutdown (`sudo poweroff`) or a prolonged physical button press (10-15s) as a last resort. The tap function remains disabled due to stuck IRQs.

### Known Limitations
*   **Sleep/Hibernate:** Not supported (missing RTC driver, no swap).
*   **Battery Reporting:** Unreliable/Inaccurate due to PMIC sensor fault. Expect immediate shutdown on battery removal.
*   **USB Devices:** Prone to disconnects (known issue).
*   **Tap Power Button:** Disabled due to stuck hardware interrupt.
### Power Button Update
- Changed Hard Shutdown hold time from 4s to 6s (Register 0x36 = 0x59) to improve reliability against PMIC noise.

### Battery Management Status (Post-Fix)
**Hardware**:
- **ADC Sensor**: Working (Reads ~3.7V via I2C).
- **Charging**: Functional (PMIC autonomous).
- **Power Source**: AC/Battery switching works.

**Software (Linux Driver)**:
- **Status**: **Driver Probe Failure**.
- **Symptoms**: `axp20x_battery` module loads but does not create `/sys/class/power_supply` entries.
- **Impact**: Waybar/Sway cannot display battery percentage.
- **Root Cause**: Likely a Device Tree mismatch where the `axp20x-i2c` MFD driver does not automatically instantiate the battery cell from the DT overlay.
- **Workaround**: None implemented. Battery management is handled by hardware. Monitoring is possible via manual `i2cget` scripts but not integrated into UI.
