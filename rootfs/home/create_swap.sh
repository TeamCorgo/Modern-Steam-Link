#!/bin/sh
#
# Create a swap file on the USB stick.
#
#   ./create_swap.sh     asks for the size (512 MB if you just press Enter)
#
# It gets priority 10, below zram's 100, so if zram is ever turned on, the stick
# is only written once zram is full. It's
# added to /etc/fstab, so it's turned on at every boot. Running it again when
# /swapfile already exists only makes sure it's on.

set -e

if [ "$(id -u)" != 0 ]; then
    exec sudo "$0"
fi

SWAP=/swapfile
DEFAULT_MB=512
MARGIN_MB=256   # free space to leave on the stick after creating the file
PRIORITY=10     # below zram's 100
FSTAB_LINE="$SWAP none swap sw,pri=$PRIORITY 0 0"

if [ -f "$SWAP" ]; then
    echo "$SWAP already exists ($(( $(stat -c %s "$SWAP") / 1048576 )) MB)."
else
    avail=$(df -Pm / | awk 'NR == 2 { print $4 }')
    echo "The stick has ${avail} MB free."
    printf "Swap file size in MB [%s]: " "$DEFAULT_MB"
    read -r SIZE_MB
    SIZE_MB=${SIZE_MB:-$DEFAULT_MB}
    case "$SIZE_MB" in
        ''|*[!0-9]*|0) echo "The size must be a number of MB, like 512." >&2; exit 1 ;;
    esac

    if [ "$avail" -lt $((SIZE_MB + MARGIN_MB)) ]; then
        echo "Not enough space: ${avail} MB free, need $((SIZE_MB + MARGIN_MB)) MB" >&2
        echo "(${SIZE_MB} MB swap + ${MARGIN_MB} MB to spare). Run ./expand_usb.sh to use" >&2
        echo "the whole stick, or pick a smaller size." >&2
        exit 1
    fi

    printf "Create a %s MB swap file at %s? [y/N] " "$SIZE_MB" "$SWAP"
    read -r answer
    case "$answer" in
        y|Y|yes|YES) ;;
        *) echo "Nothing changed."; exit 0 ;;
    esac

    echo "Creating a ${SIZE_MB} MB swap file at $SWAP."
    echo "Writing it takes a while on a USB stick (about a minute for 512 MB);"
    echo "keep the Steam Link powered until it finishes."
    # Write to a temporary name so an interruption can't leave a half-made swap file
    rm -f "$SWAP.tmp"
    dd if=/dev/zero of="$SWAP.tmp" bs=1M count="$SIZE_MB" status=progress
    chmod 600 "$SWAP.tmp"
    mkswap "$SWAP.tmp" >/dev/null
    sync
    mv "$SWAP.tmp" "$SWAP"
fi

if ! grep -q "^$SWAP[[:space:]]" /etc/fstab; then
    echo "$FSTAB_LINE" >> /etc/fstab
    echo "Added $SWAP to /etc/fstab, so it's turned on at every boot."
fi

if ! grep -q "^$SWAP " /proc/swaps; then
    swapon -p "$PRIORITY" "$SWAP"
fi

echo
swapon --show
