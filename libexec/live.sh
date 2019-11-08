cd $WORKING
mkdir -p iso
cd iso

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
