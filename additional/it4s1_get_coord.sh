#!/bin/bash
#(c) 2017-2018 Milan Lazecky, IT4Innovations

#This is to find radar coordinates of given WGS84 location, based on lat/lon

if [ -z $6 ]; then
 echo "Usage: "`basename $0`" relorb iw burst LAT LON RADIUS(in km)"
 echo "  e.g. "`basename $0`" 73 3 8008 49.511058 18.415157 7"
 exit
fi

RESS=3
RESL=13

relorb=$1
SWATH=$2
BURST=$3
LAT=$4
LON=$5
RADIUS=$6

if [ ! -z $7 ]; then
 if [ ! -f metadata.txt ]; then
  echo 'seems you are not in INSAR_* folder?';
 else
  source metadata.txt
  lat='lat'
  lon='lon'
 fi
else
 source $IT4S1STORAGE/$relorb/$SWATH/metadata.txt
 lat=$IT4S1STORAGE/$relorb/$SWATH/$BURST/geom/lat
 lon=$IT4S1STORAGE/$relorb/$SWATH/$BURST/geom/lon
fi

#find coordinates
cat << EOF > find_coord.m
mujlat=$LAT;
mujlon=$LON;
radius=$RADIUS;
resS=$RESS;
resL=$RESL;
%first compute coordinate centers
addpath('$MATLABDIR');
len=$lines;
sam=$samples;
lat=freadbk('$lat',len,'float32');
lon=freadbk('$lon',len,'float32');
lat2=lat-mujlat;
lon2=lon-mujlon;
lonlat2=abs(lon2.*lat2);
[L,S]=find(lonlat2 == min(min(lonlat2)))
%now compute coordinates of min and max for the crop
radiusS=round(radius*1000/resS);
radiusL=round(radius*1000/resL);
LMIN=max([1 L-radiusL])
LMAX=min([len L+radiusL])
SMIN=max([1 S-radiusS])
SMAX=min([sam S+radiusS])
samples=SMAX-SMIN+1
lines=LMAX-LMIN+1
EOF

echo "Converting WGS84 crop to radar coordinates (see crop.txt for result)"
octave --eval find_coord -q 2>/dev/null | grep = | sed 's/ //g' > crop.txt
rm find_coord.m
