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
 echo "This script will coregister an image in the given dataset, to the Master through SUBMASTER."
 echo "Usage: "`basename $0`" RELORB SWATH SUBMASTER SLAVE [oven]"
 echo "  e.g. "`basename $0`" 175 2 20160101 20160113 oven"
 echo "..... oven parameter is useful only with non-CZ data (ask Milan)"
 exit
fi

relorb=$1
SWATH=$2
MS=$3
S=$4
oven=''
if [ ! -z $5 ]; then
 if [ $5 == 'oven' ]; then oven='oven'; fi
fi
BASEDIR=$IT4S1BASEDIR/$relorb
TEMPDIR=$IT4S1TMPDIR/$relorb; mkdir -p $TEMPDIR 2>/dev/null
IT4IDIRtmp=$IT4S1STORAGE/BASEtmp/$relorb/$SWATH
IT4IDIR=$IT4S1STORAGE/BASE/$relorb/$SWATH

#Get Big Master date
M=`grep master= $IT4IDIR/metadata.txt | cut -d '=' -f2`

#establish the coregistration processing
mkdir -p $TEMPDIR/$MS'_'$S/$SWATH
cd $TEMPDIR/$MS'_'$S/$SWATH
ln -s $IT4IDIR/geom_master 2>/dev/null
cp -r $IT4IDIRtmp/$M/isce/PICKLE .
ln -s $IT4IDIRtmp/$MS/isce/$MS 2>/dev/null
ln -s $IT4IDIRtmp/$MS/isce/$MS.xml 2>/dev/null

#asi tohle tam ma byt??
if [ -f $IT4IDIRtmp/$MS/isce/fine_coreg.patch ]; then
 cp $IT4IDIRtmp/$MS/isce/fine_coreg.patch .
#cp $IT4IDIRtmp/$MS/isce/$MS.xml fine_coreg.patch
 TOREMM=`it4s1_get_xmlvalue.sh file_name fine_coreg.patch | cut -d '/' -f1`
 sed -i 's/value>'$TOREMM'/value>'$MS'/g' fine_coreg.patch
fi
ln -s $MS.xml master.xml 2>/dev/null
ln -s $S.xml slave.xml 2>/dev/null
for x in `ls $IT4S1STORAGE/DEM/SRTM*`; do ln -s $x 2>/dev/null; done
if [ ! -f $MS/burst_03.slc ]; then echo "Whoops, image "$MS" does not exist. what the.."; exit; fi
burstfileS=`ls ../../*_$S/$SWATH/$S/burst_03.slc 2>/dev/null | head -n1`
if [ -f $S/burst_03.slc ]; then
  echo "Using previously preprocessed image "$S". Is it right?"
  rm finished 2>/dev/null
 elif [ ! -z $burstfileS ]; then
  Stempd=`echo $burstfileS | rev | cut -c 14- | rev`
  ln -s $Stempd $S
  ln -s $Stempd.xml $S.xml
  echo "Using previously preprocessed image "$S
 else
  echo "Waiting for Slave preprocessing. Should take some 10 minutes."
  touch isce_processing
  time isceserver "it4s1_ISCE_preprocess.sh $S $relorb $SWATH `pwd`" $oven
  it4s1_wait_for.sh `pwd`/finished #`pwd`/isce_processing
 fi

#Check if we got the data normally. Let's skip this image if it was already wrong here
if [ ! -d $S ] || [ ! -f $S.xml ]; then
 echo "Image "$S" not extracted properly, aborting and skipping the image.";
 echo $S >> $IT4IDIR/skipped.txt
 exit;
fi

#new version of ISCE.. correcting by removing new properties
for xmlfile in slave $S $MS master; do
if [ `grep -c azimuthwindowtype $xmlfile.xml` -gt 0 ]; then
 for a in azimuthwindowcoefficient rangewindowcoefficient azimuthprocessingbandwidth rangeprocessingbandwidth rangewindowtype azimuthwindowtype; do
  xmlstarlet ed -L -d "productmanager_name/component/component/component/property[@name='$a']" $xmlfile.xml
  #somehow slave.xml is not just a link but real file! perhaps python IO?
  #xmlstarlet ed -L -d "productmanager_name/component/component/component/property[@name='$a']" slave.xml
 done
fi
done

#Code to correct images with slightly differing pixels w.r.t. (sub)master
#sometimes it can cause error, so if already tried once, let's just use the original..
#...24-04-2019: yeah, error... will remove it
#if [ ! -d bck ]; then
# it4s1_correct_size.sh $MS $S
#else
# rm -r $S; mv bck/* .; rmdir bck
#fi

#Correct if there are more slave bursts than the master ones
#seems it is not needed here
LASTBURSTMS=`ls $MS/burst*slc | tail -n1 | cut -d '_' -f2 | cut -d '.' -f1`
LASTBURSTS=`ls $S/burst*slc | tail -n1 | cut -d '_' -f2 | cut -d '.' -f1`
if [ $LASTBURSTS -gt $LASTBURSTMS ]; then 
 echo "Warning, slave has more bursts than master. Hope it is not problem?"
# rm $S/burst*$LASTBURSTS*
# sed -i "s/\, 'burst"$LASTBURSTS"'//" $S.xml
# xml ed -L -O -u "productmanager_name/component/property[@name='numberofbursts']/value" -v $LASTBURSTMS $S.xml
# xml ed -L -O -d "productmanager_name/component/component/component[@name='burst"$LASTBURSTS"']" $S.xml
fi

