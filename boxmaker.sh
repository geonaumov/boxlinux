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
		echo "Preparing filesystem"
	mkdir -p $ROOTFS/cross-tools/lib
	mkdir -p $ROOTFS/tools
	cd $ROOTFS/cross-tools
	ln -sfn . usr
	ln -sfn lib lib64
	mkdir -p $TARGET
	cd $TARGET
	ln -sfn . usr
	ln -sfn lib lib64
	cd /
	ln -sfn $ROOTFS/cross-tools /
	ln -sfn $ROOTFS/tools /
	export PATH="/cross-tools/bin:$DEFPATH"
mkdir -pv $WORKING
	cd $WORKING
	
	# Logging
	mkdir -pv $LOGS/xtools-$BUILDID
	LOGDIR="$LOGS/xtools-$BUILDID/"

	echo "Kernel headers"
	tar xf $SRC/linux-*
	cd linux-*
	if ARCH="aarch64"; then
		OLDARCH=$ARCH
		ARCH=arm
	fi
	make ARCH="$ARCH" INSTALL_HDR_PATH="$ROOTFS/cross-tools/$TARGET" headers_install &> $LOGDIR/kernel_headers.log
	make clean &> $LOGDIR/kernel_headers.log
	ARCH=$OLDARCH
	cd $WORKING
	rm -rf linux-*

	echo "Binutils"
	tar xf $SRC/binutils-*
	cd binutils-*
	mkdir -p binutils-build
	cd binutils-build
	../configure  --prefix="$ROOTFS/cross-tools"  \
	 --target="$TARGET" --disable-nls	      \
	 --disable-multilib --disable-werror	      \
	 --with-sysroot="$ROOTFS/cross-tools/$TARGET" \
	 --disable-gold >> $LOGDIR/binutils.log
	make  &> $LOGDIR/binutils.log
	make install &> $LOGDIR/binutils.log
	cd $WORKING
	rm -rf binutils-*
	
	echo "GMP, MPC, MPFR and GCC - Pass 1"
	tar xf $SRC/gcc-*
	cd gcc-*
	tar xf $SRC/gmp-*
	tar xf $SRC/mpc-*
	tar xf $SRC/mpfr-*
	mv gmp-* gmp
	mv mpc-* mpc
	mv mpfr-* mpfr
	mkdir -p gcc-build
	cd gcc-build

	../configure --prefix="$ROOTFS/cross-tools"     \
	 --target="$TARGET" --host=$HOST --build=$HOST  \
	 --with-sysroot="$ROOTFS/cross-tools/$TARGET"   \
	 --disable-multilib --disable-threads		\
	 --disable-libquadmath --disable-libatomic	\
	 --disable-libssp --disable-libmudflap 		\
	 --disable-libgomp --disable-decimal-float	\
	 --with-newlib  --without-headers --disable-nls \
	 --disable-shared --enable-languages=c,c++	\
	 --disable-libsanitizer  &> $LOGDIR/gcc_pass1.log

	make all-gcc all-target-libgcc &> $LOGDIR/gcc_pass1.log
	make install-gcc install-target-libgcc  &> $LOGDIR/gcc_pass1.log
	cd $WORKING
	rm -rf gcc-*
	
	echo "Musl libc"
	cd $WORKING
	tar xf $SRC/musl-*.tar.gz
	cd musl-*
	mkdir -p musl-build
	cd musl-build
	../configure CROSS_COMPILE=$TARGET- --prefix="/"  --target="$TARGET"   &> $LOGDIR/musl.log
	make  >> $LOGS/xtools-musl-$BUILDID.log
	make DESTDIR=$ROOTFS/cross-tools/$TARGET install  &> $LOGDIR/musl.log
	cd $WORKING
	rm -rf musl-*
	
	echo "GMP, MPC, MPFR and GCC - Pass 2"
	tar xf $SRC/gcc-*
	cd gcc-*
	tar xf $SRC/gmp-*
	tar xf $SRC/mpc-*
	tar xf $SRC/mpfr-*
	mv gmp-* gmp
	mv mpc-* mpc
	mv mpfr-* mpfr
	mkdir -p gcc-build
	cd gcc-build

	../configure --prefix="$ROOTFS/cross-tools"   \
	 --target="$TARGET" --host=$HOST	      \
	 --build=$HOST				      \
	 --with-sysroot="$ROOTFS/cross-tools/$TARGET" \
	 --disable-multilib --enable-c99	      \
	 --enable-long-long --disable-libmudflap      \
	 --enable-languages=c,c++			\
         --disable-libgomp --disable-libsanitizer       \
         --disable-nls --disable-libmudflap             \
         --disable-libssp --disable-libquadmath          \
         --disable-libatomic --disable-libmpx            \
         --disable-libitm --disable-libvtv               \
         --disable-libcilkrts  &> $LOGDIR/gcc_pass2.log
	make  &> $LOGDIR/gcc_pass2.log
	make install  &> $LOGDIR/gcc_pass2.log
	cd $WORKING
	rm -rf gcc-*
	echo "Finished building xtools"

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
	LOGDIR="$DEFDIR/logs"
	cd $ROOTFS
	
	set -e
	echo -ne '#(1%)\r'
	cd $ROOTFS
	ln -sfn $ROOTFS/cross-tools /
	
	msg "Preparing filesystem"
	export AS_FOR_TARGET=""
	export CC="$TARGET-gcc"
	export CXX="$TARGET-g++"
	export CFLAGS="-I$ROOTFS/usr/include"
	export CXXFLAGS="-I$ROOTFS/usr/include"
	export LDFLAGS="-L$ROOTFS/usr/lib -L$ROOTFS/usr/lib"
	export LD=$TARGET-ld
	export AR=$TARGET-ar 
	export AS=$TARGET-as 
	export NM=$TARGET-nm 
	export RANLIB=$TARGET-ranlib 
	export READELF=$TARGET-readelf
	export STRIP=$TARGET-strip
	export PATH="/cross-tools/bin:/cross-tools/sbin:/bin:/sbin:/usr/bin:/usr/sbin"
	
	mkdir -p $ROOTFS/bin
	mkdir -p $ROOTFS/sbin
	mkdir -p $ROOTFS/proc
	mkdir -p $ROOTFS/sys
	mkdir -p $ROOTFS/tmp
	mkdir -p $ROOTFS/root
	mkdir -p $ROOTFS/home
	mkdir -p $ROOTFS/mnt
	mkdir -p $ROOTFS/dev
	mkdir -p $ROOTFS/etc/acpi
	mkdir -p $ROOTFS/var/log
	mkdir -p $ROOTFS/var/run
	mkdir -p $ROOTFS/var/spool/cron/crontabs
	mkdir -p $ROOTFS/lib64
	mkdir -p $ROOTFS/usr/lib64
	mkdir -p $ROOTFS/run
	ln -sf ./lib64 ./lib
	cd usr
	ln -sf ./lib64 ./lib
	cd $ROOTFS
	
	touch $ROOTFS/etc/mtab
	
	cd $ROOTFS/dev
	mknod fd0 b 2 0
	mknod fd1 b 2 1
	mknod hda b 3 0
	mknod hda1 b 3 1
	mknod hda2 b 3 2
	mknod hda3 b 3 3
	mknod hda4 b 3 4
	mknod hda5 b 3 5
	mknod hda6 b 3 6
	mknod hda7 b 3 7
	mknod hda8 b 3 8
	mknod hdb b 3 64
	mknod hdb1 b 3 65
	mknod hdb2 b 3 66
	mknod hdb3 b 3 67
	mknod hdb4 b 3 68
	mknod hdb5 b 3 69
	mknod hdb6 b 3 70
	mknod hdb7 b 3 71
	mknod hdb8 b 3 72
	mknod tty c 5 0
	mknod console c 5 1
	mknod tty1 c 4 1
	mknod tty2 c 4 2
	mknod tty3 c 4 3
	mknod tty4 c 4 4
	mknod ram b 1 1
	mknod mem c 1 1
	mknod kmem c 1 2
	mknod null c 1 3
	mknod zero c 1 5
	
	cd $ROOTFS
	
	cp -rf $DEFDIR/config/* $ROOTFS/etc/
	chown -R root:root $ROOTFS/etc/
	
	chmod +x etc/service/*/run
	chmod +x etc/service/*/log/run
	chmod +x etc/service/logger.sh
	
	mkdir -p var/service
	ln -s /etc/service/01.klogd/ var/service/
	ln -s /etc/service/02.syslogd/ var/service/
	ln -s /etc/service/03.crond/ var/service/
	ln -s /etc/service/04.ntpd/ var/service/
	ln -s /etc/service/99.console/ var/service/
	
	rm -rf $WORKING
	mkdir $WORKING
	cd $WORKING
	
	msg "Busybox"
	tar xf $SRC/busybox-*
	cd busybox-*
	cp -rf $DEFDIR/busybox-$ARCH.conf .config
	make &> $LOGDIR/busybox-build-$ARCH-$BUILDID.log
	make install &> $LOGDIR/busybox-install-$ARCH-$BUILDID.log
	cp -rf _install/* $ROOTFS/
	
	## UDHCPC SCRIPT
	mkdir -p $ROOTFS/usr/share/udhcpc
	cp -rf examples/udhcp/simple.script $ROOTFS/usr/share/udhcpc/default.script
	chmod +x $ROOTFS/usr/share/udhcpc/default.script
	cd $WORKING
	rm -rf busybox-*
	
	msg "Musl libc"
	tar xf $SRC/musl-*
	cd musl-*
	./configure --prefix=/usr --enable-shared  	\
		--libdir=/usr/lib			\
		--host=$ARCH-box-linux-musl  		\
	        --build=$(uname -m)-linux-gnu 		\
	        --target=$ARCH-box-linux-musl &> $LOGDIR/musl-conf-$ARCH-$BUILDID.log
	make &> $LOGDIR/musl-build-$ARCH-$BUILDID.log
	make install DESTDIR=$ROOTFS &> $LOGDIR/musl-install-$ARCH-$BUILDID.log
	cd $WORKING
	rm -rf musl-*
	
	msg "zlib"
	tar xf $SRC/zlib-*
	cd zlib-*
	./configure --prefix=/usr --enable-shared &> $LOGDIR/zlib-conf-$ARCH-$BUILDID.log
	make &> $LOGDIR/zlib-build-$ARCH-$BUILDID.log
	make install DESTDIR=$ROOTFS &> $LOGDIR/zlib-install-$ARCH-$BUILDID.log
	cd $WORKING
	rm -rf zlib-*
	
	msg "LibreSSL"
	tar xf $SRC/libressl-*
	cd libressl-*
	./configure --prefix=/usr --build=$(uname -m)-linux-gnu --enable-shared  	\
		--libdir=/usr/lib			\
		--host=$ARCH-box-linux-musl &> $LOGDIR/libressl-conf-$ARCH-$BUILDID.log
	make &> $LOGDIR/libressl-build-$ARCH-$BUILDID.log
	make install DESTDIR=$ROOTFS &> $LOGDIR/libressl-install-$ARCH-$BUILDID.log
	cd $WORKING
	rm -rf libressl-*
	
	msg "OpenSSH"
	tar xf $SRC/openssh-*
	cd openssh-*
	./configure --prefix=/usr --build=$(uname -m)-linux-gnu --enable-shared --with-md5-passwords  \
		--disable-wtmp --disable-wtmpx --without-pam 		\
		--sysconfdir=/etc/sshd --libdir=/usr/lib 			\
		--host=$ARCH-box-linux-musl --disable-strip &> $LOGDIR/openssh-conf-$ARCH-$BUILDID.log
	make &> $LOGDIR/openssh-build-$ARCH-$BUILDID.log
	make install DESTDIR=$ROOTFS &> $LOGDIR/openssh-install-$ARCH-$BUILDID.log
	cd $WORKING
	rm -rf openssh-*
	
	msg "RSync"
	tar xf $SRC/rsync-*
	cd rsync-*
	./configure --prefix=/usr --build=$(uname -m)-linux-gnu --host=$ARCH-box-linux-musl &> $LOGDIR/rsync-conf-$ARCH-$BUILDID.log
	make &> $LOGDIR/rsync-build-$ARCH-$BUILDID.log
	make install DESTDIR=$ROOTFS &> $LOGDIR/rsync-install-$ARCH-$BUILDID.log
	cd $WORKING
	rm -rf rsync-*
	
	msg "Links"
	tar xf $SRC/links-*
	cd links-*
	./configure --prefix=/usr --build=$(uname -m)-linux-gnu --host=$ARCH-box-linux-musl &> $LOGDIR/links-conf-$ARCH-$BUILDID.log
	make &> $LOGDIR/links-build-$ARCH-$BUILDID.log
	make install DESTDIR=$ROOTFS &> $LOGDIR/links-install-$ARCH-$BUILDID.log
	cd $WORKING
	rm -rf links-*
	
	# msg "Make"
	# tar xf $SRC/make-*
	# cd make-*
	# ./configure  --prefix="/usr" --build=$(uname -m)-linux-gnu --host="$TARGET"  &> $LOGDIR/make-conf-$ARCH-$BUILDID.log
	# make &> $LOGDIR/make-build-$ARCH-$BUILDID.log
	# make install  DESTDIR=$ROOTFS &> $LOGDIR/make-install-$ARCH-$BUILDID.log
	# cd $WORKING
	# rm -rf make-*
	
	# msg "M4"
	# tar xf $SRC/m4-*
	# cd m4-*
	# ./configure  --prefix="/usr" --build=$(uname -m)-linux-gnu --host="$TARGET"  &> $LOGDIR/m4-conf-$ARCH-$BUILDID.log 
	# make &> $LOGDIR/m4-build-$ARCH-$BUILDID.log
	# make install  DESTDIR=$ROOTFS &> $LOGDIR/m4-install-$ARCH-$BUILDID.log
	# cd $WORKING
	# rm -rf m4-*
	
	# msg "Patch"
	# tar xf $SRC/patch-*
	# cd patch-*
	# ./configure  --prefix="/usr" --build=$(uname -m)-linux-gnu --host="$TARGET" &> $LOGDIR/patch-conf-$ARCH-$BUILDID.log
	# make  &> $LOGDIR/patch-build-$ARCH-$BUILDID.log
	# make install  DESTDIR=$ROOTFS &> $LOGDIR/patch-install-$ARCH-$BUILDID.log
	# cd $WORKING
	# rm -rf patch-*
	
	# msg "Binutils"
	# tar xf $SRC/binutils-*
	# cd binutils-*
	# mkdir -p binutils-build
	# cd binutils-build
	# ../configure --prefix=/usr --build=$(uname -m)-linux-gnu --host=$TARGET  --target=$TARGET    \
	# 	--with-lib-path=/usr/lib  --disable-nls      \
	# 	--enable-shared --enable-64-bit-bfd    \
	# 	--disable-multilib --disable-gold --enable-plugins    \
	# 	--with-system-zlib --enable-threads  >> $LOGS/binutils-conf-$ARCH-$BUILDID.log
	# make  &> $LOGDIR/binutils-build-$ARCH-$BUILDID.log
	# make install DESTDIR=$ROOTFS &> $LOGDIR/binutils-install-$ARCH-$BUILDID.log
	# cd $WORKING
	# rm -rf binutils-*
	
	# msg "GCC"
	# tar xf $SRC/gcc-*
	# cd gcc-*
	
	# tar xf $SRC/gmp-*
	# tar xf $SRC/mpc-*
	# tar xf $SRC/mpfr-*
	# mv ./gmp-* ./gmp
	# mv ./mpc-* ./mpc
	# mv ./mpfr-* ./mpfr
	
	# echo "StartFile Spec"
	# echo -en '\n#undef STANDARD_STARTFILE_PREFIX_1\n#define STANDARD_STARTFILE_PREFIX_1 "/usr/lib/"\n' >> gcc/config/linux.h
	# echo -en '\n#undef STANDARD_STARTFILE_PREFIX_2\n#define STANDARD_STARTFILE_PREFIX_2 ""\n' >> gcc/config/linux.h
	# echo "Disabling fixinclude tests"
	# cp -v gcc/Makefile.in gcc/Makefile.in.orig
	# sed 's@\./fixinc\.sh@-c true@' gcc/Makefile.in.orig > gcc/Makefile.in
	# mkdir -p gcc-build
	# cd gcc-build
	# ../configure --prefix=/usr 	\
	# 	--build=$(uname -m)-linux-gnu --host=$TARGET --target=$TARGET		\
	# 	--with-local-prefix=/usr		\
	# 	--disable-multilib			\
	# 	--enable-languages=c,c++   \
	# 	--with-system-zlib 	\
	# 	--with-native-system-header-dir=/usr/include 	\
	# 	--enable-c99  \
	#        	--enable-long-long  \
	# 	--enable-install-libiberty  \
	#  	--disable-libgomp --disable-libsanitizer       \
	#  	--disable-nls --disable-libmudflap             \
	# 	--disable-libssp --disable-libquadmath          \
	# 	--disable-libatomic --disable-libmpx            \
	# 	--disable-libitm --disable-libvtv               \
	# 	--disable-libcilkrts   &> $LOGDIR/gcc-conf-$ARCH-$BUILDID.log
	
	# make AS_FOR_TARGET=$TARGET-as LD_FOR_TARGET=$TARGET-ld   &> $LOGDIR/gcc-build-$ARCH-$BUILDID.log
	# make install DESTDIR=$ROOTFS &> $LOGDIR/gcc-install-$ARCH-$BUILDID.log
	# cd $WORKING
	# rm -rf gcc-*
	
	msg "Done building"
	
	cd $ROOTFS
	
	msg "Final adjustments"
	ln -s ./sbin/init ./
	chmod +x ./init
	chmod +x ./etc/sysinit
	
	rm -rf tools
	rm -rf cross-tools
	
	msg "Creating initramfs"
	find . | cpio -o --format=newc > $OUTPUT/initramfs-$ARCH-$BUILDID
	echo "Output file is: $OUTPUT/initramfs-$ARCH-$BUILDID"
	
	msg "Creating cpio initramfs"
	find . | cpio -H newc -o | gzip > $OUTPUT/initramfs-$ARCH-$BUILDID.cpio.gz  
	echo "Output file is: $OUTPUT/initramfs-$ARCH-$BUILDID.cpio.gz"
	echo
	
	msg "Creating tar archive"
	tar czf $OUTPUT/rootfs-$ARCH-$BUILDID.tgz ./  
	echo "Output file is: $OUTPUT/rootfs-$ARCH-$BUILDID.tgz"
	
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
		# if ARCH="aarch64"; then  
		# 	OLDARCH=$ARCH
		# 	echo "The correct architecture variable for aarch64 is arm64"
		# 	export ARCH="arm64"
		# fi
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

build_iso () {

mkdir -p $WORKING/iso
cp -rfv $2 $WORKING/iso/ramfs.cpio.gz
cp -rfv $1 $WORKING/iso/kernel
cd $WORKING

echo "CD/ISO bootloader configuration"
mkdir -pv iso/boot/grub
cat >  iso/boot/grub/grub.cfg << "EOF"
set timeout=5
set default=0
set menu_color_normal=yellow/black
set menu_color_highlight=black/yellow
menuentry "BoxLinux Live - Boot from CD" {
      set root=(cd)
      echo Loading kernel
      linux /kernel root=/dev/ram0 quiet splash nomodeset
      echo Loading ramfs
      initrd /ramfs.cpio.gz
      boot
}
EOF

echo "Creating ISO image"

if [ -f /usr/bin/grub-mkrescue ]; then 
	echo "Found /usr/bin/grub-mkrescue"
	GRUBCMD="/usr/bin/grub-mkrescue"
else 
	echo "Assuming you have grub2-mkrescue"
	GRUBCMD="/usr/bin/grub2-mkrescue"
fi
	
$GRUBCMD -V BOXLINUX -o $OUTPUT/boxlinux-$ARCH-$BUILDID.iso iso

echo 
echo "Done. Output file is: $OUTPUT/boxlinux-$ARCH-$BUILDID.iso"
echo

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
	echo "   kernel   /path/to/xtools-ID.tar.gz   - build kernel with XTOOLS"
	echo "   system   /path/to/tools-ID.tar.gz    - build binary packages with TOOLS"
	echo
	echo "Build ISO with KERNEL and RAMFS as options (experimental, requires grub2"
	echo "   iso     /path/to/bzImage-ID.tar.gz /path/to/ramfs-ID.tar.gz"
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
	iso)
		run_checks
		file_check $2
		clean_up
		setup_build
		build_iso $2 $3
		;;
	clean)
		run_checks
		clean_up
		;;
	*)
		help_me
		exit 1
esac
