# Modern

A modern way to repurpose a Valve Steam Link: Debian 13 (Trixie) with Linux 7.3.1, booted from a USB drive, ready to use as a Docker host. With the rising cost of Raspberry Pi solutions, the Steam Link presents an opportunity to be repurposed as an inexpensive, very low-power server. Alternative projects are available, but the primary goal of this project is to provide the most vanilla Debian experience possible, closely replicating a standard Debian installation while maintaining up-to-date packages and software versions for security purposes.

## How to use

The image is a standard Debian 13 (trixie) install, with the same package set as a netinstall with "standard system utilities" and "SSH server" selected.

### 1. Download the image

Download the latest `steamlink-debian-trixie-7.3.1.img.xz` from the [Releases](https://github.com/TeamCorgo/Modern/releases/latest) page.

### 2. Write it to a USB drive

A USB drive of at least 2GB is required: the image is about 1.7GB, including room for an optional swap file.

> :warning: **Warning**: Writing the image wipes everything on the target device. Writing it to the wrong device will wipe that disk instead.

**Linux:** find the USB drive's device name. It's the entry that appears when you plug the drive in, e.g. `/dev/sdb`:

```bash
lsblk -o NAME,SIZE,MODEL,TRAN,MOUNTPOINTS
```

Unmount it if your desktop mounted it, then write the image to the whole device (`/dev/sdX`, not `/dev/sdX1`):

```bash
sudo umount /dev/sdX?*
xzcat steamlink-debian-trixie-7.3.1.img.xz | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress
sync
```

**Windows / macOS / Linux desktop:** [balenaEtcher](https://etcher.balena.io/) can write the `.img.xz` directly. On Linux, GNOME Disks ("Restore Disk Image") works too.

### 3. Boot the Steam Link

Plug the USB drive and a network cable into the Steam Link and power it on. The stock firmware starts first and then hands over to the Debian kernel. HDMI output stops at that point, which is expected. After a minute or two the device appears on your network as `steamlink`; find its IP address in your router's DHCP table and log in:

```bash
ssh corgo@<ip-address>
```

## Default passwords

> :warning: **Recommended**: Consider changing your passwords with `passwd` after first login.

### Default user

User: `corgo`
password: `steamlink123`

### Root

User: `root`
password: `steamlink123`

Use `su -` or `sudo` once logged in as `corgo`. Root can't log in over SSH with a password (Debian's default). Change both passwords:

```bash
passwd
sudo passwd root
```

## Expand to the full USB drive

The image is kept small so it fits any USB drive of 2GB or more, whatever its size. After the initial boot, it is recommended that you expand the filesystem to utilize the entire drive using the script located in your home directory.

```bash
./expand_usb.sh
```

> :warning: Expanding is **very slow**: from a few minutes to over an hour depending on the size and speed of the drive, and it may look stuck with no output. Keep the Steam Link powered and the SSH session open until it reports `Done`. Running it again does nothing once the drive is fully used.

## Docker

Docker isn't installed, but the kernel supports it. For installation instructions, refer to the [official Docker Engine installation guide for Debian](https://docs.docker.com/engine/install/debian/).

- **ARM-based processor:** 32-bit ARM architecture, linux/arm/v7.
- **Memory:** `dockerd` and `containerd` use about 100MB of the ~500MB RAM.
- **Networking:** 100 Mbit/s (Fast Ethernet), not gigabit.

## Building

See [kernel/README.md](kernel/README.md) for how kernel configs are made and checked, and how to add a kernel version.

`rootfs/Dockerfile` accepts these build arguments:

| Argument | Default |
| --- | --- |
| `DEBIAN_RELEASE` | `trixie` |
| `KERNEL_VERSION` | `7.3.1` |
| `DEFAULT_USER` | `corgo` |
| `DEFAULT_PASSWORD` | `steamlink123` |

`rootfs/build.sh` turns the exported container (`rootfs.tar`) into a flashable image. `IMAGE_HOSTNAME` sets the hostname (default `steamlink`).

## Memory and USB drive wear

- There's no swap by default.
- **zram** (compressed swap in RAM) is off. Its zstd compression costs CPU time on the single slow core. The kernel and `systemd-zram-generator` still support it; `/etc/systemd/zram-generator.conf` shows how to turn it on.
- **A swap file on the USB drive**: run `./create_swap.sh` in your home directory. It shows the free space, asks for a size (press Enter for 512MB), and asks you to confirm. It's added to `/etc/fstab`, so it's on at every boot. Writing the file takes about a minute for 512MB. To remove it: `sudo swapoff /swapfile`, delete the `/swapfile` line from `/etc/fstab`, then `sudo rm /swapfile`.
- The root filesystem is mounted with `noatime`, and the journal is capped at 32 MB (`/etc/systemd/journald.conf.d/steamlink.conf`), to cut down on writes to the USB drive.

## Prebuilt boot binaries

The handover from Valve's kernel uses two prebuilt files that this repository doesn't build:

| File | What it is | SHA-256 |
| --- | --- | --- |
| `rootfs/boot/kexec_load.ko` | Kernel module that adds `kexec` to Valve's 3.8 kernel (`vermagic=3.8.13-mrvl`, GPL). Build paths inside it point to a `ford_kexec/` directory in a `steamlink-sdk` checkout. | `b1b8a7964a06d7ebcd45170b6565f6d9e348c5fc885eba3ae7fc818f404b1956` |
| `rootfs/usr/bin/kexec` | `kexec` from kexec-tools 2.0.15, armhf, linked against libc and zlib | `630c26edd2932102068785df074dbe4ef32ae63ea4c50dc787d27e3ae9309e05` |

Both are byte-for-byte identical to the copies in [djmuted/steamlink-debian](https://github.com/djmuted/steamlink-debian) and [regmibijay/steamlink-archlinux](https://github.com/regmibijay/steamlink-archlinux). The [heap.ovh article](https://heap.ovh/getting-linux-on-valve-steam-link.html) describes the technique. The module's source isn't published in any of these repositories. Rebuilding it would need Valve's [steamlink-sdk](https://github.com/ValveSoftware/steamlink-sdk), which has the 3.8 kernel source and toolchain; nothing else in this repository uses the SDK. They only run on the stock firmware, during the handover.

## Limitations

- **No video or audio output.** HDMI goes dark when Debian takes over, because mainline Linux has no driver for the Steam Link's display and audio hardware.
- **No reboot or shutdown.** Reboot, halt and suspend don't work, so restart the Steam Link by unplugging and replugging its power.
- **No real-time clock.** The time is wrong at boot until it's synced over the network.
- **No DMA controller driver.** Data that hardware could move on its own is copied by the single CPU core instead.
- **No access to the internal NAND flash.** This is deliberate: the kernel is built without NAND support, so Valve's firmware is never touched.

## Acknowledgments

This project was originally inspired by and developed with reference to code from [djmuted](https://github.com/djmuted/steamlink-debian).The original project was distributed under the GNU General Public License v2.0 (GPL-2.0). The implementation in this project has since been independently rewritten.