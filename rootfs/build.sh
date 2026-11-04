#!/usr/bin/env bash

set -euo pipefail

IMAGE=${IMAGE:-steamlink-debian.img}
ROOTFS_TAR=${ROOTFS_TAR:-rootfs.tar}
IMAGE_HOSTNAME=${IMAGE_HOSTNAME:-steamlink}
MOUNT_DIR=${MOUNT_DIR:-/mnt/disk}

# Size the image to the rootfs plus 1 GiB: room for the optional 512 MiB swap file
# (create_swap.sh in the home directory) and ~512 MiB of free space. Users can grow the
# partition to the full stick later.
ROOTFS_MB=$(( $(stat -c %s "$ROOTFS_TAR") / 1024 / 1024 ))
IMAGE_MB=$(( ROOTFS_MB + 1024 ))
# A "2 GB" stick holds about 1907 MiB; refuse to build an image that won't fit
MAX_IMAGE_MB=1900
if (( IMAGE_MB > MAX_IMAGE_MB )); then
    echo "Image would be ${IMAGE_MB} MiB, more than a 2 GB stick holds (${MAX_IMAGE_MB} MiB)" >&2
    exit 1
fi

rm -f "$IMAGE" "$IMAGE.xz"
dd if=/dev/zero of="$IMAGE" bs=1M count="$IMAGE_MB"

# One msdos partition spanning the image
parted --script "$IMAGE" mklabel msdos
parted --script "$IMAGE" mkpart primary ext3 1MiB 100%

LOOP_DEV=$(losetup --show -P -f "$IMAGE")

cleanup() {
    if mountpoint -q "$MOUNT_DIR"; then umount "$MOUNT_DIR"; fi
    losetup -d "$LOOP_DEV" 2>/dev/null || true
}
trap cleanup EXIT

# The label is what /etc/fstab mounts as /
mkfs.ext3 -L steamlink-root "${LOOP_DEV}p1"

mkdir -p "$MOUNT_DIR"
mount "${LOOP_DEV}p1" "$MOUNT_DIR"
tar -xpf "$ROOTFS_TAR" -C "$MOUNT_DIR"
rm -f "$MOUNT_DIR/.dockerenv"

# Docker manages these during the build, so they're written here instead
echo "$IMAGE_HOSTNAME" > "$MOUNT_DIR/etc/hostname"
cat > "$MOUNT_DIR/etc/hosts" <<EOF
127.0.0.1	localhost
127.0.1.1	$IMAGE_HOSTNAME

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF
rm -f "$MOUNT_DIR/etc/resolv.conf"
: > "$MOUNT_DIR/etc/resolv.conf"

sync
umount "$MOUNT_DIR"
losetup -d "$LOOP_DEV"
trap - EXIT

xz -z -T0 "$IMAGE"
chmod 644 "$IMAGE.xz"
