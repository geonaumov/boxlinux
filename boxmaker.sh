#! /bin/bash
# gnaumov@premiumworx.net

set -e

echo "BOXMAKER - THE BOXLINUX DEVELOPMENT SCRIPT"
source config/boxmaker.config

init () {	
	mkdir -p $ROOTFS
	mkdir -p $WORKING
	mkdir -p $SRC
	mkdir -p $OUTPUT
	mkdir -p $LOGS
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

root_check () {
	if [[ $EUID -ne 0 ]]; then
		echo
		echo "This script must be run as root!"
   		help_me
		exit 1
	fi
}

clean_up () {
	root_check
	cd $DEFDIR
	source config/boxmaker.config
	unmount
	rm -rf $ROOTFS
	rm -rf $WORKING
	set +e
	unlink /tools
	unlink /cross-tools
	set -e
}

debian_deps () {
	root_check
	apt install git gcc g++ cpp make m4 bison flex xorriso grub bc
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
	download
	root_check
	echo "Building xtools-$ARCH-$BUILDID"
	source $DEFDIR/libexec/xtools.sh
        echo "Packing" 
	cd $ROOTFS
	tar cf $OUTPUT/xtools-$ARCH-$BUILDID.tar ./
	gzip $OUTPUT/xtools-$ARCH-$BUILDID.tar
	cd $WORKING
	clean_up
	echo Output file:
	ls -lh $OUTPUT/xtools-$ARCH-$BUILDID.tar
}

build_tools () {
	download
	root_check
	# Weird path error, check
	FILENAME=$(realpath $1)
	echo "Building tools-$ARCH-$BUILDID"
	echo "with xtools $FILENAME"
	rm -rf $ROOTFS
	mkdir -p $ROOTFS
	cd $ROOTFS
	tar xf $FILENAME
	source $DEFDIR/libexec/tools.sh
        echo "Cleaning up tools"
	cd $ROOTFS
	rm -rf cross-tools
	echo "Packing tools"
	tar cf $OUTPUT/tools-$ARCH-$BUILDID.tar ./
	gzip $OUTPUT/tools-$ARCH-$BUILDID.tar
	clean_up
	echo Output file:
	ls -lh $OUTPUT/tools-$ARCH-$BUILDID.tar
}

build_system () {
	set -e
	download
	root_check
	if [[ $EUID -ne 0 ]]; then
		echo "This script must be run as root"
   		exit 1
	fi
	FILENAME=$(realpath $1)
	
	if [ ! -f $FILENAME ]; then
		echo "File $(basename $FILENAME) not found!!!"
		exit
	fi

	echo "Preparing chroot and tools"
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
	echo "Adding base list"
	cp -rfv $DEFDIR/config/$BASELIST.list $ROOTFS/current.list
	cd $ROOTFS
	mount -v -t proc proc $ROOTFS/proc
	mount -v -t sysfs sysfs $ROOTFS/sys
	mount -v -t tmpfs tmpfs $ROOTFS/run
	mount -v -t tmpfs tmpfs $ROOTFS/tmp
	mount -v --bind /dev $ROOTFS/dev
	rm -rf ./dev/console
	mknod -m 600 ./dev/console c 5 1
	rm -rf ./dev/null
	mknod -m 666 ./dev/null c 1 3
pwd
echo "Setting up tools: $(basename $FILENAME)"
	tar xf $FILENAME
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
	cp -rfv /etc/resolv.conf $ROOTFS/etc/
	cp -rfv $DEFDIR/config/busybox-*.config $ROOTFS/
	mkdir -pv $ROOTFS/packages
	mount -v --bind $OUTPUT/packages $ROOTFS/packages
	mkdir -pv $ROOTFS/src
	mount -v --bind $SRC $ROOTFS/src
	mkdir -pv $ROOTFS/logs
	mount -v --bind $LOGS $ROOTFS/logs
	mkdir -pv $ROOTFS/boxbuild
	mount -v --bind $DEFDIR/boxbuild $ROOTFS/boxbuild
	cp -rf $DEFDIR/libexec/boxer.sh $ROOTFS/
	chmod +x $ROOTFS/boxer.sh
	mkdir -pv $ROOTFS/tools/etc/
	touch $ROOTFS/tools/etc/ld.so.conf
	cp -rvf $DEFDIR/sysconfig/* $ROOTFS/etc/
	echo "Running worker in chroot"
	cd $DEFDIR
	chroot $ROOTFS /tools/bin/ash boxer.sh
}

build_kernel () {
	echo "Starting a clean build"
	rm -rf $ROOTFS
	mkdir -p $ROOTFS
	cd $ROOTFS
	echo "Unpacking cross-tools"
	tar xf $OUTPUT/$(basename $1)
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
	root_check
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
	echo "   ./boxmaker.sh command /path/to/... "
	echo 
	echo "Commands:"
	echo
	echo "   download     - download sources (run first)"
	echo "   clean        - remove temporary data and unmount everything"
	echo "   debian_deps  - install Debian 9 x86_64 host tools"
	echo
	echo "   xtools                            - build cross-tools"
	echo "   tools /path/to/xtools-ID.tar.gz   - build tools"
	echo "   kernel /path/to/xtools-ID.tar.gz  - build kernel"
	echo "   packs /path/to/tools-ID.tar.gz    - build binary packages for target"
	echo "   live /path/to/bzImage-ID.tar.gz   - build iso for a rescue/installer cd"
	echo
}

case "$1" in
        debian_deps)
            	init
            	debian_deps
            	;;
        download)
            	init
            	download
            	;;
        xtools)
		unmount
		clean_up
            	init
            	build_xtools
            	;;
        tools)
		unmount
		clean_up
            	init
            	build_tools $2
            	;;
        system)
		unmount
		clean_up
            	init
            	build_system $2
            	;;
    	kernel)
		unmount
		clean_up
            	init
            	build_kernel $2
            	;;
	live)
       		init
		unmount
		clean_up
                build_live $(realpath $2)
            	;;
        clean)
		clean_up
		;;
        *)
		help_me
		exit 1
esac
