#!/bin/bash
#(c) 2017-2018 Milan Lazecky, IT4Innovations
LIMITKM=80
CLEAN=0
#it should automatically identify if nodes are reserved by PBS
PBS_RESERVED=0
WDIR=`pwd`/output
TEMPWDIR=`pwd`/temp
mkdir $WDIR 2>/dev/null
mkdir -p $TEMPWDIR 2>/dev/null
mkdir $WDIR/qsubs 2>/dev/null
mkdir $WDIR/logs 2>/dev/null
rm $WDIR/qsubs/qsub.list >/dev/null 2>/dev/null
#This script will process all possible combinations of data overlapping given coordinates

if [ -z $4 ]; then
 echo "This script will process all possible combinations of data overlapping given coordinates"
 echo "Usage: "`basename $0`" projname LAT LON RADIUS(in km) [end_date_floreon]"
 echo "  e.g. "`basename $0`" ostravice 49.511058 18.415157 7 [2017-04-01]"
 exit
fi

projname=$1
LAT=$2
LON=$3
radius=$4
floreon_end_date=""
if [ ! -z $5 ]; then
 floreon_end_date=$5
 if [ ! `echo $5 | wc -m` -eq 11 ]; then
  echo "You have specified wrong end_date format. Should be yyyy-mm-dd, e.g. 2017-04-30"
  echo "Your input was: "$5
  exit
 fi
fi

if [ $radius -gt $LIMITKM ]; then echo "This script allows only areas below $LIMITKM km radius. Contact administrator."; exit; fi
if [ $radius -lt 11 ]; then
 echo "Given radius is below 10 km. Using the reserved node to process also using SB algorithm.";
 #echo "(Attention, this script waits for finishing only PS result. Check later if you see SB/MERGED results - should be in extra 30 minutes)"
fi

if [ ! -z $PBS_NODEFILE ]; then
 NODESCOUNT=`cat $PBS_NODEFILE | wc -l`
 #echo "Using "$NODECOUNT" reserved nodes for processing";
 PBS_RESERVED=1;
fi

it4s1_get_bursts.sh $LAT $LON > tmp_bursts
rm $WDIR/qsubs/$projname'.qsub_list' 2>/dev/null
a=0
for linero in `grep ':' tmp_bursts | tail -n+2 | sed 's/ /_/g'`; do
 linero2=`echo $linero | sed 's/_/ /g'`
 imageno=`echo $linero2 | gawk {'print $5'}`
 if [ $imageno -gt 39 ]; then
  relorb=`echo $linero2 | gawk {'print $1'}`
  swath=`echo $linero2 | gawk {'print $2'}`
  burstid=`echo $linero2 | gawk {'print $3'}`
#  if [ ! -d $IT4S1STORAGE/$relorb/$swath/$burstid ]; then
#   echo "Burst ID "$burstid" is not in database yet, skipping."
#  else
   let a=$a+1
   echo "preparing the dataset (copying files from CESNET)"
   it4s1_stamps_prepare.sh $projname $relorb $swath $burstid 
#  echo "source ~/IT4S1/it4s1_variables" >> $WDIR/qsubs/$projname'_'$relorb'_'$swath'_'$burstid'.qsub'
   echo "cd "`pwd` > $WDIR/qsubs/$projname'_'$relorb'_'$swath'_'$burstid'.qsub'
#   echo "module list Octave 2> tmp.del.$projname'_'$relorb'_'$swath'_'$burstid; if [ \`grep -c \"4.2.1\" tmp.del\` -lt 1 ]; then source ~/.bashrc; fi; rm tmp.del.$projname'_'$relorb'_'$swath'_'$burstid" >> $WDIR/qsubs/$projname'_'$relorb'_'$swath'_'$burstid'.qsub'
   echo "it4s1_stamps_ps.sh -crop "$LAT $LON $radius $projname $relorb $swath $burstid >> $WDIR/logs/$projname'.log'
   echo "it4s1_stamps_ps.sh -crop "$LAT $LON $radius $projname $relorb $swath $burstid >> $WDIR/qsubs/$projname'_'$relorb'_'$swath'_'$burstid'.qsub'
   echo "cd "`pwd`"/output" >> $WDIR/qsubs/$projname'_'$relorb'_'$swath'_'$burstid'.qsub'
   echo "it4s1_csv2floreon.sh "$projname'_'$relorb'_'$swath'_'$burstid'_ps.csv' $floreon_end_date >> $WDIR/qsubs/$projname'_'$relorb'_'$swath'_'$burstid'.qsub'
   echo "cd "`pwd`"/temp/"$projname"/"$relorb"_"$swath"_"$burstid"/IN*/CROP" >> $WDIR/qsubs/$projname'_'$relorb'_'$swath'_'$burstid'.qsub'
   echo "it4s1_stamps2kml.sh "$WDIR/$projname'_'$relorb'_'$swath'_'$burstid'_PS.kml' >> $WDIR/qsubs/$projname'_'$relorb'_'$swath'_'$burstid'.qsub'
