#!/bin/bash

error() {
	echo -e "\033[31m$1 \033[0m"
}

warn() {
	echo -e "\033[33m$1 \033[0m"
}

info() {
	echo -e "\033[34m$1 \033[0m"
}

print_usage() {
	echo "Usage:"
	echo -e "\t$0 [options]"
	echo "options:"
	echo -e "-a|--arch argument \n\tConstruction of ubuntu rootfs, default: arm64"
	echo -e "\tSupport:"
	echo -e "\t\tamd64, arm64, riscv64, s390x, ppc64el, armhf"
	echo -e "-v|--ubuntu-version argument \n\tDownload the specified Ubuntu version, default: focal(20.04)"
	echo -e "\tYou can also select one of follow version:"
	echo -e "\t\tbionic(18.04)"
	echo -e "\t\tfocal(20.04)"
	echo -e "\t\tjammy(22.04)"
	echo -e "\t\tlunar(23.04)"
	echo -e "\t\tmantic(23.10)"
	echo -e "-o|--output argument \n\tSpecia output dir, format: out-arch-version"
	echo -e "-t|--filetype argument \n\tFilesystem type for initrd image, default: ext4"
	echo -e "\tAll types support are: ext4..."
	echo -e "-s|--size argument \n\tImage size, default: 1G"
	echo -e "\t\tSupport units m/M or g/G, like 2m/2M, 2g/2G"
	echo -e "-u|--update-only \n\tJust run install.sh and update initrd image without download ubuntu base"
	echo -e "-r|--run-qemu \n\tJust run qemu, command like:"
	echo -e "\t\tbuild.sh -r -a [arch:default arm64] -k /xxx/kernel_image -i /xxx/initrd_image"
	echo -e "-k|--kernel-image \n\tSpecial kernel image"
	echo -e "-i|--initrd-image \n\tSpecial initrd image"
	echo -e "-h|--help \n\tHelp information"
	echo ""
}

download_ubuntu_base() {
	sudo debootstrap --arch="${UBUNTU_ARCH}" "${UBUNTU_VERSION}" "${OUT_UBUNTU_DL}" "${UBUNTU_URL}"
	return $?
}

create_virtual_net(){
	sudo ip tuntap add dev ${TAP_NAME} mode tap user `whoami`
	sudo ip link set ${TAP_NAME} up
	sudo ip addr add 192.168.10.10/24 dev ${TAP_NAME}
}

parase_args() {
	while true; do
		case "$1" in
		-a | --arch)
			UBUNTU_ARCH=$2
			shift 2
			;;
		-v | --ubuntu-version)
			UBUNTU_VERSION=$2
			shift 2
			;;
		-o | --output)
			OUT=$2
			shift 2
			;;
		-t | --filetype)
			FILETYPE=$2
			shift 2
			;;
		-s | --size)
			SIZE=$2
			shift 2
			;;
		-u | --update-only)
			UPDATE_ONLY=1
			shift
			;;
		-r | --run-qemu)
			RUN_QEMU=1
			shift
			;;
		-k | --kernel-image)
			KERNEL_IMAGE=$2
			shift 2
			;;
		-i | --initrd-image)
			INITRD_IMAGE=$2
			shift 2
			;;
		-h | --help)
			shift
			return 1
			;;
		--)
			shift
			break
			;;
		*)
			error "Invalid args"
			return 1
			;;
		esac
	done

	if [ ${UBUNTU_ARCH} = "amd64" ]; then
		# reset PORT and UBUNTU_URL
		PORT=""
	fi

	if [ ${FILETYPE} != "ext4" ]; then
		error "Just support ext4 filetype now!"
		return 1
	fi

	return 0
}

short_opts="a:v:o:s:t:k:i:urh"
long_opts="arch:,ubuntu-version:,output:,size:,filetyle:,kernel-image:,initrd_image:,update-only,run-qemu,help"
all_args=$(getopt -o $short_opts -l $long_opts -n "$(basename $0)" -- "$@")

if [ $? -ne 0 ]; then
	error "Failed to parased args"
	print_usage
	exit 1
fi

eval set -- "$all_args"

