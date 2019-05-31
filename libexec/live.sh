cd $ROOTFS

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

echo Preparing temporary system
dpkg-deb -x $OUTPUT/packages/busybox-*.deb $ROOTFS

echo Copying packages to destination
for item in $(cat $DEFDIR/config/live.list) ; do 
	cp -rf $OUTPUT/packages/$item-*.deb $ROOTFS/  ; done
echo Setting up dpkg
mkdir -pv $ROOTFS/var/lib/dpkg/info
touch $ROOTFS/var/lib/dpkg/status

cat > $ROOTFS/install_pkg.sh << EOF
#!/bin/sh
dpkg -i /*.deb
EOF

echo System configuration
mkdir -pv $ROOTFS/etc/
cp -rf $DEFDIR/sysconfig/* $ROOTFS/etc/
echo Replacing sysinit and inittab
rm -rfv $ROOTFS/etc/sysinit
rm -rfv $ROOTFS/etc/inittab

cat > $ROOTFS/etc/sysinit << EOF
#! /bin/ash
echo "BOXLINUX SYSINIT"
date
uname -srm
echo "Configuring kernel logging"
dmesg -n2
echo "Mounting filesystems"
mkdir -p /dev/pts
mount -a
echo "Configuring kernel settings"
sysctl -qp /etc/sysctl.conf
echo "Setting hostname"
hostname -F /etc/hostname
echo "Starting network"
ifup -a &>/dev/null
EOF
chmod -v +x $ROOTFS/etc/sysinit

cat > $ROOTFS/etc/inittab << EOF
# /etc/inittab
# BoxLinux
::sysinit:/etc/sysinit
::askfirst:-/bin/sh
tty2::askfirst:-/bin/sh
tty3::askfirst:-/bin/sh
tty4::askfirst:-/bin/sh
::restart:/sbin/reboot
::ctrlaltdel:/sbin/reboot
::shutdown:/bin/umount -a -r
::shutdown:/sbin/swapoff -a
EOF

echo Installing packages
chroot $ROOTFS /bin/sh /install_pkg.sh
rm -rf $ROOTFS/*.deb
rm -rf $ROOTFS/install_pkg.sh

#echo "Copying kernel to installation media"
#cp -rf $1 $ROOTFS/kernel 

echo "Copying installer to installation media"
cp -rf $DEFDIR/libexec/boxstrap.sh $ROOTFS/sbin/boxstrap
chmod +x $ROOTFS/sbin/boxstrap

echo Packing system configuration
cd $DEFDIR/sysconfig
tar czf $ROOTFS/sysconfig.tgz ./
cd $ROOTFS

echo "Setting installation media default hostname"
echo "boxlinux_live" >> $ROOTFS/etc/hostname
cd $ROOTFS

echo "Doing some adjustments"
# Removing this will break the system!
ln -s sbin/init ./
ln -sf /usr/lib/libc.so lib/ld-musl-x86_64.so.1
chmod -v +x ./etc/sysinit
echo Setting up service logger
chmod -v +x ./etc/service/logger.sh
chmod +x ./etc/service/*/log/run
echo Setting up services
chmod +x ./etc/service/*/run
mkdir -pv $ROOTFS/var/service
chroot $ROOTFS ln -svf /etc/service/01.klogd /var/service
chroot $ROOTFS ln -svf /etc/service/02.syslogd /var/service
chroot $ROOTFS ln -svf /etc/service/03.crond /var/service
chroot $ROOTFS ln -svf /etc/service/09.console /var/service
chroot $ROOTFS ln -svf /etc/service/04.ntpd /var/service

rm -rf tools
rm -rf cross-tools

echo "Packing ramfs"
# Important
mkdir -pv $WORKING
find . | cpio -H newc -o | gzip > $OUTPUT/ramfs-$BUILDID.cpio.gz #  -R root:root 

echo "Copying packages to installation media"
cd $WORKING
mkdir -p iso
cd iso
mkdir -p ./packages
# For all packages in the list except scripts do ...
echo "Processing package list"
cat $CONFIG/$BASELIST.list | grep -v "_script" | grep -v "_patch" >> $WORKING/package.list

for file in $(cat $WORKING/package.list | grep -v "_script" | grep -v "_patch")  
do
	cp -rf $OUTPUT/packages/$file*.deb ./packages ; done ;

cp -rfv $OUTPUT/ramfs-$BUILDID.cpio.gz ./ramfs.cpio.gz
cp -rfv $1 ./kernel
cd $WORKING

echo "Bootloader configuration"
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
