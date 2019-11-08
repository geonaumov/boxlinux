#! /bin/bash
# gnaumov@premiumworx.net

msg () {
	echo -e "[\e[33m $( date +%H:%M:%S)\e[39m ] $1"
}

set -e
echo -e "\e[33mBOXMAKER - THE BOXLINUX DEVELOPMENT SCRIPT\e[39m"
source ./boxmaker.conf

echo "Build ID number:   $BUILDID"
echo "Build system:      $(uname -m)"
echo "Host system:       $ARCH"
echo "Target toolchain:  $TARGET"
echo "Number of cores:   $(nproc)"
echo "Root directory:    $ROOTFS"
echo "Working directory: $WORKING"
echo "Sources directory: $SRC"
echo "Output directory:  $OUTPUT"

deps_list="gcc
cpp
m4
make
flex
bison
bc
xorriso
"

setup_build () {
	mkdir -p $ROOTFS
	mkdir -p $WORKING
	mkdir -p $SRC
	mkdir -p $OUTPUT
	mkdir -p $LOGS
}

run_checks () {
	if [[ $EUID -ne 0 ]]; then
		echo
		echo "This script must be run as root!"
		help_me
		exit 1
	fi

if [ -f /usr/bin/grub-mkrescue ]; then 
	GRUBCMD="/usr/bin/grub-mkrescue"
fi

if [ -f /usr/bin/grub2-mkrescue ]; then 
	GRUBCMD="/usr/bin/grub2-mkrescue"
fi 

	for command in $deps_list
	do
		if which $command &> /dev/null ; then
			continue
		else
			echo "$command missing!"
			exit
		fi
	done

}

file_check () {
	FILENAME=$(realpath $1)
	if [ ! -f $FILENAME ]; then
		echo "File $FILENAME not found!"
		exit
	fi
}

unmount () {
	set +e
	umount $ROOTFS/proc &> /dev/null
	umount $ROOTFS/sys &> /dev/null
	umount $ROOTFS/dev &> /dev/null
	umount $ROOTFS/tmp &> /dev/null
	umount $ROOTFS/run &> /dev/null
	umount $ROOTFS/packages &> /dev/null
	umount $ROOTFS/src &> /dev/null
	umount $ROOTFS/logs &> /dev/null
	umount $ROOTFS/boxbuild &> /dev/null
	set -e
}

clean_up () {
	cd $DEFDIR
	source ./boxmaker.conf
	unmount
	rm -rf $ROOTFS
	rm -rf $WORKING
	set +e
	unlink /tools &> /dev/null
	unlink /cross-tools &> /dev/null
	set -e
}

build_xtools () {
	msg "Building xtools-$ARCH-$BUILDID"
	source $DEFDIR/libexec/xtools.sh
	msg "Packing" 
	cd $ROOTFS
	tar cfz $OUTPUT/xtools-$ARCH-$BUILDID.tgz ./
	cd $WORKING
	msg "Done packing $OUTPUT/xtools-$ARCH-$BUILDID.tgz"
	clean_up
}

build_system () {
	rm -rf $ROOTFS
	mkdir -p $ROOTFS
	cd $ROOTFS
	msg "Unpacking $FILENAME"
	tar xf $FILENAME
	source $DEFDIR/libexec/system.sh
	clean_up
}

build_kernel () {
	rm -rf $ROOTFS
	mkdir -p $ROOTFS
	cd $ROOTFS
	echo "Unpacking cross-tools"
	tar xf $FILENAME
	ln -sfn $ROOTFS/cross-tools /
	export PATH=/cross-tools/bin:/cross-tools/sbin:/bin:/sbin:/usr/bin:/usr/sbin
	cd $WORKING
	echo "Unpacking and preparing source"
	tar xf $SRC/linux-*
	cd linux-*
		if ARCH="aarch64"; then  
			OLDARCH=$ARCH
			echo "The correct architecture variable for aarch64 is arm64"
			export ARCH="arm64"
		fi
		make mrproper
		echo "Configuring kernel"
		CROSS_COMPILE=$TARGET- make defconfig &> $DEFDIR/logs/kernel-config-$ARCH-$BUILDID.log
		echo "Building kernel"
		CROSS_COMPILE=$TARGET- make &> $DEFDIR/logs/kernel-build-$ARCH-$BUILDID.log
		echo "Done."
		cp -rf arch/$ARCH/boot/bzImage $OUTPUT/kernel-$ARCH-$BUILDID
		export ARCH=$OLDARCH
	cd $WORKING
	rm -rf linux-*
}

build_live () {
	echo "Building live image"
	FILENAME=$1
	file_check $1
	echo "Using kernel $FILENAME"
	rm -rf $ROOTFS
	mkdir -p $ROOTFS
	cd $DEFDIR
	source libexec/live.sh
	clean_up
	echo "Done"
}

help_me () {
	echo 
	echo "Usage: "
	echo
	echo "   ./boxmaker.sh command [ /path/to/... ]"
	echo 
	echo "Commands:"
	echo
	echo "   download                             - download sources"
	echo "   clean                                - remove and unmount everything"
	echo "   xtools                               - build xtools"
	echo "   tools    /path/to/xtools-ID.tar.gz   - build tools with XTOOLS"
	echo "   kernel   /path/to/xtools-ID.tar.gz   - build kernel with XTOOLS"
	echo "   system   /path/to/tools-ID.tar.gz    - build binary packages with TOOLS"
	echo "   live     /path/to/bzImage-ID.tar.gz  - build live iso with KERNEL"
	echo
}

case "$1" in
	download)
		init
		download
		;;
	xtools)
		run_checks
		clean_up
		setup_build
		build_xtools
		;;
	system)
		run_checks
		file_check $2
		clean_up
		setup_build
		build_system $2
		;;
	kernel)
		run_checks
		file_check $2
		clean_up
		setup_build
		build_kernel $2
		;;
	live)
		run_checks
		file_check $2
		clean_up
		setup_build
		build_live $(realpath $2)
		;;
	clean)
		run_checks
		clean_up
		;;
	*)
		help_me
		exit 1
esac
