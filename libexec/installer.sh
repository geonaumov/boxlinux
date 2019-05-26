#! /bin/ash
# The BoxLinux installer script.
# Experimental
dmesg -n2
clear
export INSTALLDEST="/mnt/install"
export INSTALLMED="/mnt/installmedia"
export DISK=""
# Unmounting filesystems if required, usually after a failed run
umount $INSTALLDEST &> /dev/null
umount $INSTALLMED &> /dev/null

set -e

msg () {
	echo -e "\033[33m$1\033[00m"
}

list_drives () {
	echo "Available devices and partitions:"
	cat /proc/diskstats | grep -v loop | awk '{ print $3 }'
}

proceed () {
read -r -p "Are you sure? [Y/N] " proceed
case $proceed in 
	[yY])
		continue
		;;
	*)
		echo "Bye bye."
		exit
		;;
esac
}

echo
msg "BOXLINUX INSTALLER"
echo
echo " * Experimental - use at your own risk"
echo " * Backup your data!"
echo
echo "This script will install BoxLinux to a hard-drive of your choice"

proceed

mkdir -p $INSTALLMED
echo "Mounting installation media"
mount $(findfs LABEL=BOXLINUX)  $INSTALLMED
msg "Choose the system disk"
echo "Example: sda or vda"
list_drives
echo "Select a disk, not a partition!"

while [ ! -b /dev/$DISK ]
do
  read -p "Your choice: " DISK
done

echo "The first 100MB of the disk will be zeroed."
echo "Then a new partion will be created and formated as ext4."
echo "All data on disk ${DISK} will be lost! This step is not reversable!"
proceed
msg "Setting up the system disk"
echo "Creating new partition table"
dd if=/dev/zero of=/dev/${DISK} bs=1M count=100 &> /dev/null
sleep 2s
{
fdisk /dev/$DISK <<EOF
n
p
1
+

w
EOF
} &> /dev/null
echo "Formatting system partition"
sleep 2s
mkfs.ext4 -L ROOT /dev/${DISK}1 &> /dev/null
echo "Mounting partition"
sleep 2s
mkdir -p $INSTALLDEST
mount /dev/${DISK}1 $INSTALLDEST
echo "Preparing filesystem"
cd $INSTALLDEST
mkdir -p home
mkdir -p root
mkdir -p proc
mkdir -p sys
mkdir -p dev/pts
mkdir -p tmp
mkdir -p var/db/boxer
mkdir -p var/run
mkdir -p var/spool/cron/crontabs
mkdir -p lib64
mkdir -p etc
mkdir -p var/log/service
chown -R logger:logger var/log
cd 

echo "Installing temporary system"
cd $INSTALLMED/packages
dpkg-deb -x musl-*.deb $INSTALLDEST
dpkg-deb -x busybox-*.deb $INSTALLDEST

mkdir -p $INSTALLDEST/var/lib/dpkg/info
touch $INSTALLDEST/var/lib/dpkg/status
mkdir -p $INSTALLDEST/var/boxer/packages

echo "Copying system packages to destination"
cp -rf *.deb $INSTALLDEST/var/boxer/packages

echo Unpacking default configuration
tar xf /sysconfig.tgz -C $INSTALLDEST/etc/
chown -R root:root $INSTALLDEST/etc/*
chmod -R 0640 $INSTALLDEST/etc

echo "dev/null fix"
mknod $INSTALLDEST/dev/null c 1 3
chmod 666 $INSTALLDEST/dev/null
msg "Performing package installation"
# NOTHING ELSE WORKS!!
cat > $INSTALLDEST/install.sh << EOF
#!/bin/ash
cd /var/boxer/packages
dpkg -i *.deb 
EOF
chmod +x $INSTALLDEST/install.sh
chroot $INSTALLDEST /install.sh
sleep 1s
msg "Finished installing packages. Cleaning up."
rm -rf $INSTALLDEST/install.sh
rm -rf $INSTALLDEST/var/boxer/packages/*.deb
cd

echo "Setting up"
chmod 755 $INSTALLDEST/./
chmod 700 $INSTALLDEST/root
chmod 751 $INSTALLDEST/home
chmod 777 $INSTALLDEST/tmp
chmod 755 $INSTALLDEST/bin
chmod 755 $INSTALLDEST/lib
chmod 755 $INSTALLDEST/usr/bin
chmod 755 $INSTALLDEST/usr/lib
chmod u+x $INSTALLDEST/bin/busybox
chmod u+s $INSTALLDEST/bin/su
chmod +x $INSTALLDEST/etc/service/*/run
chmod +x $INSTALLDEST/etc/service/*/log/run
chmod +x $INSTALLDEST/etc/sysinit
chmod +x $INSTALLDEST/etc/service/logger.sh
chroot $INSTALLDEST mkdir -pv /var/service
chroot $INSTALLDEST ln -sf /etc/service/01.klogd /var/service
chroot $INSTALLDEST ln -sf /etc/service/02.syslogd /var/service
chroot $INSTALLDEST ln -sf /etc/service/03.crond /var/service
chroot $INSTALLDEST ln -sf /etc/service/04.ntpd /var/service
chroot $INSTALLDEST ln -sf /etc/service/11.smtpd /var/service
chroot $INSTALLDEST ln -sf /etc/service/99.console /var/service
chroot $INSTALLDEST ln -sf /var/run /
chroot $INSTALLDEST mkdir -p /var/spool/mail
chroot $INSTALLDEST mkdir -v /var/spool/smtpd
chroot $INSTALLDEST chmod 0711 /var/spool/smtpd

msg "System hostname"
read -p "Hostname: " NEWHOST
echo ${NEWHOST} >> $INSTALLDEST/etc/hostname

msg "Setting superuser password"
until chroot $INSTALLDEST passwd
do
  echo "Try again ..."
done

msg "Installing boot loader and kernel"
mkdir -p $INSTALLDEST/boot
cp -rf $INSTALLMED/kernel $INSTALLDEST/boot/kernel
chown 0:0 $INSTALLDEST/boot/kernel
grub-install /dev/${DISK} --boot-directory=$INSTALLDEST/boot
export GRUBCFG=$INSTALLDEST/boot/grub/grub.cfg
echo "set default=0" >> $GRUBCFG
echo "set timeout=0" >> $GRUBCFG
echo "set menu_color_normal=yellow/black" >> $GRUBCFG
echo "set menu_color_highlight=black/yellow" >> $GRUBCFG
echo "insmod ext2" >> $GRUBCFG
echo "insmod ext3" >> $GRUBCFG
echo "set root=(hd0,1)" >> $GRUBCFG
echo 'menuentry "BoxLinux" {' >> $GRUBCFG
echo "	echo Loading kernel" >> $GRUBCFG
echo "  linux /boot/kernel root=/dev/${DISK}1 splash quiet rw" >> $GRUBCFG 
echo "}" >> $GRUBCFG

cd /
umount $INSTALLDEST
umount $INSTALLMED
msg "Done installing BOXLINUX"
