#! /bin/bash
# gnaumov@premiumworx.net

set -e

echo
echo "BOXMAKER - THE BOXLINUX DEVELOPMENT SCRIPT"
source config/boxmaker.config

deps_list="gcc
cpp
m4
make
flex
bison
bc
xorriso
grub-mkrescue
"

init () {	
	echo "Build system init"
	mkdir -p $ROOTFS
	mkdir -p $WORKING
	mkdir -p $SRC
	mkdir -p $OUTPUT
	mkdir -p $LOGS
}

root_check () {
	if [[ $EUID -ne 0 ]]; then
		echo
		echo "This script must be run as root!"
		help_me
		exit 1
	fi
}

file_check () {
	FILENAME=$(realpath $1)
	echo "Looking for $(basename $FILENAME)"
	if [ ! -f $FILENAME ]; then
		echo "File $FILENAME not found!"
		exit
	fi	
}

disk_check () {
	FREEDISK=$(df ./ | grep dev | awk '{print $4}')
	MINDISK=8000000
	if [ $FREEDISK -lt $MINDISK ]; then
		echo "Not enough disk space!"
		exit
	else
		echo "Disk space available."
	fi
}

deps_check () {
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

unmount () {
	echo "Unmounting virtual filesystems, if required"
	set +e
	umount $ROOTFS/proc &> /dev/null
	umount $ROOTFS/sys &> /dev/null
	umount $ROOTFS/dev &> /dev/null
	umount $ROOTFS/tmp &> /dev/null
	umount $ROOTFS/run &> /dev/null
	echo "Unbinding directories, if required"
	umount $ROOTFS/packages &> /dev/null
	umount $ROOTFS/src &> /dev/null
	umount $ROOTFS/logs &> /dev/null
	umount $ROOTFS/boxbuild &> /dev/null
	set -e
}

clean_up () {
	root_check
	cd $DEFDIR
	source config/boxmaker.config
	unmount
	rm -rf $ROOTFS
	rm -rf $WORKING
	set +e
	unlink /tools &> /dev/null
	unlink /cross-tools &> /dev/null
	set -e
}

download () {
	echo "Sources directory is: $SRC"
	cd $SRC
	# Must add checksums here somehow
	echo "Checking all sources"
	for file in $(cat $DEFDIR/config/system.list | grep -v "_script"); do
	if [ -f $DEFDIR/boxbuild/$file.boxbuild ]; then
        	export $(sed -n 1p $DEFDIR/boxbuild/$file.boxbuild)
        	export $(sed -n 4p $DEFDIR/boxbuild/$file.boxbuild)
        	export $(sed -n 5p $DEFDIR/boxbuild/$file.boxbuild)
	else 
		echo "Boxbuild $file missing!"
		exit
	fi
	if [ ! -f $SRC/${SOURCE} ]; then
            	echo "File $SOURCE not found, downloading from $URL"
            	wget -cq $URL/$SOURCE ;
    	fi
		
	done ;	
	cd ..
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

build_tools () {
	echo "Building tools-$ARCH-$BUILDID"
	rm -rf $ROOTFS
	mkdir -p $ROOTFS
	cd $ROOTFS
	tar xf $FILENAME
	source $DEFDIR/libexec/tools.sh
	echo "Cleaning up tools"
	cd $ROOTFS
	rm -rf cross-tools
	echo "Packing tools"
	tar zcf $OUTPUT/tools-$ARCH-$BUILDID.tgz ./
	clean_up
}

build_system () {
	set -e
	echo "Creating directory tree"
	mkdir -p $ROOTFS
	mkdir -p $OUTPUT/packages
	mkdir -p $ROOTFS/proc
	mkdir -p $ROOTFS/sys
	mkdir -p $ROOTFS/tmp
	mkdir -p $ROOTFS/run 
	mkdir -p $ROOTFS/dev 
	mkdir -p $ROOTFS/etc
	mkdir -p $ROOTFS/root
	mkdir -p $ROOTFS/bin
	mkdir -p $ROOTFS/sbin
	mkdir -p $ROOTFS/home
	mkdir -p $ROOTFS/root
	mkdir -p $ROOTFS/mnt
	mkdir -p $ROOTFS/lib
	mkdir -p $ROOTFS/usr/bin
	mkdir -p $ROOTFS/usr/sbin
	mkdir -p $ROOTFS/var/log
	cd $ROOTFS
	echo "Mounting virtual filesystems"
	mount -t proc proc $ROOTFS/proc
	mount -t sysfs sysfs $ROOTFS/sys
	mount -t tmpfs tmpfs $ROOTFS/run
	mount -t tmpfs tmpfs $ROOTFS/tmp
	mount --bind /dev $ROOTFS/dev
	rm -rf ./dev/console
	mknod -m 600 ./dev/console c 5 1
	rm -rf ./dev/null
	mknod -m 666 ./dev/null c 1 3
	echo "Unpacking tools: $(basename $FILENAME)"
	tar xf $FILENAME
	echo "Setting up rootfs"
	cp -rf $DEFDIR/config/$BASELIST.list $ROOTFS/current.list
	cd bin
	ln -s ../tools/bin/ash sh
	ln -s ../tools/bin/ash ash
	ln -s ../tools/bin/cat cat
	ln -s ../tools/bin/echo echo
	ln -s ../tools/bin/pwd pwd
	ln -s ../tools/bin/stty stty
	cd ../
	cd lib
	ln -s ../tools/lib/ld-2.26.so ld-linux-x86-64.so.2
	ln -s ../tools/lib/libc.so.6 ./
	ln -s ../tools/lib/libgcc_s.so.1 ./
	ln -s ../tools/lib/libstdc++.so.6 ./
	ln -s ../tools/lib/libmpc.so.3 ./
	ln -s ../tools/lib/libmpfr.so.4 ./
	ln -s ../tools/lib/libgmp.so.10 ./
	ln -s ../tools/lib/libgmpxx.so.4 ./
	ln -s ../tools/lib/libz.so.1 ./
	sed -e 's/tools/usr/' ../tools/lib/libstdc++.la > ./libstdc++.la
	cp -rf /etc/resolv.conf $ROOTFS/etc/
	cp -rf $DEFDIR/config/busybox-*.config $ROOTFS/
	cp -rf $DEFDIR/libexec/boxer.sh $ROOTFS/
	chmod +x $ROOTFS/boxer.sh
	mkdir -p $ROOTFS/tools/etc/
	touch $ROOTFS/tools/etc/ld.so.conf
	cp -rf $DEFDIR/sysconfig/* $ROOTFS/etc/
	echo "Binding directories"
	mkdir -p $ROOTFS/packages
	mount --bind $OUTPUT/packages $ROOTFS/packages
	mkdir -p $ROOTFS/src
	mount --bind $SRC $ROOTFS/src
	mkdir -p $ROOTFS/logs
	mount --bind $LOGS $ROOTFS/logs
	mkdir -p $ROOTFS/boxbuild
	mount --bind $DEFDIR/boxbuild $ROOTFS/boxbuild
	echo "Running boxer in chroot"
	cd $DEFDIR
	chroot $ROOTFS /tools/bin/ash boxer.sh
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
	cp -rf $CONFIG/kernel.config .config
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
		root_check
		deps_check
		disk_check
		clean_up
		init
		download
		build_xtools
		;;
	tools)
		root_check
		file_check $2
		deps_check
		disk_check
		clean_up
		init
		download
		build_tools $2
		;;
	system)
		root_check
		file_check $2
		disk_check
		clean_up
		init
		download
		build_system $2
		;;
	kernel)
		root_check
		file_check $2
		deps_check
		disk_check
		clean_up
		init
		download
		build_kernel $2
		;;
	live)
		root_check
		clean_up
		init
		download
		build_live $(realpath $2)
		;;
	clean)
		clean_up
		;;
	*)
		help_me
		exit 1
esac
