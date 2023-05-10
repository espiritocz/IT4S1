#!/bin/bash

#(c) 2017 Milan Lazecky, IT4Innovations
# Should be run from IT4I

IT4S1STORAGE=/home/laz048/mount/cesnet_base/BASE/CZ

if [ -z $2 ]; then
 echo "This script is to list available bursts of given relorb and SWATH."
 echo "Usage: "`basename $0`" relorb SWATH [BURST]"
 echo "  e.g. "`basename $0`" 124 1 [21558]"
 exit
fi

relorb=$1
SWATH=$2
#BURSTID=$3
echo $IT4S1STORAGE/$relorb/$SWATH
if [ -z $3 ]; then
  ls $IT4S1STORAGE/$relorb/$SWATH/[0-9]* -d | rev | cut -d '/' -f1 | rev
 else
  #include check for much smaller (bad) images
  #(assuming that the first image in the row is actually coorect..)
  sizefirst=`ls $IT4S1STORAGE/$relorb/$SWATH/$3/20*/20* -al | head -n1 | gawk {'print $5'}`
  let sizehalf=$sizefirst/3
  for image in `ls $IT4S1STORAGE/$relorb/$SWATH/$3/20*/20*`; do
   if [ `ls -al $image | gawk {'print $5'}` -gt $sizehalf ]; then
    echo $image | rev | cut -d '/' -f1 | rev | cut -d '.' -f1
   else
    echo $image >> $IT4S1STORAGE/$relorb/$SWATH/$3/wrong_images.txt
   fi
  done
  #ls $IT4S1STORAGE/$relorb/$SWATH/$3/[0-9]*/20* -d | rev | cut -d '/' -f1 | rev | cut -d '.' -f1
fi