#Prepare the coregistration working file
cat << EOF > coreg_$MS'_'$S'.xml'
<?xml version="1.0" encoding="UTF-8"?>
<topsApp>
<component name="topsinsar">
    <property name="Sensor name">SENTINEL1</property>
    <component name="master">
        <property name="output directory">$MS</property>
    </component>
    <component name="slave">
        <property name="output directory">$S</property>
    </component>
    <property name="demFilename">SRTM1_DEM.wgs84</property>
</component>
</topsApp>
EOF

#Prepare the qsub processing instructions file
cat << EOF > proc_coreg_$MS'_'$S.a.sh
cd `pwd`
date > start_time
topsApp.py --dostep=computeBaselines coreg_$MS'_'$S.xml
#Correction for not common bursts
cp PICKLE/computeBaselines.xml PICKLE/topo.xml
cp PICKLE/computeBaselines PICKLE/topo
#Fine Resample needs that master-based fine_coreg.xml file, so a workaround here..:
if [ -f fine_coreg.patch ]; then
 mv $MS.xml $MS.xml.backup
 cp fine_coreg.patch $MS.xml
fi
#if you have error, then put this line above... but i had problems with sometimes different DEM file size (
topsApp.py --start=subsetoverlaps --end=rangecoreg coreg_$MS'_'$S.xml > topsapp.out 2> topsapp.err
EOF

cat << EOF > proc_coreg_$MS'_'$S.b.sh
cd `pwd`
topsApp.py --dostep=fineoffsets coreg_$MS'_'$S.xml >> topsapp.out 2>> topsapp.err
#will tryit here permanently
#if [ -d bck ]; then
if [ ! $M -eq $MS ]; then
 cp $IT4IDIR/isce/$M.xml .
 mv $MS.xml tmp.$MS
 sed -i 's/'$M'/'$MS'/g' $M.xml
 mv $M.xml $MS.xml
fi
#fi
topsApp.py --dostep=fineresamp coreg_$MS'_'$S.xml >> topsapp.out 2>> topsapp.err
mv tmp.$MS $MS.xml 2>/dev/null
#return the xml file back (in case of reprocessing is needed)
if [ -f fine_coreg.patch ]; then
 mv $MS.xml.backup $MS.xml
fi
# I do not understand why, but it happened twice that processing failed, but succeeded when done another time, without changes
#if [ ! -d fine_coreg ] || [[ ! \`ls fine_coreg/b*slc -l | head -n1 | gawk {'print \$5'}\` -eq \`ls $MS/burst_01.slc -l | gawk {'print \$5'}\` ]]; then
# topsApp.py --start=subsetoverlaps --end=fineresamp coreg_$MS'_'$S.xml > topsapp.out 2> topsapp.err
#fi
if [ -d fine_coreg ] && [ -f fine_coreg.xml ]; then
 it4s1_deramp.sh fine_coreg
 echo "Seems finished.. Moving to the IT4IBASE and CESNETBASE."
 it4s1_save_bursts.sh $relorb $SWATH $S
 echo 1 > finished
 echo 1 > finished_and_copied
fi
date > stop_time
EOF
chmod 777 proc_coreg_$MS'_'$S.a.sh
chmod 777 proc_coreg_$MS'_'$S.b.sh

echo "Processing (this may take around 30 minutes once started)."
if [ `ls $S/burst*slc | wc -l` -gt 25 ]; then Q="qfree"; else Q="qexp"; fi
#qsub -A $PROJECTIT4I -q $Q -N $relorb'_'$SWATH'_'$S ./proc_coreg_$MS'_'$S.sh
PREVJOB=`qsub -q qexp -N $relorb'_'$SWATH'_'$S'a' ./proc_coreg_$MS'_'$S.a.sh`
qsub -q qexp -N $relorb'_'$SWATH'_'$S'b' -W depend=afterany:$PREVJOB ./proc_coreg_$MS'_'$S.b.sh

echo "If something goes wrong here but the processing was finished ok"
echo "then please check no. of bursts - if same, update in metadata.txt as full image:"
echo "nano ~/IT4S1/BASE/CZ/"$relorb"/"$SWATH"/metadata.txt"
echo "and if exists fine_coreg/deramped then just run following command to save to db:"
echo "it4s1_save_bursts.sh "$relorb $SWATH $S
echo "we are in this folder:"`pwd`
it4s1_wait_for.sh `pwd`/finished

#if ESD is wrong, there is nothing much more to do with this file..
if [ `tail -n1 topsapp.err | grep -c ESD` -gt 0 ]; then
 echo "Date "$S" is not coherent at all towards "$MS". Skipping and removing from processing"
 echo $S >> $IT4IDIR/skipped.txt
 exit;
fi;
if [ ! -f finished_and_copied ]; then echo "Something went wrong during coregistration :( Aborting."; exit; fi
#if [ ! -f fine_coreg/deramped ]; then echo "Something went wrong during coregistration :( Aborting."; exit; fi

#echo "Seems finished.. Moving to the IT4IBASE and CESNETBASE."
#it4s1_save_bursts.sh $relorb $SWATH $S

echo "Cleaning"
rm -r geom_master/overlaps
mkdir -p $IT4S1IT4ITMPDIR/$relorb/$SWATH
if [ ! $M -eq $MS ] && [ ! -h $IT4IDIRtmp/$MS ]; then
 mv $IT4IDIRtmp/$MS $IT4S1IT4ITMPDIR/$relorb/$SWATH/.
 ln -s $IT4S1IT4ITMPDIR/$relorb/$SWATH/$MS $IT4IDIRtmp/$MS
fi

touch finished_coreg

