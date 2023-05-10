#!/bin/bash
#mount -a 2>/dev/null
~/mount_cesnet.sh 2>/dev/null
export IT4S1TMPDIR=/home/laz048/TEMP/cz_s1/temp_coreg
export IT4S1BASEDIR=/home/laz048/mount/S1/BASE/CZ
export IT4S1STORAGEtmp=/scratch/work/user/laz048/.cz_s1/BASEtmp
export IT4S1STORAGE=/scratch/work/user/laz048/.cz_s1/BASE

#(c) 2017 Milan Lazecky, IT4Innovations
# Should be run from IT4I

# This script should fill the (temporary) IT4I burst database and backup bursts to CESNET BASE

if [ -z $3 ]; then
 echo "This script will fill the IT4I and CESNET burst bases by fine_coreg folder (is it deramped??)."
 echo "Usage: "`basename $0`" RELORB SWATH S"
 echo "  e.g. "`basename $0`" 124 1 20160325"
 exit
fi

CLEAN=0

relorb=$1
SWATH=$2
S=$3

if [ -z $4 ]; then CLEAN=$4; fi

if [ ! $CLEAN -eq 0 ] || [ ! $CLEAN -eq 1 ]; then echo "wrong fourth parameter, aborting"; exit; fi
BASEDIR=$IT4S1BASEDIR/$relorb

if [ ! -f $IT4S1STORAGE/$relorb/$SWATH/burst_to_id.txt ]; then echo "Cannot find metadata for this relorb/SWATH. Aborting."; exit; fi
if [ ! -d fine_coreg ]; then echo "Cannot find coregistration results here!!!! Aborting."; exit; fi
if [ ! -f fine_coreg.xml ]; then echo "Critical file fine_coreg.xml not found!!!! Aborting."; exit; fi
if [ ! -f fine_coreg/deramped ]; then echo "The results were not deramped!!!! Aborting."; exit; fi

echo "Exporting bursts to IT4I (temporary?) storage"
source $IT4S1STORAGE/$relorb/$SWATH/metadata.txt
mv $S $S.bck 2>/dev/null
mv fine_coreg $S 2>/dev/null

BURSTOT=`ls $S/burst*.slc | wc -l`
i=0
YEAR=`echo $S | cut -c -4`
for LINE in `cat $IT4S1STORAGE/$relorb/$SWATH/burst_to_id.txt`; do
 BURSTNO=`echo $LINE | cut -d '=' -f1 | cut -d '_' -f2`
 BURSTID=`echo $LINE | cut -d '=' -f2`
 BURSTIDID=`echo $BURSTID | cut -d '_' -f3`
 #source $IT4S1STORAGE/$relorb/$SWATH/$BURSTIDID/metadata.txt
 if [ -f $S/burst_$BURSTNO.slc ]; then
  let i=$i+1
  #echo "Copying burst "$i" from "$BURSTOT
  mkdir -p $IT4S1STORAGE/$relorb/$SWATH/$BURSTIDID/$YEAR
  #cp $S/burst_$BURSTNO.slc $IT4S1STORAGE/$relorb/$SWATH/$BURSTIDID/$YEAR/$S.slc
  echo "Compressing burst "$i" from "$BURSTOT
  cd $S
  mv burst_$BURSTNO.slc $S.slc
  7za a -mx=1 $IT4S1STORAGE/$relorb/$SWATH/$BURSTIDID/$YEAR/$S.7z $S.slc >/dev/null
  #now copy it to the CESNET BASE
  if [ `ls -al $IT4S1STORAGE/$relorb/$SWATH/$BURSTIDID/$YEAR/$S.7z | gawk {'print $5'}` -lt 1000000 ]; then
   echo "this file seems corrupted - please check yourself: "
   ls -ahl $IT4S1STORAGE/$relorb/$SWATH/$BURSTIDID/$YEAR/$S.7z
  else
   if [ ! -d ~/mount/cesnet_base/BASE/CZ ]; then
    echo "something got wrong with CESNET BASE connection, keeping at IT4I"
   else
    echo "moving to CESNET BASE"
    if [ ! -d ~/mount/cesnet_base/BASE/CZ/$relorb/$SWATH/$BURSTIDID/$YEAR ]; then mkdir -p ~/mount/cesnet_base/BASE/CZ/$relorb/$SWATH/$BURSTIDID/$YEAR; fi
    rsync -vzir --size-only $IT4S1STORAGE/$relorb/$SWATH/$BURSTIDID/$YEAR/$S.7z ~/mount/cesnet_base/BASE/CZ/$relorb/$SWATH/$BURSTIDID/$YEAR >/dev/null 2>/dev/null
    if [ ! -f ~/mount/cesnet_base/BASE/CZ/$relorb/$SWATH/$BURSTIDID/$YEAR/$S.7z ]; then
     echo "something got wrong with CESNET BASE connection, keeping at IT4I"
    else
     rm $IT4S1STORAGE/$relorb/$SWATH/$BURSTIDID/$YEAR/$S.7z
    fi
   fi
  fi
  mv $S.slc burst_$BURSTNO.slc
  cd - >/dev/null
 fi
done

# Move the resampled slave isce-ready files to IT4I (temp) BASE
# Correction of parameters for making it transferable
for XML in `ls $S/*.xml`; do
  sed -i 's/fine_coreg/'$S'/g' $XML
