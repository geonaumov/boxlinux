set -e
echo "Preparing"
echo -ne '#(1%)\r'
mkdir -p $ROOTFS/tools
cd $ROOTFS/tools
ln -sfn lib lib64
cd $ROOTFS
ln -sfn $ROOTFS/cross-tools /
ln -sfn $ROOTFS/tools /	

export CC="$TARGET-gcc"
export CXX="$TARGET-g++"
export CFLAGS="-I/tools/include"
export CXXFLAGS="-I/tools/include"
export LDFLAGS="-L/tools/lib"
export LD=$TARGET-ld
export AR=$TARGET-ar 
export AS=$TARGET-as 
export NM=$TARGET-nm 
export RANLIB=$TARGET-ranlib 
export READELF=$TARGET-readelf
export STRIP=$TARGET-strip
export PATH="/cross-tools/bin:/cross-tools/sbin:/bin:/sbin:/usr/bin:/usr/sbin"

cd $WORKING

# Logging
mkdir -p $LOGS/tools-$BUILDID
LOGDIR="$LOGS/tools-$BUILDID/"

echo "Musl libc"
cd $WORKING
tar xf $SRC/musl-*.tar.gz
cd musl-*
./configure --prefix=/ --enable-shared CROSS_COMPILE=$TARGET-  &> $LOGDIR/musl.log
make &> $LOGDIR/musl.log
make install DESTDIR=/tools &> $LOGDIR/musl.log
cd $WORKING
rm -rf musl-*

echo "Busybox"
tar xf $SRC/busybox-*
cd busybox*
cp -rf $DEFDIR/config/busybox-host.config .config
make &> $LOGDIR/busybox.log
make install &> $LOGDIR/busybox.log
cd $WORKING
rm -rf busybox*

echo "Zlib"
cd $WORKING
tar xf $SRC/zlib-*
cd zlib-*
./configure --prefix=/tools  &> $LOGDIR/zlib.log
make  &> $LOGDIR/zlib.log
make install DESTDIR="$ROOTFS" &> $LOGDIR/zlib.log
cd $WORKING
rm -rf zlib-*

echo "Make"
tar xf $SRC/make-*
cd make-*
./configure  --prefix="/tools" --host="$TARGET" --build="$HOST"  &> $LOGDIR/make.log
make &> $LOGDIR/make.log
make install  DESTDIR=$ROOTFS &> $LOGDIR/make.log
cd $WORKING
rm -rf make-*

echo "M4"
tar xf $SRC/m4-*
cd m4-*
./configure  --prefix="/tools" --host="$TARGET" --build="$HOST" &> $LOGDIR/m4.log 
make &> $LOGDIR/m4.log
make install  DESTDIR=$ROOTFS &> $LOGDIR/m4.log
cd $WORKING
rm -rf m4-*

echo "GMP"
tar xf $SRC/gmp-*
cd gmp-*
CC_FOR_BUILD=gcc ./configure  --prefix="/tools" --host="$TARGET" --build="$HOST" --enable-cxx  &> $LOGDIR/gmp.log
make  &> $LOGDIR/gmp.log
make install  &> $LOGDIR/gmp.log
cd $WORKING
rm -rf gmp-*

echo "MPFR"
tar xf $SRC/mpfr-*
cd mpfr-*
./configure --with-gmp=/tools --prefix="/tools" --host="$TARGET" --build="$HOST"  &> $LOGDIR/mpfr.log
make  &> $LOGDIR/mpfr.log
make install &> $LOGDIR/mpfr.log
cd $WORKING
rm -rf mpfr-*

echo "MPC"
tar xf $SRC/mpc-*
cd mpc-*
./configure --with-gmp=/tools  --prefix="/tools" --host="$TARGET" --build="$HOST"  &> $LOGDIR/mpc.log 
make  &> $LOGDIR/mpc.log
make install  &> $LOGDIR/mpc.log
cd $WORKING
rm -rf mpc-*

echo "Binutils"
tar xf $SRC/binutils-*
cd binutils-*
mkdir -p binutils-build
cd binutils-build
../configure --prefix=/tools --build=$HOST   --host=$TARGET  --target=$TARGET  --with-lib-path=/tools/lib  --disable-nls  --enable-shared --enable-64-bit-bfd  --disable-multilib --disable-gold --enable-plugins --with-system-zlib --enable-threads  >> $LOGS/tools-binutils-config-$BUILDID.log
make  &> $LOGDIR/binutils.log
make install  &> $LOGDIR/binutils.log
cd $WORKING
rm -rf binutils-*

echo "GCC"
tar xf $SRC/gcc-*
cd gcc-*
echo "StartFile Spec"
echo -en '\n#undef STANDARD_STARTFILE_PREFIX_1\n#define STANDARD_STARTFILE_PREFIX_1 "/tools/lib/"\n' >> gcc/config/linux.h
echo -en '\n#undef STANDARD_STARTFILE_PREFIX_2\n#define STANDARD_STARTFILE_PREFIX_2 ""\n' >> gcc/config/linux.h
echo "Disabling fixinclude tests"
cp -v gcc/Makefile.in gcc/Makefile.in.orig
sed 's@\./fixinc\.sh@-c true@' gcc/Makefile.in.orig > gcc/Makefile.in
mkdir -p gcc-build
cd gcc-build
../configure --prefix=/tools --build=$HOST	\
	--host=$TARGET --target=$TARGET		\
	--with-local-prefix=/tools		\
	--disable-multilib			\
	--enable-languages=c,c++   \
	--with-system-zlib 	\
	--with-native-system-header-dir=/tools/include 	\
	--enable-c99  \
       	--enable-long-long  \
	--enable-install-libiberty  \
 	--disable-libgomp --disable-libsanitizer       \
 	--disable-nls --disable-libmudflap             \
	--disable-libssp --disable-libquadmath          \
	--disable-libatomic --disable-libmpx            \
	--disable-libitm --disable-libvtv               \
	--disable-libcilkrts   >> $LOGS/tools-gcc-config-$BUILDID.log

make AS_FOR_TARGET=$TARGET-as LD_FOR_TARGET=$TARGET-ld  &> $LOGDIR/binutils.log
make install  &> $LOGDIR/binutils.log
cd $WORKING
rm -rf gcc-*

echo "File"
tar xf $SRC/file-*
cd file-*
./configure  --prefix="/tools" --host="$TARGET" --build="$HOST"  >> $LOGS/tools-file-config-$BUILDID.log
make  >> $LOGS/tools-file-$BUILDID.log
make install  DESTDIR=$ROOTFS >> $LOGS/tools-file-$BUILDID.log
cd $WORKING
rm -rf file-*

echo "Patch"
tar xf $SRC/patch-*
cd patch-*
./configure  --prefix="/tools" --host="$TARGET" --build="$HOST" &> $LOGDIR/patch.log
make  &> $LOGDIR/patch.log
make install  DESTDIR=$ROOTFS &> $LOGDIR/patch.log
cd $WORKING
rm -rf patch-*

echo "Finished building tools"
