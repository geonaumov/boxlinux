#! /bin/bash
# gnaumov@premiumworx.net

set -e

echo
echo "BOXMAKER - THE BOXLINUX DEVELOPMENT SCRIPT"
source ./boxmaker.conf

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
	echo "Build system init"
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

	FREEDISK=$(df ./ | grep dev | awk '{print $4}')
	MINDISK=8000000
	if [ ! $FREEDISK -lt $MINDISK ]; then
		echo "Not enough disk space!"
		exit
	fi

if [ -f /usr/bin/grub-mkrescue ]; then 
	echo "Found /usr/bin/grub-mkrescue"
	GRUBCMD="/usr/bin/grub-mkrescue"
fi

if [ -f /usr/bin/grub2-mkrescue ]; then 
	echo "Found /usr/bin/grub-mkrescue"
	GRUBCMD="/usr/bin/grub2-mkrescue"
fi 

		if which $GRUBCMD &> /dev/null ; then
			continue
		else
			echo "$GRUBCMD missing!"
			exit
		fi


	echo "Checking dependencies"
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
	echo "Looking for $(basename $FILENAME)"
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
	source config/boxmaker.conf
	unmount
	rm -rf $ROOTFS
	rm -rf $WORKING
	set +e
	unlink /tools &> /dev/null
	unlink /cross-tools &> /dev/null
	set -e
}

build_xtools () {
	echo "Building xtools-$ARCH-$BUILDID"
	source $DEFDIR/libexec/xtools.sh
	echo "Packing" 
	cd $ROOTFS
	tar cfz $OUTPUT/xtools-$ARCH-$BUILDID.tgz ./
	cd $WORKING
	clean_up
}

build_rootfs () {
	echo "Building rootfs-$ARCH-$BUILDID"
	rm -rf $ROOTFS
	mkdir -p $ROOTFS
	cd $ROOTFS
	echo Unpacking cross-tools
	tar xf $FILENAME
	source $DEFDIR/libexec/rootfs.sh
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
	echo "Unpacking the Linux kernel"
	tar xf $SRC/linux-*
	cd linux-*
	make mrproper 
	cp -rf $DEFDIR/kernel-$ARCH.conf .config
	echo "Building"
	make ARCH=$ARCH CROSS_COMPILE=$TARGET- 
	echo "Done."
	cp -rf arch/x86/boot/bzImage $OUTPUT/bzImage-$ARCH-$BUILDID
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
	rootfs)
		run_checks
		file_check $2
		clean_up
		setup_build
		build_rootfs $2
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
