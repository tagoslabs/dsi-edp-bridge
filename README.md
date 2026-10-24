# TagosLabs SN65DSI86 DSI→eDP bridge — installer for NanoPi M6

Enables the TagosLabs SN65DSI86 bridge board on a **FriendlyElec NanoPi M6** so that the
**BOE NE160WUM-N62** 16" eDP panel (1920×1200) shows your GNOME desktop.

## Quick start
1. Download **tagos-bridge-installer.run** in your web browser (it goes to your Downloads folder).
2. Press **Ctrl+Alt+T** to open a Terminal.
3. Type `sudo bash ~/Downloads/tagos-bridge-installer.run`, press Enter, type your password, wait for **DONE!**, then type `y` to restart.

No internet connection is needed. To undo: `sudo bash ~/Downloads/tagos-bridge-installer.run --uninstall`

---
# Advanced

## Supported system (checked by the installer, it refuses anything else)
| Item | Required |
|---|---|
| Board | FriendlyElec NanoPi M6 (RK3588S), `/proc/device-tree/model` = `FriendlyElec NanoPi M6` |
| OS | stock FriendlyElec Debian (GNOME), booting from microSD |
| Kernel | exactly `6.1.141` (#47), `uname -r` = `6.1.141` (module vermagic `6.1.141 SMP mod_unload modversions aarch64`) |
| Boot media | microSD with GPT partition `resource` (16 MiB, normally `/dev/mmcblk0p4`) |

## What it does
1. Checks board, SoC, kernel, root, and the sha256 of every file it will install.
2. Backs up the current `resource` partition (it holds the device tree) to
   `/var/backups/tagos-bridge/<timestamp>/resource-backup.img` and verifies the copy.
3. Installs 4 kernel modules that the stock kernel lacks into `/lib/modules/6.1.141/extra/`:
   `tagos_auxbus`, `drm_dp_aux_bus`, `panel-edp`, `ti-sn65dsi86`, then runs `depmod`
   and writes `/etc/modules-load.d/tagos-sn65dsi86.conf`.
4. Writes the verified resource image (stock DTBs + modified `rk3588-nanopi6-rev0a.dtb`
   with the bridge on DSI0 and U-Boot `route-dsi0` disabled) to the `resource` partition with
   `dd … conv=fsync`, reads it back and checks the sha256. On mismatch it restores the backup.
5. Prints a summary and asks whether to reboot (`y/N`).

## Install (details)
Before you start, connect the screen and adapter (see *Cable orientation*) and boot with HDMI attached.
`tagos-bridge-installer.run` is one self-contained file: a bash script with the payload (modules +
resource image) appended. It unpacks to a temporary folder, checks the sha256 of the payload, and then runs
the install. It needs only bash, coreutils, tar and gzip, and no network.

```
sudo bash tagos-bridge-installer.run              # install
sudo bash tagos-bridge-installer.run --dry-run    # show what would be done, change nothing
sudo bash tagos-bridge-installer.run --yes        # no questions, restarts automatically
sudo bash tagos-bridge-installer.run --uninstall  # undo
```
If the file is damaged, it stops with "checksum mismatch" and changes nothing.

## Revert
```
sudo bash tagos-bridge-installer.run --uninstall   # restores the FIRST (original) backup, removes the modules, asks to reboot
```
If the board no longer boots: put the microSD into a Linux PC, find the partition labelled
`resource` (`lsblk -o NAME,SIZE,PARTLABEL`), then
`sudo dd if=resource-backup.img of=/dev/sdX4 bs=1M conv=fsync` (copy `resource-backup.img` off the
board beforehand, or reflash the stock FriendlyElec image). The root filesystem is not touched.

## Do not upgrade the kernel
The modules are built for 6.1.141 #47 only. After a kernel update they will not load (black panel).
Optional: `sudo apt-mark hold linux-image-6.1.141 linux-headers-6.1.141` (package names may vary).

## Cable orientation
Insert the panel FPC tail into J2 on the bridge **with the blue stiffener DOWN (toward the board) and the
contacts UP (toward the flip lock)** — i.e. flipped compared to the original scaler board.
Correctly inserted, LED1 lights up once the panel power is enabled. The DSI cable goes to the
**DSI0** connector of the NanoPi M6. The DSI1 (YX35) LCD output is disabled by this DT.

## Troubleshooting
- **Panel stays black**
  - `uname -r` must be `6.1.141`; `lsmod | grep -E 'sn65|panel_edp|aux'` must show all 4 modules.
  - `dmesg | grep -iE 'sn65|edp|dsi|aux'` — "disagrees about version of symbol" = wrong kernel.
  - `ls /sys/class/drm/` should list `card*-eDP-1`; `cat /sys/class/drm/card*-eDP-1/status`.
  - In GNOME Settings → Displays the panel may be configured as a second screen or disabled.
  - Check cable orientation and that LED1 lights; reseat both FPCs with the board powered off.
- **Board does not boot / stuck before kernel** — connect UART debug (1500000 baud, 8N1, 3.3 V) to the
  NanoPi M6 debug header and look for `Invalid DTB hash` or `Synchronous Abort` in U-Boot output.
  Restore the backup as described in *Revert*.
- **Installer refuses** — the message tells why (wrong board, kernel, missing `resource` partition,
  checksum). Nothing is changed in that case.