done
#echo "I should copy to the BASE here.. VV, VH, PHA"
#echo "but now i will use only cpx file VV+PHA.."
#echo "Copying "$S" to the slow (but unlimited) CESNET BASE for backup."
#echo "..or not. I will not archive it now, I will use 7zip for the whole archive a bit later, using HPC.."
mkdir -p $BASEDIR/$SWATH/$S
cp -r $S.xml $BASEDIR/$SWATH/.
#echo "Compressing "$S
#cd $S
#time for x in `ls *.slc`; do
# zip $BASEDIR/$SWATH/$S/`basename $x .slc`.zip $x; 
# cp $x.* $BASEDIR/$SWATH/$S/.
#done
#cd ..
#mkdir -p $BASEDIR/$SWATH/$S/isce
echo "Moving new isce-ready files to IT4I BASEtmp."
mkdir -p $IT4S1STORAGEtmp/$relorb/$SWATH/$S/isce/$S
#copying fine_coreg xml file instead of original $S.xml - hope will be no problem?
#well... seems working for coregistration but I need original orbits for MT InSAR
sed 's/fine_coreg/'$S'/' fine_coreg.xml > $IT4S1STORAGEtmp/$relorb/$SWATH/$S/isce/fine_coreg.patch
mv $S/* $IT4S1STORAGEtmp/$relorb/$SWATH/$S/isce/$S/.



#correcting $S.xml for different burst numbering
#S=20160325
SX=$S.xml
FX=fine_coreg.xml
#SWATH=1
#DIR=/home/laz048/TEMP/cz_s1/temp_coreg/124/20160325_20160418/1
#cd $DIR
head -n`grep -n '<component name="burst1">' $SX | cut -d ':' -f1` $SX | head -n-1 > XML.intro
echo '<property name="family"><value>TraitSeq</value><doc>Instance family name</doc></property>' > XML.outro
echo '<property name="name">' >> XML.outro
A="<value>["
NUMBURST=`it4s1_get_xmlvalue.sh numberofbursts $SX`
NUMBURSTF=`it4s1_get_xmlvalue.sh numberofbursts $FX`
NUMBURSTM=`grep number_of_bursts= $IT4S1STORAGE/$relorb/$SWATH/metadata.txt | cut -d '=' -f2`
COMMAS=`it4s1_get_xmlvalue.sh commonburststartmaster PICKLE/computeBaselines.xml`
COMSLV=`it4s1_get_xmlvalue.sh commonburststartslave PICKLE/computeBaselines.xml`
let BURDIFF=$COMMAS-$COMSLV
i=0
for burst in `seq $NUMBURST`; do 
 #let burstinmas=$BURDIFF+$burst
 let burstnew=$burst+$BURDIFF
 echo "Transferring "$burst" into "$burstnew
 if [ $burstnew -gt 0 ] && [ ! $burstnew -gt $NUMBURSTM ]; then
  let i=$i+1
  xml sel -t -c "productmanager_name/component/component/component[@name='burst"$burst"']" $SX > burst$i.xml
  sed -i 's/burst'$burst'"/burst'$i'"/' burst$i.xml
  if [ $burstnew -lt 10 ]; then
   if [ $burst -lt 10 ]; then 
    sed -i 's/burst_0'$burst'/burst_0'$burstnew'/' burst$i.xml
   else
    sed -i 's/burst_'$burst'/burst_0'$burstnew'/' burst$i.xml
   fi
  else
   if [ $burst -lt 10 ]; then
    sed -i 's/burst_0'$burst'/burst_'$burstnew'/' burst$i.xml
   else
    sed -i 's/burst_'$burst'/burst_'$burstnew'/' burst$i.xml
   fi
  fi 
  #BN=`xml sel -t -v "productmanager_name/component/component/component[@name='burst"$i"']/property[@name='burstnumber']/value" $FX`
  xml ed -L -O -u "productmanager_name/component/component/component[@name='burst"$i"']/property[@name='burstnumber']/value" -v $burstnew burst$i.xml
  A=$A"'burst"$i"', "
 fi
done
echo "`echo $A | rev | cut -c 2- | rev`"']</value>' >> XML.outro
tail -n+`grep -n "<value>\['burst" $SX | cut -d ':' -f1` $SX | tail -n+2 >> XML.outro
if [ `ls bu*xml | wc -l` -eq  $NUMBURSTF ] && [ `ls bu*xml -l | sort -n | head -n1 | gawk {'print $5'}` -gt 0 ]; then
 cat XML.intro burst*xml XML.outro > $SX.2
 xml ed -L -O -u "productmanager_name/component/property[@name='numberofbursts']" -v $NUMBURSTF $SX.2
 cp $SX.2 $IT4S1STORAGEtmp/$relorb/$SWATH/$S/isce/$S.xml
 else
 echo "Some error occurred during metadata extraction. Using original xml file. Pray for it"
 cp $SX $IT4S1STORAGEtmp/$relorb/$SWATH/$S/isce/$S.xml
fi

#Finally save the xml file also to the BASE
if [ ! -d $IT4S1STORAGE/$relorb/$SWATH/isce ]; then mkdir -p $IT4S1STORAGE/$relorb/$SWATH/isce; fi
cp $IT4S1STORAGEtmp/$relorb/$SWATH/$S/isce/$S.xml $IT4S1STORAGE/$relorb/$SWATH/isce/.
echo "done."

if [ $CLEAN -eq 1 ]; then
 thisdir=`pwd | rev | cut -d '/' -f1 | rev`
 cd ..
 rm -r $thisdir
fi
