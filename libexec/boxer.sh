#! /tools/bin/ash
set -e 

# Important
/tools/bin/ln -s /tools/lib/libc.so /lib/ld-musl-x86_64.so.1

export LANGUAGE=C
export LC_ALL=C
export LANG=C
export PATH="/bin:/sbin:/usr/bin:/usr/sbin:/tools/bin:/tools/sbin"

# DEFAULT BOXLINUX COMPILE OPTIONS
export OPTIONS="--prefix=/usr --build=$TARGET --host=$TARGET --libdir=/usr/lib --sysconfdir=/etc"
export ALTOPTS="--prefix=/usr --libdir=/usr/lib "
export PKGDIR="/packages"
export LOGDIR="/logs"
export WORKING="/working"
export DEBTEMP="/staging"
export SRC="/src"
export INSTALLDIR="/tmp/install"

# User variables
export MAKEFLAGS=-j$(nproc)

# Directories to strip
stripdir="/bin
/sbin
/usr/bin
/usr/sbin
/lib
/usr/lib
"

## For dpkg
mkdir -p /var/lib/dpkg/info/
mkdir -p /var/lib/dpkg/updates/
mkdir -p /var/lib/dpkg/triggers/
touch /var/lib/dpkg/status

mkdir -p $WORKING
mkdir -p $PKGDIR
mkdir -p $LOGDIR

pkg_create () {
	cd $INSTALLDIR
	TEMPLATE="$PKGNAME-$BUILDID-$TAG"
	if [ -d ./lib64 ]; then
		echo "Error: lib64 directory detected!"
		echo "Make sure you use only /lib, exit"
		exit
	fi
	if [ -d ./usr/lib64 ]; then
		echo "Error: usr/lib64 directory detected!"
	        echo "Make sure you use only /usr/lib, exit"
		exit
	fi
	rm -rfv usr/share/man
	rm -rfv usr/share/doc 
	rm -rfv usr/share/gtk-doc
	mkdir -pv $INSTALLDIR/usr/src/boxlinux/boxbuild
	cp -rvf /boxbuild/$PKGNAME.boxbuild $INSTALLDIR/usr/src/boxlinux/boxbuild/
	
	for dir in $stripdir ; 
	do
		if [ -d $INSTALLDIR/$dir ]; then
			echo "Stripping $dir"
			find $INSTALLDIR/$dir -type f \
				-exec strip --strip-debug '{}' ';'
		fi
	done

	echo "Creating data archive"
	tar zcf $DEBTEMP/data.tar.gz ./
	echo "Creating control file"
	controlfile=$DEBTEMP/DEBIAN/control
	echo "Package: $PKGNAME" >> $controlfile
	echo "Version: $VERSION" >> $controlfile
	echo "Maintainer: $MAINTAINER" >> $controlfile
	echo "Section: $TAG" >> $controlfile
	echo "Architecture: $ARCH" >> $controlfile
	echo "Description: Under development" >> $controlfile
	echo "Source: $SOURCE" >> $controlfile
	echo "Homepage: $URL"  >> $controlfile
	# Empty deps variable will break dpkg
	# The if command returns a very weird error in the log
	# The deps variable must be "none", if empty
	if [ $DEPS == "none" ] ; then
		echo "No package dependencies"
	else
		echo "Dependencies are: $DEPS"
		echo "Depends: $DEPS" >> $controlfile
	fi
	if [ $CONFLICTS == "" -o $CONFLICTS == "none" ] ; then
		echo "No package conflicts"
	else
		echo "Conflicts are: $CONFLICTS"
		echo "Conflicts: $CONFLICTS" >> $controlfile
	fi
	echo "Checking for scripts"
	if [ -f $DEBTEMP/DEBIAN/postinst ]; then
	    echo "Post-installation script detected" 
	    chmod -v +x $DEBTEMP/DEBIAN/postinst
	fi
	
	if [ -f $DEBTEMP/DEBIAN/prerm ]; then
	    echo "Pre-removal script detected" 
	    chmod -v +x $DEBTEMP/DEBIAN/prerm
	fi
	
	echo "Creating control archive"
	cd $DEBTEMP/DEBIAN/
	tar zcf $DEBTEMP/control.tar.gz ./
	echo "Creating debian-binary file"
	cd $DEBTEMP
	echo 2.0 > debian-binary
	echo "Creating deb package"
	ar r $PKGDIR/$TEMPLATE.deb debian-binary control.tar.gz data.tar.gz
}

echo "BOXER PACKAGE BUILDER" 
echo
currentnum=0
totalnum=$(wc -l /current.list | cut -d " " -f1)
for pkg in $(cat /current.list) ; do
	unset PKGNAME
	unset VERSION
	unset TAG
        unset SOURCE
        unset URL
        unset DEPS
	if [ ! -f $PKGDIR/$pkg-*.deb ]; then
		currentnum=$((currentnum+1))
		echo "[ ${currentnum}/${totalnum} ] Building $pkg" 
		mkdir -p $DEBTEMP/DEBIAN
		mkdir -p $INSTALLDIR
		mkdir -p $LOGDIR/packages/$pkg
		cd $WORKING
		source /boxbuild/$pkg.boxbuild &> $LOGDIR/packages/$pkg/$pkg-build-$BUILDID.log
		cd $WORKING
		if [ ! -z "$(ls -A $INSTALLDIR)" ]; then
		    pkg_create &> $LOGDIR/packages/$pkg/$pkg-dpkg-$BUILDID.log
		    # Install and then update to test pre-remove and post install scripts
		    dpkg -i $PKGDIR/$TEMPLATE.deb &> $LOGDIR/packages/$pkg/$pkg-dpkg-$BUILDID.log
		    dpkg -i $PKGDIR/$TEMPLATE.deb &> $LOGDIR/packages/$pkg/$pkg-dpkg-$BUILDID.log
		fi
		rm -rf $INSTALLDIR/*
		rm -rf $DEBTEMP/*
		rm -rf $WORKING/*
		echo
		else
		currentnum=$((currentnum+1))
		echo "[ ${currentnum}/${totalnum} ] Installing $pkg"
		# Install once, scripts are already tested
		dpkg -i $PKGDIR/$pkg-*.deb
		echo	
	fi
done

echo "Finished building packages. Exiting chroot"
