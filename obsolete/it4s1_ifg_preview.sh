#!/bin/bash
#e.g. isce_preview.sh burst_04.int
if [ ! -e $1 ]; then
 echo "This is for ISCE files preview"
 echo "Usage: "`basename $0`" FILE"
 echo "  e.g. "`basename $0`" burst_04.int"
 exit
fi

FILE=$1
W=`grep rasterXSize $FILE'.vrt' | cut -d '"' -f2`
FILENAME=`echo $FILE | rev | cut -c 5- | rev`
cpxfiddle -w$W -o sunraster -c jet -q phase -f cr4 -M 5/2 $FILE | convert - $FILE'_pha.png'
cpxfiddle -w$W -o sunraster -c gray -q mag -f cr4 -M 5/2 $FILE | convert - $FILE'_mag.png'
