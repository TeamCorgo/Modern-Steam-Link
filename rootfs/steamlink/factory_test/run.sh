#!/bin/sh
#
# Run by the stock Steam Link firmware from the USB stick (mounted at /mnt/disk).
# Loads the Debian kernel from the stick with kexec and jumps to it. If anything
# fails, this script exits and the stock firmware keeps running.
#
# Paths inside the chroot match rootfs/Dockerfile: /boot/zImage,
# /boot/initramfs-linux-steam.img and /boot/berlin2cd-valve-steamlink.dtb.

LOG=/mnt/disk/var/log/steamlink-handover.log
[ -f "$LOG" ] && mv -f "$LOG" "$LOG.1"
exec >"$LOG" 2>&1

echo "Resetting crashcounter"
fts-set steamlink.crashcounter 0

echo "Mounting devices"
mount -t proc proc /mnt/disk/proc
mount -o rbind /sys /mnt/disk/sys
mount -o rbind /dev /mnt/disk/dev

sync

echo "Booting into new kernel"
insmod /mnt/disk/boot/kexec_load.ko
chroot /mnt/disk/ /usr/bin/kexec -l /boot/zImage --initrd /boot/initramfs-linux-steam.img --dtb /boot/berlin2cd-valve-steamlink.dtb --command-line "root=/dev/sda1 rootwait rw init=/lib/systemd/systemd console=ttyS0,115200n8 usbcore.autosuspend=-1"
chroot /mnt/disk/ /usr/bin/kexec -e