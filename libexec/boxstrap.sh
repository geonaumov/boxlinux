#! /bin/sh
# The BoxLinux bootstrapper script.
# Experimental
dmesg -n2

msg () {
	echo -e "\033[33m$1\033[00m"
}

heading () {
	echo
	msg "BOXLINUX INSTALLER"
}

if [ $# -eq 0 ]; then
	heading
	echo "Type 'boxstrap -h' for more information."  
	exit 1
fi

case $1 in 
  -h|-help|--help|help) 
	heading
	echo "Experimental - use at your own risk! Backup important data."
	echo
	echo "Boxstrap will not partition or foramt your storage!"
	echo "Create a partition on the first drive, format it with ext4 filesytem"
	echo "and mount it somewhere. Mount the installation media in another directory."
	echo
	echo "Then run boxstrap like below:"
	echo "   boxstrap /destination/directory /media/directory"
	echo
	echo "Also it's a good idea to note the first drive name."
	echo "You will be asked for grub MBR installation."
	echo "For now, only booting from the first drive is supported."
	echo
	exit
  ;;

  *)
	echo "Continue"
	continue
  ;;
esac 

echo
heading
echo

export INSTALLDEST=$(realpath $1)
export INSTALLMED=$(realpath $2)
echo "Installation destination:   $INSTALLDEST"
echo "Installation source:        $INSTALLMED"
echo

if [ ! -d $INSTALLDEST ]; then
	echo "The installation directory is missing"
	echo "or it is not accessable!"
	echo "Double-check and try again!"
	exit
fi

if [ ! -z "$(ls -A $INSTALLDEST | grep -v 'lost+found')" ]; then
	echo "Your installation directory is not empty!"
	echo "Update procedure is not supported yet."
	echo "Double-check and try again!"
	exit
fi

if [ ! -d $INSTALLDEST ]; then
	echo "The installation media directory is missing"
	echo "or it is not accessable!"
	echo "Double-check and try again!"
	exit
fi

if mountpoint -q $INSTALLDEST ;
then
	continue
else
	echo "Error!"
	echo "The chosen directory is not a mountpoint!"
	echo "Format a disk, create an ext4 partition on it,"
	echo "and mount that partition to a location of your choice."
	echo "Pass the mount directory as an argument to this script."
	exit
fi  

if [ -d $INSTALLMED/packages ]; 
then 
	continue
else
	echo "Packages missing from installation media!"
	echo "Double check and try again."
	exit
fi

if [ -f $INSTALLMED/kernel ]; then
	continue
else
	echo "Kernel missing from installation media!"
	echo "Double check and try again."
	exit
fi
echo
echo "Last warning!"
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

echo "Preparing filesystem"
cd $INSTALLDEST
mkdir -p home
mkdir -p root
mkdir -p proc
mkdir -p sys
mkdir -p bin
mkdir -p root
mkdir -p home
mkdir -p sys
mkdir -p dev/pts
mkdir -p tmp
mkdir -p var/db/boxer
mkdir -p var/run
mkdir -p var/spool/cron/crontabs
mkdir -p lib
mkdir -p etc
mkdir -p var/log/service
chown -R logger:logger var/log
mknod dev/null c 1 3
chmod 666 dev/null
chmod 755 ./
chmod 700 root
chmod 751 home
chmod 777 tmp
chmod 755 bin
chmod 755 lib
cd 

echo "Installing temporary system"
cd $INSTALLMED/packages
dpkg-deb -x musl-*.deb $INSTALLDEST
dpkg-deb -x busybox-*.deb $INSTALLDEST

mkdir -p $INSTALLDEST/var/lib/dpkg/info
touch $INSTALLDEST/var/lib/dpkg/status
mkdir -p $INSTALLDEST/var/boxer/packages

echo "Copying system packages to destination"
cp -rf *system.deb $INSTALLDEST/var/boxer/packages

read -r -p "Install developement environment? [Y/N] " install_dev
case $install_dev in 
	[yY])
		echo "Copying development packages to destination"
		cp -rf *devel.deb $INSTALLDEST/var/boxer/packages
		;;
	*)
		echo "Skipping"
		continue
		;;
esac

echo Unpacking default configuration
tar xf /sysconfig.tgz -C $INSTALLDEST/etc/
chown -R root:root $INSTALLDEST/etc/*
chmod -R 0640 $INSTALLDEST/etc

msg "Performing package installation"
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
chroot $INSTALLDEST mkdir -pv /var/spool/smtpd
chroot $INSTALLDEST chmod 0711 /var/spool/smtpd

msg "System hostname"
read -p "Hostname: " NEWHOST
echo ${NEWHOST} >> $INSTALLDEST/etc/hostname

msg "Setting superuser password"
until chroot $INSTALLDEST passwd
do
	echo "Try again ..."
done

msg "Installing kernel"
mkdir -p $INSTALLDEST/boot
cp -rf $INSTALLMED/kernel $INSTALLDEST/boot/kernel
chown 0:0 $INSTALLDEST/boot/kernel

read -r -p "Install bootloader? [Y/N] " install_bootloader
case $install_bootloader in 
	[yY])
		msg "Choose a disk (not a partititon)"
		echo "Available devices:"
		# Print all disks, exclude loop, print column 3 (device name), exclude partitions (ending with a number)  :)
		cat /proc/diskstats | grep -v loop | awk '{ print $3 }' | sed '/[0-9]/d'
		while [ ! -b /dev/$DISK ]
		do
		  read -p "Your choice: " DISK
		done
		grub-install /dev/${DISK} --boot-directory=$INSTALLDEST/boot
		SYSDEV=$(mountpoint -n $INSTALLDEST | cut -d' ' -f1)
		echo "System device name is: $SYSDEV"
		export GRUBCFG=$INSTALLDEST/boot/grub/grub.cfg
		echo "set default=0" >> $GRUBCFG
		echo "set timeout=0" >> $GRUBCFG
		echo "set menu_color_normal=cyan/magenta" >> $GRUBCFG
		echo "set menu_color_highlight=magenta/cyan" >> $GRUBCFG
		echo "insmod ext2" >> $GRUBCFG
		echo "insmod ext3" >> $GRUBCFG
		echo "set root=(hd0,1)" >> $GRUBCFG
		echo 'menuentry "BoxLinux" {' >> $GRUBCFG
		echo "  echo Loading kernel" >> $GRUBCFG
		# LAST PROBLEM, DEVICE NAME IS NOT GENERATED PROPERLY, USE A VAR
		echo "  linux /boot/kernel root=$SYSDEV splash quiet rw" >> $GRUBCFG 
		echo "}" >> $GRUBCFG
		;;
	*)
		echo "Skipping"
		continue
		;;
esac

cd /
umount $INSTALLDEST
umount $INSTALLMED

msg "Done installing BOXLINUX"