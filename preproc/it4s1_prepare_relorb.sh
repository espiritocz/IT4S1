#!/bin/bash
mount -a 2>/dev/null
~/mount_cesnet.sh 2>/dev/null
##workaround for starting in screen
#module load intel 2>/dev/null
#module add Octave/4.2.1-intel-2017a 2>/dev/null
#source ~/mount/S1/BASE/CZ/crop.in
source ~/cz_s1/db_vars
export PROJECTIT4I=DD-13-5
export IT4S1TMPDIR=/home/laz048/TEMP/cz_s1/temp_coreg
export IT4S1BASEDIR=/home/laz048/mount/S1/BASE/CZ
export IT4S1STORAGEtmp=/scratch/work/user/laz048/.cz_s1/BASEtmp
export IT4S1STORAGE=/scratch/work/user/laz048/.cz_s1/BASE
metahoum=/storage/brno2/home/laz048
#alias isceserver="ssh root@147.251.253.242"


#(c) 2017 Milan Lazecky, IT4Innovations
# Should be run from IT4I

# First script to create a burst database foundations of given relative orbit and IW (because some cover much further areas, not interesting for us)
# I believe in human-based logic, so I want to provide my own specific date to be selected as M
# e.g. it4s1_prepare_relorb.sh 124 2 20160313

if [ -z $2 ]; then
 echo "This script will prepare the whole RELORB dataset of given SWATH with M date used as master"
 echo "Usage: "`basename $0`" RELORB SWATH [M]"
 echo "  e.g. "`basename $0`" 175 2 20160313"
 exit
fi

S=''
relorb=$1
SWATH=$2

if [ -z $3 ]; then 
 echo "Choose yourself a master from the file list:"
 it4s1_get_dates.sh $relorb $SWATH >/dev/null 2>/dev/null
 let maspos=`cat selection.dates.sorted.$relorb.$SWATH | wc -l`/2
 rm selection.$relorb.$SWATH
 echo "See selection.dates.sorted.$relorb.$SWATH"
 echo "(Recommended master is "`head -n $maspos selection.dates.sorted.$relorb.$SWATH | tail -n1`" )"
 exit
else
 M=$3
fi
if [ ! -z $4 ]; then
 S=$4
fi

# Legend
# M - bigmaster - all dates should be coregistered towards him
# MS - local master - last already coregistered date (kept in the memory) that will be used for following date to connect to the M
# S - slave - date to be coregistered. No special abilities "yet" - just should be old enough to have matured orbits
# relorb - relative orbital frame for M and S to happen

# Prepare the database directory and the temp directory
BASEDIR=$IT4S1BASEDIR/$relorb
TEMPDIR=$IT4S1TMPDIR/$relorb
IT4IDIR=$IT4S1STORAGEtmp/$relorb
if [ -d $BASEDIR/$SWATH ]; then echo "This seems already done. Delete first this folder if you want to continue:" $BASEDIR/$SWATH; exit; fi
mkdir -p $BASEDIR/$SWATH
mkdir -p $TEMPDIR
mkdir -p $IT4IDIR/$SWATH/$M
cd $TEMPDIR

#echo "MASTER="$M > $BASEDIR/$SWATH/metadata.txt
#echo "LAST=" >> $BASEDIR/$SWATH/metadata.txt
#mkdir -p $TEMPDIR
#sed -i '/LAST=/d' $BASEDIR/metadata.txt
# This is to prepare the first M-S pair. The generated files will be saved for usage by the other Ss
# So first let's get the proper (following) S date:
it4s1_get_dates.sh $relorb $SWATH 2>/dev/null
if [ -z $S ]; then
 S=`grep $M -A1 selection.dates.sorted.$relorb.$SWATH | tail -n1`
fi
#exploit information about next and prev dates (usage in the end of the script)
NUMOFDATES=`cat selection.dates.sorted.$relorb.$SWATH | wc -l`
maspos=`grep -n $M selection.dates.sorted.$relorb.$SWATH | cut -d ':' -f1`
let NUMOFPREVDATES=$maspos-1
let NUMOFNEXTDATES=$NUMOFDATES-$maspos

