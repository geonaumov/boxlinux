LOGDIR="$DEFDIR/logs"
cd $ROOTFS

set -e
echo -ne '#(1%)\r'
cd $ROOTFS
ln -sfn $ROOTFS/cross-tools /

msg () {
	echo -e "[ \e[33m$( date +%H:%M:%S)\e[39m ] $1"
}

msg "Preparing filesystem"
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

msg "System configuration"
## UDHCPC SCRIPT
mkdir -p $ROOTFS/usr/share/udhcpc
cp -rf examples/udhcp/simple.script $ROOTFS/usr/share/udhcpc/default.script
chmod +x $ROOTFS/usr/share/udhcpc/default.script
cd $WORKING
rm -rf busybox-*

cd $ROOTFS

cp -rf $DEFDIR/config/* $ROOTFS/etc/
chown -R root:root $ROOTFS/etc/

mkdir -p var/service
ln -s /etc/service/01.klogd/ var/service/
ln -s /etc/service/02.syslogd/ var/service/
ln -s /etc/service/03.crond/ var/service/
ln -s /etc/service/04.ntpd/ var/service/

chmod +x etc/service/01.klogd/run
chmod +x etc/service/02.syslogd/run 
chmod +x etc/service/03.crond/run 
chmod +x etc/service/04.ntpd/run

cd $WORKING

cat > $ROOTFS/etc/ld.so.conf << EOF
/usr/lib
/usr/lib64
/usr/local/lib
/usr/local/lib64
EOF

msg "Musl C library"
tar xf $SRC/musl-*
cd musl-*
./configure --prefix=/usr --enable-shared  	\
	--libdir=/usr/lib			\
	--host=$ARCH-box-linux-musl  		\
        --build=$ARCH-box-linux-musl 		\
        --target=$ARCH-box-linux-musl &> $LOGDIR/musl-conf-$ARCH-$BUILDID.log
make &> $LOGDIR/musl-build-$ARCH-$BUILDID.log
make install DESTDIR=$ROOTFS &> $LOGDIR/musl-install-$ARCH-$BUILDID.log
cd $WORKING
rm -rf musl-*

msg "Z compression library"
tar xf $SRC/zlib-*
cd zlib-*
./configure --prefix=/usr --enable-shared &> $LOGDIR/zlib-conf-$ARCH-$BUILDID.log
make &> $LOGDIR/zlib-build-$ARCH-$BUILDID.log
make install DESTDIR=$ROOTFS &> $LOGDIR/zlib-install-$ARCH-$BUILDID.log
cd $WORKING
rm -rf zlib-*

msg "LibreSSL crypto library"
tar xf $SRC/libressl-*
cd libressl-*
./configure --prefix=/usr --enable-shared  	\
	--libdir=/usr/lib			\
	--host=$ARCH-box-linux-musl &> $LOGDIR/libressl-conf-$ARCH-$BUILDID.log
make &> $LOGDIR/libressl-build-$ARCH-$BUILDID.log
make install DESTDIR=$ROOTFS &> $LOGDIR/libressl-install-$ARCH-$BUILDID.log
cd $WORKING
rm -rf libressl-*

msg "OpenSSH client and server"
tar xf $SRC/openssh-*
cd openssh-*
./configure --prefix=/usr --enable-shared --with-md5-passwords  \
	--disable-wtmp --disable-wtmpx --without-pam 		\
	--sysconfdir=/etc/sshd --libdir=/usr/lib 			\
	--host=$ARCH-box-linux-musl --disable-strip &> $LOGDIR/openssh-conf-$ARCH-$BUILDID.log
make &> $LOGDIR/openssh-build-$ARCH-$BUILDID.log
make install DESTDIR=$ROOTFS &> $LOGDIR/openssh-install-$ARCH-$BUILDID.log
cd $WORKING
rm -rf openssh-*

msg "RSync file sync"
tar xf $SRC/rsync-*
cd rsync-*
./configure --prefix=/usr --host=$ARCH-box-linux-musl &> $LOGDIR/rsync-conf-$ARCH-$BUILDID.log
make &> $LOGDIR/rsync-build-$ARCH-$BUILDID.log
make install DESTDIR=$ROOTFS &> $LOGDIR/rsync-install-$ARCH-$BUILDID.log
cd $WORKING
rm -rf rsync-*

msg "Links browser"
tar xf $SRC/links-*
cd links-*
./configure --prefix=/usr --host=$ARCH-box-linux-musl &> $LOGDIR/links-conf-$ARCH-$BUILDID.log
make &> $LOGDIR/links-build-$ARCH-$BUILDID.log
make install DESTDIR=$ROOTFS &> $LOGDIR/links-install-$ARCH-$BUILDID.log
cd $WORKING
rm -rf links-*

msg "Make"
tar xf $SRC/make-*
cd make-*
./configure  --prefix="/usr" --host="$TARGET"  &> $LOGDIR/make-conf-$ARCH-$BUILDID.log
make &> $LOGDIR/make-build-$ARCH-$BUILDID.log
make install  DESTDIR=$ROOTFS &> $LOGDIR/make-install-$ARCH-$BUILDID.log
cd $WORKING
rm -rf make-*

msg "M4"
tar xf $SRC/m4-*
cd m4-*
./configure  --prefix="/usr" --host="$TARGET"  &> $LOGDIR/m4-conf-$ARCH-$BUILDID.log 
make &> $LOGDIR/m4-build-$ARCH-$BUILDID.log
make install  DESTDIR=$ROOTFS &> $LOGDIR/m4-install-$ARCH-$BUILDID.log
cd $WORKING
rm -rf m4-*

msg "Patch"
tar xf $SRC/patch-*
cd patch-*
./configure  --prefix="/tools" --host="$TARGET" &> $LOGDIR/patch-conf-$ARCH-$BUILDID.log
make  &> $LOGDIR/patch-build-$ARCH-$BUILDID.log
make install  DESTDIR=$ROOTFS &> $LOGDIR/patch-install-$ARCH-$BUILDID.log
cd $WORKING
rm -rf patch-*
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
