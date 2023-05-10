#!/bin/bash
#(c) 2017-2018 Milan Lazecky, IT4Innovations
IT4S1STORAGE=/home/laz048/mount/cesnet_base/BASE/CZ

source $IT4S1STORAGE/crop.in
#source $IT4S1STORAGE/.db_vars
#alias isceserver="ssh -i /scratch/work/project/dd-18-9/it4s1/.ssh/key_isceserver.old root@147.251.253.242"
alias oc="octave-cli"

# This script will get ID of bursts that contain given two coordinates

if [ -z $2 ]; then
 echo "This script will get ID of bursts that contain given two coordinates."
 echo "Usage: "`basename $0`" lat1 lon1 [lat2 lon2]"
 echo "  e.g. "`basename $0`" 49.907 18.027 [49.848 18.140]"
 exit
fi

lat1=$1
lon1=$2

if [ ! -z $4 ]; then
 lat2=$3
 lon2=$4
else
 lat2=`echo $lat1+0.001 | bc`
 lon2=`echo $lon1+0.001 | bc`
fi

minlat=`python -c "print(min($lat1,$lat2))"`
maxlat=`python -c "print(max($lat1,$lat2))"`
minlon=`python -c "print(min($lon1,$lon2))"`
maxlon=`python -c "print(max($lon1,$lon2))"`

#2019: workaround 2..
tmpoutfile=tmp_`pwd | rev | cut -d '/' -f1 | rev`
tmpqueryfile=tmp_query_`pwd | rev | cut -d '/' -f1 | rev`

echo "SELECT bid_tanx from bursts where least(corner1_lat,corner2_lat,corner3_lat,corner4_lat) < '$maxlat' and greatest(corner1_lat,corner2_lat,corner3_lat,corner4_lat) > '$minlat' and least(corner1_lon,corner2_lon,corner3_lon,corner4_lon) < '$maxlon' and greatest(corner1_lon,corner2_lon,corner3_lon,corner4_lon) > '$minlon';" > $tmpqueryfile

isceserver_scp $tmpqueryfile SERVER:/storage/brno2/home/laz048/tmp/. 2>/dev/null
isceserver "/storage/brno2/home/laz048/sw/it4s1/it4s1_mysql.sh /storage/brno2/home/laz048/tmp/$tmpqueryfile /storage/brno2/home/laz048/tmp/$tmpoutfile"
isceserver_scp SERVER:/storage/brno2/home/laz048/tmp/$tmpoutfile . 2>/dev/null
rm $tmpqueryfile


echo "relorb  swath  burstid  :  imageno"
echo "----------------------------------"
for x in `cat $tmpoutfile`; do
 T=`echo $x | cut -d '_' -f1`
 S=`echo $x | cut -d '_' -f2 | cut -d 'W' -f2`
 B=`echo $x | cut -d '_' -f3`
 NUM=`it4s1_list_burst.sh $T $S $B 2>/dev/null | wc -l`
 if [ $NUM -eq 1 ]; then NUM=0;fi

 #remove illegal (old) relorb numbering
 case $T in
    53|148|24|170) T=$T;;
    *)           echo $T $S $B " : " $NUM
                 ;;
 esac

done
