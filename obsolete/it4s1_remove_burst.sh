#!/bin/bash
mount -a 2>/dev/null
~/mount_cesnet.sh 2>/dev/null
#source ~/mount/S1/BASE/CZ/crop.in
#source ~/cz_s1/db_vars
export PROJECTIT4I=OPEN-11-37
export IT4S1TMPDIR=/home/laz048/TEMP/cz_s1/temp_coreg
export IT4S1BASEDIR=/home/laz048/mount/S1/BASE/CZ
export IT4S1STORAGE=/scratch/work/user/laz048/.cz_s1
export IT4S1IT4ITMPDIR=/scratch/temp/laz048/.cz_s1
#alias isceserver="ssh root@147.251.253.242"


#(c) 2017 Milan Lazecky, IT4Innovations
# Should be run from IT4I

if [ -z $2 ]; then
 echo "This script will remove given date from the given dataset."
 echo "Usage: "`basename $0`" RELORB SWATH DATE"
 echo "  e.g. "`basename $0`" 175 2 20160101"
 exit
fi

relorb=$1
SWATH=$2
M=$3

BASEDIR=$IT4S1BASEDIR/$relorb
TEMPDIR=$IT4S1TMPDIR/$relorb; mkdir -p $TEMPDIR 2>/dev/null
IT4IDIRtmp=$IT4S1STORAGE/BASEtmp/$relorb/$SWATH
IT4IDIR=$IT4S1STORAGE/BASE/$relorb/$SWATH

cd $IT4IDIR
rm */*/$M.slc
echo $M >>skipped.txt
#sub=`grep master= metadata.txt | cut -d '=' -f2`
#sed -i 's/'$M'/'$sub'/' metadata.txt