#####################################
# default configure, These var canbe reset by args
#
UBUNTU_VERSION=focal
UBUNTU_ARCH=arm64
PORT=-ports
FILETYPE=ext4
SIZE=1G
UPDATE_ONLY=0
RUN_QEMU=0
INITRD_IMAGE=""
KERNEL_IMAGE=""
TAP_NAME="tap-qemu"
#####################################

# Parse arguments
if [ $# -gt 0 ]; then
	parase_args $@
fi

# error or -h|--help
if [ $? -eq 1 ]; then
	print_usage
	exit 1
fi

#####################################
# Stage 0 -- Run qemu only
#####################################
if [ ${RUN_QEMU} -eq 1 ]; then
	if [ -z "${KERNEL_IMAGE}" -o -z "${INITRD_IMAGE}" ]; then
		error "please give special kernel and initrd image"
		print_usage
		exit 1
	fi

	if [ ! -e "${KERNEL_IMAGE}" ]; then
		error "Kernel image "${KERNEL_IMAGE}" not exits"
		exit 1
	fi

	if [ ! -e "${INITRD_IMAGE}" ]; then
		error "Initrd image "${INITRD_IMAGE}" not exits"
		exit 1
	fi

	sh run.sh ${UBUNTU_ARCH} ${KERNEL_IMAGE} ${INITRD_IMAGE} ${TAP_NAME}

	exit 0
fi

#####################################
# Stage 1 -- Download Ubuntu BASE
#####################################
info "Enter Stage 1"
UBUNTU_URL="https://mirrors.tuna.tsinghua.edu.cn/ubuntu${PORT}/" #arm64 download from /ubuntu-ports/xxx but x86 download from /ubuntu/xxx
OUT=${PWD}/out-${UBUNTU_ARCH}-${UBUNTU_VERSION}
OUT_UBUNTU_DL=${OUT}/ubuntu_base

info "TARGET = "${UBUNTU_ARCH}""
info "UBUNTU_VERSION = "${UBUNTU_VERSION}""
info "UBUNTU_URL = "${UBUNTU_URL}""

if [ ${UPDATE_ONLY} -eq 0 ]; then
	download_ubuntu_base
	create_virtual_net
fi

# TODO: check download_ubuntu_base return

info "Out of Stage 1"

#####################################
# Stage 2 -- Install tools
#####################################
info "Enter Stage 2"

# get Administrator privilege
sudo cp install.sh ${OUT_UBUNTU_DL}

sudo chroot "${OUT_UBUNTU_DL}" \
	/bin/bash -c "chmod +x install.sh \
	&& ./install.sh ${UBUNTU_URL} ${UBUNTU_VERSION} && exit"

sudo rm ${OUT_UBUNTU_DL}/install.sh -f
# release Administrator privilege

info "Out of Stage 2"

#####################################
# Stage 3 -- Generate initrd image
#####################################
MKFS_TOOL="mkfs.${FILETYPE}"
INITRD_IMAGE_NAME=initrd.img
MOUNT_DIR=${PWD}/initrd_mnt

info "Enter Stage 3"

sudo -s <<EOF
if [ ! command -v ${MKFS_TOOL} >/dev/null 2>&1 ]; then
	warn "Could't found ${MKFS_TOOL} tool, try to install..."
	apt-get install e2fsprogs -y
fi

dd if=/dev/zero of=${OUT}/${INITRD_IMAGE_NAME} bs=${SIZE} count=1
${MKFS_TOOL} ${OUT}/${INITRD_IMAGE_NAME}

if [ ! -d ${MOUNT_DIR} ]; then
	mkdir -p ${MOUNT_DIR}
fi

mount -o loop ${OUT}/${INITRD_IMAGE_NAME} ${MOUNT_DIR}
if [ $? -ne 0 ]; then
	error "Mount failed"
	exit 1
fi
cp -ar ${OUT_UBUNTU_DL}/* ${MOUNT_DIR}
ls -al ${MOUNT_DIR}
umount ${MOUNT_DIR}
rm ${MOUNT_DIR} -rf
EOF
info "Out of Stage 3"
