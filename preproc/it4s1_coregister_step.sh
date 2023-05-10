#!/bin/bash
mount -a 2>/dev/null
~/mount_cesnet.sh 2>/dev/null
#source ~/mount/S1/BASE/CZ/crop.in
#source ~/cz_s1/db_vars
export PROJECTIT4I=DD-13-5
export IT4S1TMPDIR=/home/laz048/TEMP/cz_s1/temp_coreg
export IT4S1BASEDIR=/home/laz048/mount/S1/BASE/CZ
export IT4S1STORAGE=/scratch/work/user/laz048/.cz_s1
export IT4S1IT4ITMPDIR=/scratch/temp/laz048/.cz_s1
#alias isceserver="ssh root@147.251.253.242"


#(c) 2017 Milan Lazecky, IT4Innovations
# Should be run from IT4I

# This script will get the last processed image in BASE for the given relorb/swath. It will find the next available image in database and coregister to small master
# that is already registered to Big Master and therefore it will be also attached to it.

if [ -z $2 ]; then
 echo "This script will coregister the following (next) or previous (prev) image in the given dataset."
 echo "Usage: "`basename $0`" next/prev RELORB SWATH [oven]"
 echo "  e.g. "`basename $0`" next 175 2 oven"
 exit
fi

step=$1
relorb=$2
SWATH=$3
oven=''
if [ ! -z $4 ]; then
 if [ $4 == 'oven' ]; then oven='oven'; fi
fi

if [ $step == "next" ]; then stepword="last"; grepletter="A";textfun="tail"
 elif [ $step == "prev" ]; then stepword="prev";grepletter="B";textfun="head"
 else echo "Wrong time step. Write 'next' or 'prev'"; exit;
fi

BASEDIR=$IT4S1BASEDIR/$relorb
TEMPDIR=$IT4S1TMPDIR/$relorb; mkdir -p $TEMPDIR 2>/dev/null
IT4IDIRtmp=$IT4S1STORAGE/BASEtmp/$relorb/$SWATH
IT4IDIR=$IT4S1STORAGE/BASE/$relorb/$SWATH

#Get Big Master date
M=`grep master= $IT4IDIR/metadata.txt | cut -d '=' -f2`
#Get the LAST already processed image as a sub-master MS
MS=`grep $stepword= $IT4IDIR/metadata.txt | cut -d '=' -f2`
#Some coregistered files can have one or two bursts less. Let's choose last MS that had same number of bursts as Big Master
MS_FULL=`grep $stepword'_full=' $IT4IDIR/metadata.txt | cut -d '=' -f2`
#Trouble with BASE should not occur. If it does, better not to start processing..
if [ ! `ls $IT4IDIR/*/*/$MS.7z 2>/dev/null | wc -l` -gt 0 ]; then echo "Error. The image "$MS" does not exist in the BASE. Aborting."; exit; fi
if [ ! `ls $IT4IDIR/*/*/$MS_FULL.7z 2>/dev/null | wc -l` -gt 0 ]; then echo "Error. The image "$MS_FULL" does not exist in the BASE. Aborting."; exit; fi

#Get the next-in-line image as slave S
#third parameter is duplicities here:
it4s1_get_dates.sh $relorb $SWATH 0 2>/dev/null
S=`grep $MS -$grepletter 1 selection.dates.sorted.$relorb.$SWATH | $textfun -n1`

if [ `datediff $S` -lt 22 ]; then
 echo "not processing since we do not have precise orbits. though.. this is perhaps not needed"
 echo "anyway cancelling"
 exit
fi

if [ $S == $MS ]; then
 echo "You have reached the end of available dataset. Congratulations, exiting."
 exit
fi

#deal with skipped files
while [[ `grep -c $S $IT4IDIR/skipped.txt 2>/dev/null` -gt 0 ]]; do
 echo "Skipping "$S
 S=`grep $S -$grepletter 1 selection.dates.sorted.$relorb.$SWATH | $textfun -n1`
done
rm selection.dates.sorted.$relorb.$SWATH selection.$relorb.$SWATH

#if the file was already attempted to be processed and it failed (twice), just skip it
if [[ `ls $TEMPDIR/$MS_FULL'_'$S/$SWATH/$relorb'_'$SWATH'_'$S.e* 2>/dev/null | wc -l` -gt 1 ]]; then
 echo "Attempt to process this file has been already performed twice. Skipping, aborting."
 echo "Last error message was:"
 tail -n1 $TEMPDIR/$MS_FULL'_'$S/$SWATH/topsapp.err
 if [ `grep -c $S $IT4IDIR/skipped.txt` -eq 0 ]; then
  echo $S >> $IT4IDIR/skipped.txt
 fi
 exit
fi

echo "I will process pair "$MS_FULL" and "$S" now. Cancel me in 5 seconds"; sleep 5; echo "Ok, let's do it.."
it4s1_coregister.sh $relorb $SWATH $MS_FULL $S $oven

if [ `ls $IT4IDIR/*/*/$S.7z 2>/dev/null | wc -l` -gt 0 ]; then
 echo "Finished"
 sed -i '/'$stepword'=/d' $IT4IDIR/metadata.txt
 echo $stepword"="$S >> $IT4IDIR/metadata.txt
 #if the coregistered date was full, save this information.
 NOB_M=`grep number_of_bursts= $IT4IDIR/metadata.txt | cut -d '=' -f2`
 NOB_S=`ls $IT4IDIRtmp/$S/isce/$S/bu*slc | wc -l`
 if [ ! $NOB_S -lt $NOB_M ]; then
  sed -i '/'$stepword'_full=/d' $IT4IDIR/metadata.txt
  echo $stepword"_full="$S >> $IT4IDIR/metadata.txt
 else
  echo "(this coregistered date "$S" had only "$NOB_S" instead of "$NOB_M" bursts. A previous date "$MS_FULL" will be used for further coregistrations)"
 fi
 cp $IT4IDIR/metadata.txt $BASEDIR/$SWATH/metadata.txt
else
 echo "Some error occurred, sorry"
fi