rm selection.dates.sorted.$relorb.$SWATH selection.$relorb.$SWATH
mkdir -p $TEMPDIR/$M'_'$S/$SWATH
cd $TEMPDIR/$M'_'$S/$SWATH

# This part will prepare prerequisities for future M-Ss combination, that is mainly topo
echo "Alright, now I will process the first pair of relorb $relorb: $M and $S."
#sed 's/skirit/oven/' `which isceserver` > isceserver_tmp; chmod 777 isceserver_tmp
#./isceserver_tmp "it4s1_ISCE_coregister.sh $M $S $relorb $SWATH" #>/dev/null 2>/dev/null
isceserver "it4s1_ISCE_coregister.sh $M $S $relorb $SWATH" oven #>/dev/null 2>/dev/null
#rm isceserver_tmp

# Waiting to finish the M-S coregistration processing
echo "Waiting now to finish the coregistration processing. It can take at least 30 minutes."
it4s1_wait_for.sh $TEMPDIR/$M'_'$S/$SWATH/finished #$TEMPDIR/$M'_'$S/$SWATH/isce_processing
if [ ! -d fine_coreg ]; then echo "MALFUNCTION! (finished with error)"; cat $TEMPDIR/$M'_'$S/$SWATH/*.err; exit; fi

#Checking if everything is fine
#Size check/correct
mv $S $S.bck; mv fine_coreg $S
it4s1_correct_size.sh $M $S
mv $S fine_coreg; mv $S.bck $S

echo "Ok, let's continue.."

#crop everything to the valid area... maybe not the best solution since Slave valid areas may differ. so keeping the GOW (good old way)


#now prepare the burst IDs
echo "Identifying global burst IDs."
#isceserver "mysql -h $SENT_MYSQL_DB -u $SENT_MYSQL_USER --password=$SENT_MYSQL_PASS --database=$SENT_MYSQL_S1DB -e \"SELECT bid_tanx,centre_lat from bursts where bid_tanx like '$relorb\_IW$SWATH\_%';\" | tail -n+2" > tmp_burstids.txt 2>/dev/null
tmpoutfile=tmp_burstids.txt
tmpqueryfile=tmp_query_burstids
echo "SELECT bid_tanx from bursts where bid_tanx like '"$relorb"_IW"$SWATH"_%%';" > $tmpqueryfile
isceserver_scp $tmpqueryfile SERVER:$metahoum/tmp/.
isceserver "$metahoum/sw/it4s1/it4s1_mysql.sh $metahoum/tmp/$tmpqueryfile $metahoum/tmp/$tmpoutfile"
isceserver_scp SERVER:$metahoum/tmp/$tmpoutfile .
rm $tmpqueryfile

tmpoutfile=tmp_lats.txt
tmpqueryfile=tmp_query_burstids
echo "SELECT centre_lat from bursts where bid_tanx like '"$relorb"_IW"$SWATH"_%%';" > $tmpqueryfile
isceserver_scp $tmpqueryfile SERVER:$metahoum/tmp/.
isceserver "$metahoum/sw/it4s1/it4s1_mysql.sh $metahoum/tmp/$tmpqueryfile $metahoum/tmp/$tmpoutfile"
isceserver_scp SERVER:$metahoum/tmp/$tmpoutfile .
rm $tmpqueryfile

#cat tmp_burstids.txt | gawk {'print $2'} > tmp_compare.txt
mv tmp_lats.txt tmp_compare.txt
for BURSTSLC in `ls fine_coreg/burst*slc`; do
 BURSTNO=`echo $BURSTSLC | rev | cut -d '_' -f1 | rev | cut -d '.' -f1`
 BURLAT=`gdalinfo geom_master/lat_$BURSTNO.rdr.vrt -stats | grep STATISTICS | grep MEAN | cut -d '=' -f2`
cat << EOF > tmp_oct
format long;
A=csvread('tmp_compare.txt');
B=$BURLAT;
tmp=abs(A-B);
[idx idx] = min(tmp);
A(idx)
EOF
 BURSTIDLAT=`octave-cli -q tmp_oct | cut -d '=' -f2 | sed 's/ //g' | cut -c -10`
 numl=`grep -n $BURSTIDLAT tmp_compare.txt | cut -d ':' -f1`
 BURSTID=`head -n $numl tmp_burstids.txt | tail -n1`
 #BURSTID=`grep $BURSTIDLAT tmp_burstids.txt | gawk {'print $1'}`
 echo burst_$BURSTNO=$BURSTID
 echo burst_$BURSTNO=$BURSTID >> burst_to_id.txt
 #it4s1_move_burst_it4i.sh $BURSTSLC $BURSTID
done
#rm tmp_compare.txt tmp_burstids.txt tmp_oct
mkdir -p $IT4S1STORAGE/$relorb/$SWATH
cp burst_to_id.txt $IT4S1STORAGE/$relorb/$SWATH/.
cp tmp_compare.txt $IT4S1STORAGE/$relorb/$SWATH/.

echo "Exporting bursts to IT4I (temporary?) storage"
SAMPLES=`grep rasterXSize $M/burst_01.slc.vrt | cut -d '"' -f2`
mv $S $S.bck
mv fine_coreg $S
BURSTOT=`ls $S/burst*.slc | wc -l`
i=0
for LINE in `cat burst_to_id.txt`; do
 let i=$i+1
 echo "Burst "$i" from "$BURSTOT
 BURSTNO=`echo $LINE | cut -d '=' -f1 | cut -d '_' -f2`
 BURSTID=`echo $LINE | cut -d '=' -f2`
 BURSTIDID=`echo $BURSTID | cut -d '_' -f3`
 #gawk '/burst'`echo $BURSTNO | sed 's/^0//'`'"/ {flag=1;next} /UTC/{flag=0} flag {print}' $M.xml > tmp_gawk_M
 #maybe more proper using fine_coreg xml result?
 gawk '/burst'`echo $BURSTNO | sed 's/^0//'`'"/ {flag=1;next} /UTC/{flag=0} flag {print}' fine_coreg.xml > tmp_gawk
 gawk '/burst'`echo $BURSTNO | sed 's/^0//'`'"/ {flag=1;next} /UTC/{flag=0} flag {print}' master_bottom.xml > tmp_gawk2
 FIRSTVALIDLINE=`grep firstvalidline tmp_gawk -A1 | tail -n1 | cut -d '>' -f2 | cut -d '<' -f1`
 NOVALINES=`grep numberofvalidlines tmp_gawk -A1 | tail -n1 | cut -d '>' -f2 | cut -d '<' -f1`
 #This is to remove also overlapping area.. yes, the last burst will still include it (not a problem?)
 NOOVLINES=`grep numberoflines tmp_gawk2 -A1 | tail -n1 | cut -d '>' -f2 | cut -d '<' -f1`
 if [ `grep -c numberoflines tmp_gawk2` -eq 0 ]; then NOOVLINES=0; fi
 let LASTVALIDLINE=$FIRSTVALIDLINE+$NOVALINES-1-$NOOVLINES
 FIRSTVALIDSAMPLE=`grep firstvalidsample tmp_gawk -A1 | tail -n1 | cut -d '>' -f2 | cut -d '<' -f1`
 NOVASAMPLES=`grep numberofvalidsamples tmp_gawk -A1 | tail -n1 | cut -d '>' -f2 | cut -d '<' -f1`
 let LASTVALIDSAMPLE=$FIRSTVALIDSAMPLE+$NOVASAMPLES-1
 mkdir -p $IT4S1STORAGE/$relorb/$SWATH/$BURSTIDID/geom
 for GEOMFILE in `ls geom_master/*_$BURSTNO.rdr`; do
  #I still may need the whole picture due to image shifts in time series :(
  #cpxfiddle -w $SAMPLES -o float -f r4 -q normal -p $FIRSTVALIDSAMPLE -P $LASTVALIDSAMPLE -l $FIRSTVALIDLINE -L $LASTVALIDLINE $GEOMFILE > $IT4S1STORAGE/$relorb/$SWATH/$BURSTIDID/geom/`basename $GEOMFILE | cut -d '_' -f1` 2>/dev/null
  #cp $GEOMFILE $IT4S1STORAGE/$relorb/$SWATH/$BURSTIDID/geom/`basename $GEOMFILE | cut -d '_' -f1`
  cpxfiddle -w $SAMPLES -o float -f r8 -q normal $GEOMFILE > $IT4S1STORAGE/$relorb/$SWATH/$BURSTIDID/geom/`basename $GEOMFILE | cut -d '_' -f1` 2>/dev/null
 done
 for IMA in $M $S; do
  YEAR=`echo $IMA | cut -c -4`
  mkdir -p $IT4S1STORAGE/$relorb/$SWATH/$BURSTIDID/$YEAR
  #cpxfiddle -w $SAMPLES -o float -f cr4 -q normal -p $FIRSTVALIDSAMPLE -P $LASTVALIDSAMPLE -l $FIRSTVALIDLINE -L $LASTVALIDLINE $IMA/burst_$BURSTNO.slc > $IT4S1STORAGE/$relorb/$SWATH/$BURSTIDID/$YEAR/$IMA.slc 2>/dev/null
  #cp $IMA/burst_$BURSTNO.slc $IT4S1STORAGE/$relorb/$SWATH/$BURSTIDID/$YEAR/$IMA.slc
  cd $IMA
  echo "Compressing "$IMA
  7za a -mx=1 $IT4S1STORAGE/$relorb/$SWATH/$BURSTIDID/$YEAR/$IMA.7z burst_$BURSTNO.slc >/dev/null
  cd - >/dev/null
 done
 echo "valid_samples="$NOVASAMPLES > $IT4S1STORAGE/$relorb/$SWATH/$BURSTIDID/metadata.txt
 echo "valid_lines="`echo $(($NOVALINES-$NOOVLINES))` >> $IT4S1STORAGE/$relorb/$SWATH/$BURSTIDID/metadata.txt
 echo "p="$FIRSTVALIDSAMPLE >> $IT4S1STORAGE/$relorb/$SWATH/$BURSTIDID/metadata.txt
 echo "P="$LASTVALIDSAMPLE >> $IT4S1STORAGE/$relorb/$SWATH/$BURSTIDID/metadata.txt
 echo "l="$FIRSTVALIDLINE >> $IT4S1STORAGE/$relorb/$SWATH/$BURSTIDID/metadata.txt
 echo "L="$LASTVALIDLINE >> $IT4S1STORAGE/$relorb/$SWATH/$BURSTIDID/metadata.txt
done
#Additional information to metadata
echo "samples="$SAMPLES > $IT4S1STORAGE/$relorb/$SWATH/metadata.txt
echo "lines="`grep rasterYSize $M/burst_01.slc.vrt | cut -d '"' -f4` >> $IT4S1STORAGE/$relorb/$SWATH/metadata.txt
echo "master="$M >> $IT4S1STORAGE/$relorb/$SWATH/metadata.txt
echo "last="$S >> $IT4S1STORAGE/$relorb/$SWATH/metadata.txt
echo "last_full="$S >> $IT4S1STORAGE/$relorb/$SWATH/metadata.txt
echo "prev="$M >> $IT4S1STORAGE/$relorb/$SWATH/metadata.txt
echo "prev_full="$M >> $IT4S1STORAGE/$relorb/$SWATH/metadata.txt
echo "number_of_bursts="`cat $IT4S1STORAGE/$relorb/$SWATH/burst_to_id.txt | wc -l` >> $IT4S1STORAGE/$relorb/$SWATH/metadata.txt
echo "pass="`it4s1_get_xmlvalue.sh passdirection $M.xml` >> $IT4S1STORAGE/$relorb/$SWATH/metadata.txt
#echo "rangepixelsize="`it4s1_get_xmlvalue.sh rangepixelsize $M.xml` >> $IT4S1STORAGE/$relorb/$SWATH/metadata.txt
echo "slantrange="`it4s1_get_xmlvalue.sh startingrange $M.xml` >> $IT4S1STORAGE/$relorb/$SWATH/metadata.txt
#get average inc_angle value
gdalinfo -stats geom_master/los_01.rdr.vrt > tmp_inc.txt
INC=`grep STATISTICS_MEAN tmp_inc.txt | head -n1`
HEADING=`grep STATISTICS_MEAN tmp_inc.txt | tail -n1 | cut -d '=' -f2 | cut -c -6`
echo "inc_angle="`echo $INC | cut -d '=' -f2 | cut -c -6` >> $IT4S1STORAGE/$relorb/$SWATH/metadata.txt
echo "heading="`echo 360+$HEADING | bc` >> $IT4S1STORAGE/$relorb/$SWATH/metadata.txt
#source $IT4S1STORAGE/$relorb/$SWATH/$BURSTIDID/metadata.txt
#let pp=($p+$P)/2
#let ll=($l+$L)/2
#cpxfiddle -w $SAMPLES -q normal -f r4 -o ascii -p $pp -P $pp -l $ll -L $ll $IT4S1STORAGE/$relorb/$SWATH/$BURSTIDID/geom/los >
  #sed -i 's/'$BURSTSLC'/'$BURSTID'/' $BURSTSLC'.xml'
  #mv $BURSTSLC.xml $IT4S1STORAGE/$relorb/$SWATH/$IMA
  #mv $BURSTSLC 
 #done

# Move the master stuff and resampled slave isce-ready files to IT4I (temp) BASE
#Correction of parameters for making it transferable
#for XML in `ls $S/*.xml`; do
#  sed -i 's/fine_coreg/'$S'/g' $XML
#done
#echo "I should copy to the BASE here.. VV, VH, PHA"
#echo "but now i will use only cpx file VV+PHA.."

#Preparing isce_temp folder in BASE
mkdir -p $IT4S1STORAGE/$relorb/$SWATH/isce
cp $M.xml $IT4S1STORAGE/$relorb/$SWATH/isce/.
cp -r geom_master $IT4S1STORAGE/$relorb/$SWATH/.

#master2BASEtmp
mkdir -p $IT4IDIR/$SWATH/$M/isce
rm -r geom_master/overlaps
mv $M geom_master $IT4IDIR/$SWATH/$M/isce/.
cp -r PICKLE $IT4IDIR/$SWATH/$M/isce/.
cp $M.xml $IT4IDIR/$SWATH/$M/isce/.

#Saving the slave image
mv $S fine_coreg
it4s1_save_bursts.sh $relorb $SWATH $S
echo "Moving helpfiles to the IT4I BASE"

#slave (submaster)
#mkdir -p $IT4IDIR/$SWATH/$S/isce
#mv $S.xml $S $IT4IDIR/$SWATH/$S/isce/.

#echo "Copying to the slow (but unlimited) CESNET BASE for backup"
#echo ".. not yet. Will 7zip it later."
cp $IT4S1STORAGE/$relorb/$SWATH/metadata.txt $BASEDIR/$SWATH/metadata.txt
#echo "Copying "$M
cp $M.xml $BASEDIR/$SWATH/.
#echo "Copying "$S
#cp -r $S.xml $S $BASEDIR/$SWATH/.

#echo "Preparation done. Now we can proceed coregistrating next image. Please run manually:"
echo "Preparation done. Performing processing of all images in background."
echo "for N in \`seq "$NUMOFNEXTDATES"\`; do it4s1_coregister_step.sh next" $relorb $SWATH"; done" > process_all_$relorb'_'$SWATH'_next.sh'
echo "rm `pwd`/process_all_$relorb'_'$SWATH'_next.sh'" >> process_all_$relorb'_'$SWATH'_next.sh'
echo "for P in \`seq "$NUMOFPREVDATES"\`; do it4s1_coregister_step.sh prev" $relorb $SWATH"; done" > process_all_$relorb'_'$SWATH'_prev.sh'
echo "rm `pwd`/process_all_$relorb'_'$SWATH'_prev.sh'" >> process_all_$relorb'_'$SWATH'_prev.sh'
chmod 777 process_all_$relorb'_'$SWATH'_'*.sh
echo "ok, please run these manually:"
echo ssh login "source ~/IT4S1/bashrc; `pwd`/process_all_$relorb'_'$SWATH'_prev.sh'" #&
echo ./process_all_$relorb'_'$SWATH'_next.sh'
echo "i will run it now, lets hope it will be ok"
ssh login "source ~/IT4S1/bashrc; `pwd`/process_all_$relorb'_'$SWATH'_prev.sh'" &
./process_all_$relorb'_'$SWATH'_next.sh'
