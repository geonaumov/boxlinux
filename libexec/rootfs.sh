LOGDIR="$DEFDIR/logs"
cd $ROOTFS

set -e
echo "Preparing"
echo -ne '#(1%)\r'
cd $ROOTFS
ln -sfn $ROOTFS/cross-tools /

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

echo "Creating directory structure inside rootfs"
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

echo "Creating device nodes"
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

rm -rf $WORKING
mkdir $WORKING
cd $WORKING
echo Building and installing Musl C Library
tar xf $SRC/musl-*
cd musl-*
./configure --prefix=/usr --enable-shared  	\
	--libdir=/usr/lib			\
	--host=$ARCH-box-linux-musl  		\
        --build=$ARCH-box-linux-musl 		\
        --target=$ARCH-box-linux-musl &> $LOGDIR/musl-rootfs-$ARCH-$BUILDID.log
echo Setting up the dynamic loader
cat > $ROOTFS/etc/ld.so.conf << EOF
/usr/lib
/usr/lib64
/usr/local/lib
/usr/local/lib64
EOF
make &> $LOGDIR/musl-rootfs-$ARCH-$BUILDID.log
make install DESTDIR=$ROOTFS &> $LOGDIR/musl-rootfs-$ARCH-$BUILDID.log

rm -rf $WORKING
mkdir $WORKING
cd $WORKING
echo Building and installing Busybox system
tar xf $SRC/busybox-*
cd busybox-*
cp -rvf $DEFDIR/busybox-$ARCH.config .conf
make &> $LOGDIR/busybox-rootfs-$ARCH-$BUILDID.log
make install &> $LOGDIR/busybox-rootfs-$ARCH-$BUILDID.log
cp -rf _install/* $ROOTFS/

echo Setting up udhcpc
## UDHCPC SCRIPT
mkdir -pv $ROOTFS/usr/share/udhcpc
cp -rvf examples/udhcp/simple.script $ROOTFS/usr/share/udhcpc/default.script
chmod +x $ROOTFS/usr/share/udhcpc/default.script
cd $ROOTFS

echo "Default system configuration"
cp -rf $DEFDIR/config/* $ROOTFS/etc/
chown -R root:root $ROOTFS/etc/

echo Setting up dpkg
mkdir -pv $ROOTFS/var/lib/dpkg/info
touch $ROOTFS/var/lib/dpkg/status

echo "Setting default hostname"
echo "boxlinux_live" >> $ROOTFS/etc/hostname

echo "Final adjustments"
ln -s sbin/init ./
chmod +x ./etc/sysinit

rm -rf tools
rm -rf cross-tools

echo "Packing rootfs"
echo "Creating tar file"
tar czf $OUTPUT/rootfs-$ARCH-$BUILDID.tgz ./  
echo "Output file is: $OUTPUT/rootfs-$ARCH-$BUILDID.tgz"

echo "Creating cpio file"
find . | cpio -H newc -o | gzip > $OUTPUT/rootfs-$ARCH-$BUILDID.cpio.gz  
echo "Output file is: $OUTPUT/rootfs-$ARCH-$BUILDID.cpio.gz"
echo

rm -rf $WORKING
mkdir -p $WORKING
cd $WORKING
mkdir -p iso
cd iso

cp -rfv $OUTPUT/rootfs-$ARCH-$BUILDID.cpio.gz ./ramfs.cpio.gz
cp -rfv $1 ./kernel
cd $WORKING

echo "Bootloader configuration"
mkdir -pv iso/boot/grub
cat >  iso/boot/grub/grub.cfg << "EOF"
set timeout=5
set default=0
set menu_color_normal=yellow/black
set menu_color_highlight=black/yellow
menuentry "BoxLinux" {
      set root=(cd)
      echo Loading kernel
      linux /kernel root=/dev/ram0 quiet splash nomodeset
      echo Loading ramfs
      initrd /ramfs.cpio.gz
      boot
}
EOF

echo "Creating ISO image"
	
$GRUBCMD -V BOXLINUX -o $OUTPUT/boxlinux-$ARCH-$BUILDID.iso iso

echo 
echo "Done. Output file is: $OUTPUT/boxlinux-$ARCH-$BUILDID.iso"

