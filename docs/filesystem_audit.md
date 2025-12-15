# Filesystem Audit Report

**Date:** 2025-12-16
**Device:** ClockworkPi uConsole CM5 (Mounted as /dev/sda)

## Overview
The device filesystem was mounted and audited to ensure consistency with the repository and verify applied fixes.

## Verified Files (Identical to Repo)
*   `/usr/local/sbin/axp221-monitor.sh` (Updated with IRQ clear fix)
*   `/usr/local/sbin/axp221-configure-pek.sh`
*   `/usr/local/sbin/axp221-poweroff.sh`
*   `/boot/efi/overlays/clockworkpi-uconsole-cm5.dtbo`

## Differences
*   `/boot/efi/extraconfig.txt`: Contains `dtoverlay=clockworkpi-uconsole-cm5`. This is the expected result of the deployment script.

## Corrections Applied
*   **Infinite Boot Loop Fix:** The `axp221-monitor.sh` script on the device was overwritten with the repository version which includes the instruction to clear the IRQ status register (0x44) on startup. This prevents the "Power On" button press from being misinterpreted as a "Shutdown" command.

## Partition Layout
*   `/dev/sda1`: EFI (FAT32)
*   `/dev/sda2`: BTRFS Root (Subvolumes: @, @/usr/local, @/.snapshots)
