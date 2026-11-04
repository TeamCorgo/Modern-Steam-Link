#!/bin/sh
#
# Grow the root partition and filesystem to use the whole USB stick.
# Runs the same two commands as the README:
#
#   parted /dev/sda resizepart 1 100%
#   resize2fs /dev/sda1
#
# with checks around them. Growing the filesystem can take a long time on a
# large or slow stick. Safe to run while the system is running from the
# stick (parted asks you to confirm, because the partition is in use: answer
# Yes), and safe to run again: it does nothing if the stick is already full.

set -e

if [ "$(id -u)" != 0 ]; then
    exec sudo "$0" "$@"
fi

ROOT_PART=$(findmnt -no SOURCE /)                 # e.g. /dev/sda1
PART_NAME=$(basename "$ROOT_PART")                # sda1
DISK_NAME=$(lsblk -no PKNAME "$ROOT_PART")        # sda
DISK=/dev/$DISK_NAME
PART_NUM=$(cat "/sys/class/block/$PART_NAME/partition")

# Only ever touch the USB stick the system booted from
case "$DISK_NAME" in
    sd[a-z]) ;;
    *) echo "Root filesystem is on $ROOT_PART, not a USB disk; not touching it." >&2; exit 1 ;;
esac

# Sizes in 512-byte sectors
DISK_SECTORS=$(cat "/sys/class/block/$DISK_NAME/size")
PART_START=$(cat "/sys/class/block/$PART_NAME/start")
PART_SECTORS=$(cat "/sys/class/block/$PART_NAME/size")
FREE_MB=$(( (DISK_SECTORS - PART_START - PART_SECTORS) / 2048 ))

echo "USB stick:  $DISK, $((DISK_SECTORS / 2048)) MB"
echo "Root:       $ROOT_PART, $((PART_SECTORS / 2048)) MB"
echo "Unused:     $FREE_MB MB"

if [ "$FREE_MB" -lt 16 ]; then
    echo "The root partition already uses the whole stick."
    exit 0
fi

# Keep a copy of the current partition table, in case it's ever needed
BACKUP=/root/partition-table-$DISK_NAME-$(date +%Y%m%d-%H%M%S).txt
parted -s "$DISK" unit s print > "$BACKUP"
echo "Saved the current partition table to $BACKUP"
echo

echo "This can take a long time to complete: from a few minutes to over an hour,"
echo "depending on the size and speed of the stick. Growing the filesystem is the"
echo "slow part, and it may look stuck with no output while it works."
echo "Keep the Steam Link powered, the stick plugged in, and this SSH session open"
echo "until it finishes. If it's interrupted, run it again to finish growing."
echo

START=$(date +%s)

echo "Step 1/2: growing the partition"
parted "$DISK" resizepart "$PART_NUM" 100%

echo
echo "Step 2/2: growing the filesystem (the long part, please wait)"
resize2fs "$ROOT_PART"

ELAPSED=$(( $(date +%s) - START ))
echo
echo "Done in $((ELAPSED / 60)) min $((ELAPSED % 60)) s."
df -h /
