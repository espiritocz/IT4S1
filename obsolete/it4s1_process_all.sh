#!/bin/bash
#(c) 2017-2018 Milan Lazecky, IT4Innovations

IT4S1STORAGE=/home/laz048/DATA/.cz_s1/BASE
WDIR=/home/laz048/TEMP/cz_s1/stamps

#This script will process all possible combinations of data overlapping given coordinates

if [ -z $4 ]; then
 echo "This script will process all possible combinations of data overlapping given coordinates"
 echo "Usage: "`basename $0`" projname LAT LON RADIUS(in km)"
 echo "  e.g. "`basename $0`" ostravice 49.511058 18.415157 7"
 exit
fi

projname=$1
LAT=$2
LON=$3
radius=$4

it4s1_get_bursts.sh $LAT $LON > tmp_bursts
a=0
for linero in `grep ':' tmp_bursts | tail -n+2 | sed 's/ /_/g'`; do
 linero2=`echo $linero | sed 's/_/ /g'`
 imageno=`echo $linero2 | gawk {'print $5'}`
 if [ $imageno -gt 50 ]; then
  let a=$a+1
  relorb=`echo $linero2 | gawk {'print $1'}`
  swath=`echo $linero2 | gawk {'print $2'}`
  burstid=`echo $linero2 | gawk {'print $3'}`
  echo "it4s1_stamps_ps_burst.sh -crop "$LAT $LON $radius $projname $relorb $swath $burstid >> $WDIR/logs/$projname'.log'
  echo "it4s1_stamps_ps_burst.sh -crop "$LAT $LON $radius $projname $relorb $swath $burstid > $WDIR/qsubs/$projname'_'$relorb'_'$swath'_'$burstid'.qsub'
  if [ $radius -lt 8 ]; then
   echo "it4s1_stamps_sb_burst.sh "$projname $relorb $swath $burstid " 1" >> $WDIR/qsubs/$projname'_'$relorb'_'$swath'_'$burstid'.qsub'
  fi
  chmod 777 $WDIR/qsubs/$projname'_'$relorb'_'$swath'_'$burstid'.qsub'
  qsub -q qexp $WDIR/qsubs/$projname'_'$relorb'_'$swath'_'$burstid'.qsub'
 fi
done

echo "In total, "$a" bursts are being processed"
echo "Check following folder after ~1 hour: " $WDIR/$projname

rm tmp_bursts

