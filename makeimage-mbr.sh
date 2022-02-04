#!/bin/sh
set -eu

if ! [ $(id -u) = 0 ]; then
    echo "This script must be run as root (for losetup)"
    exit 1
fi

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <total image size in MiB> <swap size in MiB> <rootfs tar file>"
    exit 1
fi

set -x

IMAGE_SIZE=$1
SWAP_SIZE=$2
ROOTFS_FILE=$3

# create image and attach to next available loop device
IMAGE_FILE=$(mktemp XXXXX.img)
dd if=/dev/zero of="$IMAGE_FILE" bs=1M count="$IMAGE_SIZE"
LOOP_DEVICE=$(losetup --partscan --show --find "$IMAGE_FILE")

# partition with swap and root partitions
echo "- ${SWAP_SIZE}M 82 -
- + 83 -" | sfdisk "$LOOP_DEVICE"

# format the partitions
mkswap "${LOOP_DEVICE}p1"
mkfs.ext2 "${LOOP_DEVICE}p2"

# mount the root partition and extract the root filesystem
TEMP_MOUNT=$(mktemp -d mnt.XXXXX)
mount -t ext2 "${LOOP_DEVICE}p2" "$TEMP_MOUNT"
(cd "$TEMP_MOUNT" && tar xf "../$ROOTFS_FILE")

# clean up
umount -l "${LOOP_DEVICE}p2"
rmdir "$TEMP_MOUNT"
losetup -d "$LOOP_DEVICE"
