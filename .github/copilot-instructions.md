# copilot-instructions.md

Purpose
- Capture reproducible build / flash / debug steps for Raspberry Pi Compute Module (CM5) with uConsole on openSUSE MicroOS (transactional).
- Provide a single-source checklist, commands, and locations used by automation scripts in this repository.

Hardware
- Target: Raspberry Pi Compute Module 5 (raspi cm5)
- Console: uConsole (serial/console tooling and any custom uconsole-daemon)
  - must support uconsole hardware (keyboard, trackball, display, backlight, battery management)
- Storage: eMMC on CM5 (exposed via rpiboot/usbboot -> /dev/sda on host when connected)
- Host: Linux workstation for build and flashing (tools below)

Operating System (target)
- openSUSE MicroOS (transactional updates, immutable root)
- Use transactional-update for package changes; images built with KIWI / image tools preferred

Interactions (quick references)
- Existing flashed system SSH: ssh -i <ssh_key> <user>@<device_ip>
- Direct eMMC (when CM5 in USB boot mode): /dev/sda (verify with lsblk)
- Serial console (uConsole or UART): e.g. /dev/ttyUSB0, 115200 8N1

Prerequisites (host)
- git, gcc, make, python3 (for build scripts)
- rpiboot (usbboot) to expose eMMC: https://github.com/raspberrypi/usbboot
- dd, parted, mkfs.ext4, mount, rsync
- kiwi / kiwi-ng or image-builder preferred for MicroOS images
- ssh keys configured
- screen or picocom for serial console

Tooling install examples
- rpiboot:
  - git clone https://github.com/raspberrypi/usbboot.git
  - cd usbboot
  - sudo ./rpiboot
- kiwi / image creation: follow openSUSE KIWI docs (install kiwi-ng packages)

Repository layout (recommended)
- scripts/
  - build-image.sh        # builds MicroOS image (kiwi)
  - flash-eMMC.sh         # run rpiboot, dd image to /dev/sda, sync
  - flash-sdcard.sh       # optional, for SD images
  - debug-serial.sh       # helper to open serial console
- overlay/                # uconsole overlays, systemd units, ssh keys
- docs/
  - troubleshooting.md
  - uconsole-setup.md
- .github/                # CI / copilot instructions (this file)
- README.md

Build & flash workflow (canonical)
1. Build image (host):
   - ./scripts/build-image.sh --output out/image.img
   - Validate image (mount loopback or use qemu)
2. Put CM5 into USB boot mode and expose eMMC:
   - Connect CM5 to host via USB (check vendor docs)
   - sudo ./usbboot/rpiboot            # or rpiboot -d if required
   - Wait for /dev/sda to appear
3. Flash image to eMMC:
   - Verify device: lsblk
   - sudo dd if=out/image.img of=/dev/sda bs=4M status=progress conv=fsync
   - sudo sync
   - sudo partprobe /dev/sda
4. Configure first boot (BEFORE powering on):
   - Run: sudo ./scripts/setup-first-boot.sh --device /dev/sda
   - This prompts for username, password (optional), SSH key, WiFi (optional)
   - Copies all uConsole configuration files to boot partition
5. First boot:
   - Insert CM5 into target board and power on
   - Use serial console (uConsole) and/or SSH
   - Default network: configure via DHCP or static via overlay

Transactional updates (openSUSE MicroOS)
- To install packages into the system image (writable snapshot):
  - sudo transactional-update pkg install <package>
  - sudo transactional-update shell   # for interactive package changes
  - Reboot to apply: sudo reboot
- Do not edit read-only root directly; use transactional-update or overlays in image build.

SSH access & first-boot setup
- Use scripts/setup-first-boot.sh to configure user/SSH/WiFi before first boot
- The script places authorized_keys, creates user with wheel group, configures WiFi
- Example: sudo ./scripts/setup-first-boot.sh --device /dev/sda --username myuser --ssh-key-file ~/.ssh/id_rsa.pub
- Ensure sshd is enabled in the image (systemd service enabled by kiwi or overlay)
- Example SSH command to existing device:
  - ssh -i <ssh_key> <user>@<device_ip>

Serial console & uConsole
- Use uConsole program or basic serial client:
  - screen /dev/ttyUSB0 115200
  - picocom -b 115200 /dev/ttyUSB0
- Collect boot logs:
  - journalctl -b -o short-iso
  - dmesg --ctime
  - Save logs to host for analysis: journalctl -b > /tmp/boot.log

Debugging checklist
- If device does not boot:
  - Check power and board connections
  - Use serial console to capture U-Boot/kernel messages
  - Confirm eMMC partitions with lsblk on host after rpiboot
  - Mount partitions on host and check /etc/fstab, network config, SSH keys
- If network unreachable:
  - Verify dhclient / NetworkManager logs on target
  - Confirm IP with serial console
- If transactional-update fails:
  - Use transactional-update shell to probe
  - Check /var/log/transactional-update.log (if present) and journalctl

Safety notes
- Always verify the target device node (e.g. /dev/sda) before running dd.
- Back up important data before flashing eMMC.

Troubleshooting snippets (examples)
- List block devices:
  - lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,LABEL
- Mount root partition (host):
  - sudo mount /dev/sda2 /mnt
  - sudo ls /mnt
- Enable sshd on mounted image:
  - sudo chroot /mnt systemctl enable sshd.service
  - (If chroot not possible, provide configured unit in overlay)

TODO / repository-specific tasks
- Add image build configuration (KIWI description) into repo.
- Add uconsole systemd unit and configuration into overlay/.
- Add automated CI job to produce images and run basic checks.
- Document exact rpiboot flags / hardware wiring for CM5 (link board-specific notes).

Contact / Notes
- Use this file as the authoritative how-to for anyone building/flashing/debugging CM5 with MicroOS + uConsole.
- Update with device-specific wiring, rpiboot flags, and any board firmware steps when available.


Resources to research
- uConsole: https://github.com/clockworkpi/uConsole
- openSUSE MicroOS Raspberry Pi raw image (aarch64): https://download.opensuse.org/ports/aarch64/tumbleweed/appliances/openSUSE-MicroOS.aarch64-16.0.0-RaspberryPi-Snapshot20251127.raw.xz