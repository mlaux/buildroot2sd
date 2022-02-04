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

BLOCKS_PER_MB=2048
IMAGE_SIZE="$(($1 * $BLOCKS_PER_MB))"
SWAP_SIZE="$(($2 * $BLOCKS_PER_MB))"
ROOTFS_FILE=$3

DRIVER_FILE="lido-driver.img"
BOOT_PART_FILE="hfs-partitions/system-7.5-penguin-19.dsk.gz"
BOOT_PART_SIZE=$((16 * $BLOCKS_PER_MB))

# subtracting 96 for partition map and HDD driver partition
ROOT_SIZE="$(($IMAGE_SIZE - $SWAP_SIZE - $BOOT_PART_SIZE - 96))"

HFDISK_SCRIPT="i

C

32
Macintosh
Apple_Driver
C

${BOOT_PART_SIZE}
Boot
Apple_HFS
C

${SWAP_SIZE}
Swap
Apple_UNIX_SVR2
C


Root
Apple_UNIX_SVR2
w
y
q
"

IMAGE_FILE=$(mktemp image.XXXXX)
dd if=/dev/zero of="$IMAGE_FILE" bs=512 count="$IMAGE_SIZE"

# partition with swap and root partitions
echo "$HFDISK_SCRIPT" | ./hfdisk "$IMAGE_FILE"

# create the individual partitions and format
SWAP_FILE=$(mktemp swap.XXXXX)
dd if=/dev/zero of="$SWAP_FILE" bs=512 count="$SWAP_SIZE"
mkswap "$SWAP_FILE"

ROOT_FILE=$(mktemp root.XXXXX)
dd if=/dev/zero of="$ROOT_FILE" bs=512 count="$ROOT_SIZE"
mkfs.ext2 "$ROOT_FILE"

# mount the root partition and extract the root filesystem
TEMP_MOUNT=$(mktemp -d mnt.XXXXX)
mount -t ext2 "$ROOT_FILE" "$TEMP_MOUNT"
(cd "$TEMP_MOUNT" && tar xf "../$ROOTFS_FILE")

# copy the HDD driver and 3 partitions into the main disk image
dd if="$DRIVER_FILE" of="$IMAGE_FILE" seek=64 bs=512 conv=notrunc
gunzip -c "$BOOT_PART_FILE" | dd of="$IMAGE_FILE" seek=96 bs=512 conv=notrunc

# 2048 blocks = 1 MiB
SWAP_OFFSET="$((96 + $BOOT_PART_SIZE))"
dd if="$SWAP_FILE" of="$IMAGE_FILE" seek="$SWAP_OFFSET" bs=512 conv=notrunc

ROOT_OFFSET="$(($SWAP_OFFSET + $SWAP_SIZE))"
dd if="$ROOT_FILE" of="$IMAGE_FILE" seek="$ROOT_OFFSET" bs=512 conv=notrunc

# clean up
rm $SWAP_FILE
umount -l "${ROOT_FILE}"
rmdir "$TEMP_MOUNT"
rm $ROOT_FILE
