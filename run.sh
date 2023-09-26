#!/bin/bash

# $1 arch, $2 kernel image, $3 initrd image, $4 tap name
#
SMP=2
RAM="3G"
QEMU_BINARY=""

echo "\$0 = "$0""
echo "\$1 = "$1""
echo "\$2 = "$2""
echo "\$3 = $3"
echo "\$4 = $4"

if [ $1 = arm64 ]; then
	QEMU_BINARY="qemu-system-aarch64"
fi

sudo ${QEMU_BINARY} -nographic -M virt -cpu cortex-a53 \
	-smp ${SMP} -m size=${RAM} \
	-kernel $2 \
	-initrd $3 \
	-drive file=$3,format=raw,if=none,id=hd0 \
	-device virtio-blk-device,drive=hd0 -append "console=ttyAMA0 root=/dev/vda rw dns=8.8.8.8" \
	-netdev tap,id=tap0,ifname=$4,script=no,downscript=no -device virtio-net-device,netdev=tap0
