#!/bin/bash
source ~/cz_s1/db_vars
metahoum=/storage/brno2/home/laz048
if [ -f ~/mount/S1/BASE/CZ/crop.in ]; then
 source ~/mount/S1/BASE/CZ/crop.in
else
 echo "Problem with CESNET S1 BASE. But continuing"
 #instead of sourcing crop.in...
 export lon1=13.62
 export lon2=13.63
 export lat1=50.52
 export lat2=50.53
fi

#alias isceserver="ssh root@147.251.253.242"
#instead of sourcing crop.in...
#export lon1=13.62
#export lon2=13.63
#export lat1=50.52
#export lat2=50.53


# This script will create a file of sorted dates existing within selected relative orbit and swath number. Condition is that they should be contained in AOI.
# Output files are selection.txt including full paths to the existing files of given RELORB+IW (with redundancies and just-VH removed) and selection.dates.sorted

if [ -z $2 ]; then
 echo "Usage: "`basename $0`" RELORB IW [remove duplicities?]"
 echo "parameters: -all...... do not limit to CZ crop (find all data)"
 echo "  e.g. "`basename $0`" -all 175 2 [1]"
 exit
fi

#ALL=0;
ALL=1
while [ "$1" != "" ]; do
    case $1 in
        -all )     ALL=1
                        ;;
        * ) break ;;
    esac
    shift
done

RELORB=$1
IW=$2
if [ -z $3 ]; then REMDUP=1; else REMDUP=$3; fi

#if [ $ALL -eq 0 ]; then
# isceserver "mysql -h $SENT_MYSQL_DB -u $SENT_MYSQL_USER --password=$SENT_MYSQL_PASS --database=$SENT_MYSQL_S1DB -e \"SELECT distinct files.abs_path from files inner join files2bursts on files.fid=files2bursts.fid inner join bursts on files2bursts.bid=bursts.bid WHERE files.rel_orb=$RELORB AND files.swath LIKE 'IW\"$IW\"' AND Intersects(GeomFromText('Polygon(($lat1 $lon1, $lat1 $lon2, $lat2 $lon2, $lat2 $lon1, $lat1 $lon1))'), GeomFromText(CONCAT('Polygon((', bursts.corner1_lat, ' ', bursts.corner1_lon, ', ', bursts.corner2_lat, ' ', bursts.corner2_lon, ', ', bursts.corner3_lat, ' ', bursts.corner3_lon, ', ', bursts.corner4_lat, ' ', bursts.corner4_lon, ', ', bursts.corner1_lat, ' ', bursts.corner1_lon, ')) ')));\" | tail -n+2" > selection.$RELORB.$IW
#else
# isceserver "mysql -h $SENT_MYSQL_DB -u $SENT_MYSQL_USER --password=$SENT_MYSQL_PASS --database=$SENT_MYSQL_S1DB -e \"SELECT distinct files.abs_path from files inner join files2bursts on files.fid=files2bursts.fid inner join bursts on files2bursts.bid=bursts.bid WHERE files.rel_orb=$RELORB AND files.swath LIKE 'IW\"$IW\"';\" | tail -n+2" > selection.$RELORB.$IW
#fi
tmpqueryfile=tmp_query.$RELORB.$IW
tmpoutfile=selection.$RELORB.$IW
if [ $ALL -eq 0 ]; then
 echo "SELECT distinct files.name from files inner join files2bursts on files.fid=files2bursts.fid inner join bursts on files2bursts.bid=bursts.bid WHERE files.rel_orb="$RELORB" AND files.swath LIKE 'IW"$IW"' AND Intersects(GeomFromText('Polygon(($lat1 $lon1, $lat1 $lon2, $lat2 $lon2, $lat2 $lon1, $lat1 $lon1))'), GeomFromText(CONCAT('Polygon((', bursts.corner1_lat, ' ', bursts.corner1_lon, ', ', bursts.corner2_lat, ' ', bursts.corner2_lon, ', ', bursts.corner3_lat, ' ', bursts.corner3_lon, ', ', bursts.corner4_lat, ' ', bursts.corner4_lon, ', ', bursts.corner1_lat, ' ', bursts.corner1_lon, ')) ')));" > $tmpqueryfile
 else
 echo "SELECT distinct files.name from files WHERE files.rel_orb=$RELORB AND files.swath = 'IW"$IW"';" > $tmpqueryfile 
