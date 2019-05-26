	echo "Preparing"
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
	make ARCH="$ARCH" INSTALL_HDR_PATH="$ROOTFS/cross-tools/$TARGET" headers_install &> $LOGDIR/kernel_headers.log
	make clean &> $LOGDIR/kernel_headers.log
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
