#!/bin/sh
set -eu

if ! [ $(id -u) = 0 ]; then
    echo "This script must be run as root (for mkswap/mount)"
    exit 1
fi

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <total image size in MiB> <swap size in MiB> <rootfs tar file>"
    exit 1
fi

BLOCKS_PER_MB=2048

IMAGE_SIZE="$(($1 * $BLOCKS_PER_MB))"
PARTITION_TABLE_SIZE=64
DRIVER_SIZE=32
BOOT_PART_SIZE="$((16 * $BLOCKS_PER_MB))"
SWAP_SIZE="$(($2 * $BLOCKS_PER_MB))"
ROOT_SIZE="$(($IMAGE_SIZE - $SWAP_SIZE - $BOOT_PART_SIZE - $DRIVER_SIZE - $PARTITION_TABLE_SIZE))"

DRIVER_OFFSET=$PARTITION_TABLE_SIZE
BOOT_PART_OFFSET="$(($DRIVER_OFFSET + $DRIVER_SIZE))"
SWAP_OFFSET="$(($BOOT_PART_OFFSET + $BOOT_PART_SIZE))"
ROOT_OFFSET="$(($SWAP_OFFSET + $SWAP_SIZE))"

DRIVER_FILE="lido-driver.img"
BOOT_PART_FILE="hfs-partitions/system-7.5-penguin-19.dsk.gz"
ROOTFS_FILE="$3"

HFDISK_SCRIPT="i

C

${DRIVER_SIZE}
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

IMAGE_FILE=$(mktemp XXXXX.img)
echo "* Creating $IMAGE_FILE..."
dd if=/dev/zero of="$IMAGE_FILE" bs=512 count="$IMAGE_SIZE"

# partition with swap and root partitions
echo "* Partitioning..."
# this is noisy, so /dev/null it is
echo "$HFDISK_SCRIPT" | ./hfdisk "$IMAGE_FILE" > /dev/null

# create the individual partitions and format
echo "* Creating swap file..."
SWAP_FILE=$(mktemp swap.XXXXX)
dd if=/dev/zero of="$SWAP_FILE" bs=512 count="$SWAP_SIZE"
mkswap "$SWAP_FILE"

echo "* Creating root filesystem..."
ROOT_FILE=$(mktemp root.XXXXX)
dd if=/dev/zero of="$ROOT_FILE" bs=512 count="$ROOT_SIZE"
mkfs.ext2 "$ROOT_FILE"

# mount the root partition and extract the root filesystem
echo "* Extracting root filesystem..."
TEMP_MOUNT=$(mktemp -d mnt.XXXXX)
mount -t ext2 "$ROOT_FILE" "$TEMP_MOUNT"
(cd "$TEMP_MOUNT" && tar xf "../$ROOTFS_FILE")

# make sure all changes are written to file underlying loopback device
# before adding it to the main image
sync

# copy the HDD driver and 3 partitions into the main disk image
echo "* Combining partition table and partitions into $IMAGE_FILE..."
dd if="$DRIVER_FILE" of="$IMAGE_FILE" seek="$DRIVER_OFFSET" bs=512 conv=notrunc
gunzip -c "$BOOT_PART_FILE" | dd of="$IMAGE_FILE" seek="$BOOT_PART_OFFSET" bs=512 conv=notrunc
dd if="$SWAP_FILE" of="$IMAGE_FILE" seek="$SWAP_OFFSET" bs=512 conv=notrunc
dd if="$ROOT_FILE" of="$IMAGE_FILE" seek="$ROOT_OFFSET" bs=512 conv=notrunc

echo "* Cleaning up..."
rm $SWAP_FILE
umount "$ROOT_FILE"
rmdir "$TEMP_MOUNT"
rm "$ROOT_FILE"

echo "Done."