fi
isceserver_scp $tmpqueryfile SERVER:$metahoum/tmp/.
isceserver "it4s1_mysql.sh $metahoum/tmp/$tmpqueryfile $metahoum/tmp/$tmpoutfile"
isceserver_scp SERVER:$metahoum/tmp/$tmpoutfile .
rm $tmpqueryfile

ORIGNO=`cat selection.$RELORB.$IW | wc -l`

if [ $ORIGNO -eq 0 ] && [ $ALL -eq 0 ]; then
 echo "No images found. Trying again without the CZ crop limit."
# isceserver "mysql -h $SENT_MYSQL_DB -u $SENT_MYSQL_USER --password=$SENT_MYSQL_PASS --database=$SENT_MYSQL_S1DB -e \"SELECT distinct files.abs_path from files inner join files2bursts on files.fid=files2bursts.fid inner join bursts on files2bursts.bid=bursts.bid WHERE files.rel_orb=$RELORB AND files.swath LIKE 'IW\"$IW\"';\" | tail -n+2" > selection.$RELORB.$IW
tmpqueryfile=tmp_query.$RELORB.$IW
tmpoutfile=selection.$RELORB.$IW
echo "SELECT distinct files.name from files WHERE files.rel_orb=$RELORB AND files.swath = 'IW"$IW"';" > $tmpqueryfile 
isceserver_scp $tmpqueryfile SERVER:$metahoum/tmp/.
isceserver "it4s1_mysql.sh $metahoum/tmp/$tmpqueryfile $metahoum/tmp/$tmpoutfile"
isceserver_scp SERVER:$metahoum/tmp/$tmpoutfile .
rm $tmpqueryfile
 ORIGNO=`cat selection.$RELORB.$IW | wc -l`
fi

#dates of the selection for only dual-pol. files (DV)
cp selection.$RELORB.$IW selavi.$RELORB.$IW
grep SDV selavi.$RELORB.$IW > selection.$RELORB.$IW
#whoops, i may have also SSVs..
grep SSV selavi.$RELORB.$IW >> selection.$RELORB.$IW
rm selavi.$RELORB.$IW
cat selection.$RELORB.$IW | rev | cut -d 'T' -f3 | cut -d '_' -f1 | rev > selection.dates.$RELORB.$IW
sort -u selection.dates.$RELORB.$IW > selection.dates.sorted.$RELORB.$IW
rm selection.dates.$RELORB.$IW

if [ $REMDUP -gt 0 ]; then
#additional: remove duplicite files from selection.txt
echo "removing duplicities - orig no of files: "$ORIGNO
for DATE in `cat selection.dates.sorted.$RELORB.$IW`; do
 #Have to be stricter here... still not perfect (some duplicities may happen if they show a second difference..)
 #grep $DATE selection.txt | rev | cut -d '/' -f1 | cut -d '.' -f2 | cut -c5- | rev > sel.tmp
 grep $DATE selection.$RELORB.$IW | cut -c-31 > sel.tmp
 if [ `uniq -d sel.tmp | wc -l` -gt 0 ]; then
  for DUP in `uniq -d sel.tmp`; do
   #here i select the oldest duplicite files
   #ls -t `grep $DUP selection.$RELORB.$IW` | tail -n +2 > sel.tmp.dup
   grep $DUP selection.$RELORB.$IW | tail -n +2 > sel.tmp.dup
   #for TOREMOVE in `cat sel.tmp.dup | rev | cut -d '/' -f1 | cut -d '.' -f2 | rev`; do
   for TOREMOVE in `cat sel.tmp.dup`; do
    sed -i '/'$TOREMOVE'/d' selection.$RELORB.$IW
   done
  done
 fi
done
rm sel.tmp sel.tmp.dup
fi

NEWNO=`cat selection.$RELORB.$IW | wc -l`

echo $NEWNO" files were selected ("$((ORIGNO-NEWNO))" duplicites were removed)."
