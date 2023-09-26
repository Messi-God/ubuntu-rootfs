#!/bin/bash

# $1 ubuntu source url
# $2 ubuntu version, like focal, jammy

if ! grep -q "$1 $2" /etc/apt/sources.list; then
	mv /etc/apt/sources.list /etc/apt/sources.list.bak

	touch /etc/apt/sources.list
	echo "deb $1 $2 main restricted universe multiverse" >> /etc/apt/sources.list
	# echo "deb $1 $2-updates main restricted universe multiverse" >> /etc/apt/sources.list
	# echo "deb $1 $2-backports main restricted universe multiverse" >> /etc/apt/sources.list
	# echo "deb $1 $2-security main restricted universe multiverse" >> /etc/apt/sources.list
fi


# install tools
apt-get update
apt-get install -y build-essential
apt-get install -y gdb
apt-get install -y gcc

# setting root passwd ant automatically login as root
echo "root:123" | chpasswd
sed -i "s/-o '-p -- \\\\\\\u'/-a root/" /lib/systemd/system/serial-getty@.service

# set language
echo "LANG=C.UTF-8" >/etc/default/locale
echo "LANGUAGE=C.UTF-8" >>/etc/default/locale
echo "LC_ALL=C.UTF-8" >>/etc/default/locale

# set timezone
apt-get install -y tzdata
echo "Asia/Shanghai" > /etc/timezone
dpkg-reconfigure --frontend noninteractive tzdata
# dpkg-reconfigure tzdata

# set host name
hostname=$(lsb_release -r | awk '{print $2}' | tr -d '.')
echo "Ubuntu${hostname}" > /etc/hostname

apt-get install -y openssh-server

# enable ssh server and client
if [ ! -e ~/.ssh/id_ed25519.pub ]; then
	ssh-keygen -t ed25519 -C ""${USER}"@Ubuntu${hostname}" -f ~/.ssh/id_ed25519 -N ''
	echo 'PubkeyAuthentication yes' >>/etc/ssh/sshd_config
	echo 'PasswordAuthentication yes' >>/etc/ssh/sshd_config
	sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
	systemctl enable ssh
fi

apt-get install -y net-tools iputils-ping tcpdump iptables openssh-client openssh-server

apt install -y udev
apt install -y zsh xterm hwloc

# replace default bash to zsh
if [ ! -e ~/.zshrc ]; then
	RUNZSH=no sh -c "$(wget https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh -O -)"
	chsh -s $(which zsh)
fi

# configure script after startup linux
if [ ! -e ~/.startup.sh ]; then
	cd ${HOME}
	touch .startup.sh
	chmod a+x .startup.sh
	echo "ifconfig eth0 192.168.10.20 netmask 255.255.255.0 up" >> .startup.sh
	echo "sh ~/.startup.sh" >> ~/.zshrc
fi


# update ldconfig cache
ldconfig
