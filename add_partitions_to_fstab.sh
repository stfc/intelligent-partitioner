#!/bin/bash

LABEL_PREFIX='data'

MOUNT_POINT='/export'
MOUNT_OPTS="logbufs=8,logbsize=256k,noatime,swalloc,inode64"

if [ ! -d $MOUNT_POINT ] ; then mkdir $MOUNT_POINT ; fi

for f in $(ls /dev/disk/by-label/${LABEL_PREFIX}*); do
  name=$(echo $f | cut -d '/' -f 5)
  mkdir /$MOUNT_POINT/${name}
  echo "Found partition $f"
  echo "$f     $MOUNT_POINT/$name  xfs  $MOUNT_OPTS  0 2" >> /etc/fstab
done