#   echo "touch $WDIR/done_$projname'_'$a" >> $WDIR/qsubs/$projname'_'$relorb'_'$swath'_'$burstid'.qsub'
   if [ $radius -lt 8 ]; then
    echo "cd "`pwd` >> $WDIR/qsubs/$projname'_'$relorb'_'$swath'_'$burstid'.qsub'
    echo "it4s1_stamps_sb.sh "$projname $relorb $swath $burstid "1" >> $WDIR/qsubs/$projname'_'$relorb'_'$swath'_'$burstid'.qsub'
    echo "it4s1_stamps_sb.sh "$projname $relorb $swath $burstid "1" >> $WDIR/logs/$projname'.log'
    echo "cd "`pwd`"/output" >> $WDIR/qsubs/$projname'_'$relorb'_'$swath'_'$burstid'.qsub'
    echo "it4s1_csv2floreon.sh "$projname'_'$relorb'_'$swath'_'$burstid'_sb.csv' $floreon_end_date >> $WDIR/qsubs/$projname'_'$relorb'_'$swath'_'$burstid'.qsub'
   fi
   if [ $CLEAN -eq 1 ]; then
    echo "cd "`pwd` >> $WDIR/qsubs/$projname'_'$relorb'_'$swath'_'$burstid'.qsub'
    echo "TEMPSIZE=\`du -h temp/$projname/$relorb'_'$swath'_'$burstid | tail -n1 | gawk {'print \$1'} \`" >> $WDIR/qsubs/$projname'_'$relorb'_'$swath'_'$burstid'.qsub'
    #echo 'echo "Cleaning temp dir (size "\$TEMPSIZE ")."'' >> $WDIR/qsubs/$projname'_'$relorb'_'$swath'_'$burstid'.qsub'
    echo "rm -r temp/$projname/$relorb'_'$swath'_'$burstid" >> $WDIR/qsubs/$projname'_'$relorb'_'$swath'_'$burstid'.qsub'
   fi
   #echo "touch $WDIR/done_$projname'_'$a" >> $WDIR/qsubs/$projname'_'$relorb'_'$swath'_'$burstid'.qsub'
   echo $WDIR/qsubs/$projname'_'$relorb'_'$swath'_'$burstid'.qsub' >> $WDIR/qsubs/$projname'.qsub_list'
   chmod 770 $WDIR/qsubs/$projname'_'$relorb'_'$swath'_'$burstid'.qsub'
   if [ $PBS_RESERVED -eq 0 ]; then
    qsub -q qexp $WDIR/qsubs/$projname'_'$relorb'_'$swath'_'$burstid'.qsub' >> $WDIR/qsubs/qsub.list
   fi
  fi
# fi
done

cd $WDIR/..
rm tmp_bursts tmp_list 2>/dev/null
if [ $a -eq 0 ]; then echo "Nothing to process. Exiting"; exit; fi

if [ $PBS_RESERVED -eq 1 ]; then
 #mkdir -p temp/reserved 2>/dev/null
 #mkdir -p output/qsubs 2>/dev/null
 #mkdir -p output/logs 2>/dev/null
 for TASKNO in `seq $a`; do
  if [ $TASKNO -gt $NODESCOUNT ]; then let NODENO=$TASKNO-$NODESCOUNT; else NODENO=$TASKNO; fi
  NODENAME=`head -n$NODENO $PBS_NODEFILE | tail -n1`
  QSUBFILE=`head -n$TASKNO $WDIR/qsubs/$projname'.qsub_list' | tail -n1`
  echo $QSUBFILE >> temp/reserved/$NODENAME
 done
 chmod 770 temp/reserved/*
 echo "Starting "$a" processes on "$NODESCOUNT" reserved nodes:"
 for NODE in `ls temp/reserved`; do
  ssh $NODE `pwd`/temp/reserved/$NODE &> $WDIR/logs/$NODE.log &
 done
 #cleaning?
 #rm -r temp/reserved
fi

echo "In total, "$a" bursts are being processed"
echo "Waiting for the processing to finish. Starting at:"
date
echo "-------------------"
if [ $PBS_RESERVED -eq 0 ]; then
while [ `cat $WDIR/qsubs/qsub.list | wc -l` -gt 0 ]; do
 for qtask in `cat $WDIR/qsubs/qsub.list`; do
  if [ `qstat -x $qtask | tail -n1 | gawk {'print $5'} | grep -c F` -gt 0 ]; then
   sed -i '/'$qtask'/d' $WDIR/qsubs/qsub.list
  fi
 done
 sleep 10
done
else
 echo "Sorry for inconvenience but check it manually.."
 echo "These nodes should be processing now:"
 for NODE in `ls temp/reserved`; do
  echo $NODE
 done
 echo "You should see some csv files in "$WDIR
fi
#for bb in `seq 1 $a`; do
# 
# it4s1_wait_for.sh $WDIR/done_$projname'_'$bb >/dev/null 2>/dev/null
# echo "Finished burst $bb from $a"
#done
echo "Finished at"
date
echo "Check following files: "
ls -lh $WDIR/$projname*csv
rm $WDIR/$projname*vrt
#echo "This is for testing now only. Please remove this folder manually:"
#TEMPSIZE=`du -h $WDIR/../temp/$projname | tail -n1`
#moving qsub logs to output folder
mv $WDIR/../$projname*qsub.* $WDIR/logs/.
rm $WDIR/qsubs/qsub.list
