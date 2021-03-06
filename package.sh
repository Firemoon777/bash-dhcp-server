#!/bin/bash --

PACKAGE=bash-dhcp-server

rm -rf $PACKAGE

mkdir -p $PACKAGE/DEBIAN
mkdir -p $PACKAGE/usr/sbin

cp dhcp.sh $PACKAGE/usr/sbin/$PACKAGE

cat > $PACKAGE/DEBIAN/control <<EOF
Package: $PACKAGE
Version: 1.2
Maintainer: Vladimir Turov
Architecture: all
Description: bash-based dhcp-server
Depends: netcat-openbsd (>= 1.130)
EOF

dpkg-deb --build $PACKAGE && rm -rf $PACKAGE
