#!/bin/bash
#credentials to CollGS
#HOST="https://dhr1.cesnet.cz"
#if [ ! -f ~/.netrc ]; then
# 
#fi
#sometimes it does not load
export PATH=$PATH:/storage/brno2/home/laz048/sw/it4s1
#source /home/laz048/sw/it4s1/it4s1_skirit_moduleload
if [ `hostname | cut -d '.' -f1`=='oven' ]; then
 OVEN=1; SLCDIR=/mnt/lazecky/temp/SLC; PREDIR=/mnt/lazecky/temp;
 else
 OVEN=0; SLCDIR=/home/laz048/TEMP/SLC; PREDIR=/home/laz048/TEMP;
fi

houm=/storage/brno2/home/laz048
source $houm/sw/it4s1/it4s1_skirit_moduleload
source $houm/mount/S1/BASE/CZ/crop.in
source $houm/cz_s1/db_vars

#export PROJECTIT4I=DD-13-5

#should be working on Sentineloshka ISCE server
#M=20160313
#relorb=124
#IW=2
#DIR=/home/laz048/TEMP/tmp_isce/iw2

M=$1
relorb=$2
SWATH=$3
DIRIT4I=$4
#should I use nonprecise orbits?
ORBIT=1

#Preliminary preparation
#IT4DIR=/home/laz048/TEMP/cz_s1/temp_coreg/$relorb'/'$M
DIR=$PREDIR/cz_s1/temp_coreg/$relorb'/'$M
if [ -d $DIR ]; then echo "Such directory exists already! I will delete it and do again!"; rm -r $DIR; fi
mkdir -p $DIR
cd $DIR
#Link the existing SRTM DEM files
#for x in `ls ~/mount/S1/BASE/DEM/SRTM*`; do ln -s $x; done
#Prepare the coregistration working file
###whoops... is it needed here? ... maybe i should remove it
#cat << EOF > coreg_$M'_'$S'.xml'
#<?xml version="1.0" encoding="UTF-8"?>
#<topsApp>
#<component name="topsinsar">
#    <property name="Sensor name">SENTINEL1</property>
#    <component name="master">
#        <property name="output directory">$M</property>
#    </component>
#    <component name="slave">
#        <property name="output directory">$S</property>
#    </component>
#    <property name="demFilename">SRTM1_DEM.wgs84</property>
#</component>
#</topsApp>
#EOF

#First stage: preprocess those images
#prepare the working files:

IMA=$M
 echo "SELECT DISTINCT name,abs_path FROM files WHERE rel_orb="$relorb" AND date(acq_date)=$IMA" > query
 it4s1_mysql.sh query $IMA.namelist
 echo "SELECT DISTINCT abs_path FROM files WHERE rel_orb="$relorb" AND date(acq_date)=$IMA" > query
 it4s1_mysql.sh query $IMA.pathlist
 paste -d ',' $IMA.namelist $IMA.pathlist > $IMA.list
 rm $IMA.namelist $IMA.pathlist
 #tail -n+2 $IMA.sql > $IMA.list; rm $IMA.sql
 #have to remove duplicities..

# for DUP in `cat $IMA.list | rev | cut -d '/' -f1 | cut -c10- | rev | sort | uniq -d`; do

 for DUP in `cat $IMA.list | cut -d ',' -f1 | sort | uniq -d`; do
  echo "Identified duplicity for "$DUP". Removing."
  grep $DUP $IMA.list | tail -n1 > sel.tmp.dup
  sed -i '/'$DUP'/d' $IMA.list
  cat sel.tmp.dup >> $IMA.list
#  ls -t `grep $DUP $IMA.list` | tail -n +2 > sel.tmp.dup; 
#  for TOREMOVE in `cat sel.tmp.dup | rev | cut -d '/' -f1 | cut -d '.' -f2 | rev`; do sed -i '/'$TOREMOVE'/d' $IMA.list; done
 done


# do their download or copy, if they are not existing..
  
 AorB=`head -n1 $IMA.list | cut -d ',' -f1 | cut -c 3`
 A='';
 todelete='';
 for x in `cat $IMA.list | cut -d ',' -f2`; do
  if [ -f $x ]; then A=`echo $A"'"$x"'"`; 
   else
   #download it
   if [ `echo $x | grep -c http` -eq 1 ]; then
     B=`grep $x $IMA.list | cut -d ',' -f1`.zip
     it4s1_colgs_down.sh $x $SLCDIR/$B
    else
     B=`basename $x`
     #B=$x
     it4s1_colgs_down.sh $B $SLCDIR
   fi
   A=`echo $A"'"$SLCDIR/$B"'"`
   todelete=$todelete" $SLCDIR/$B"
   fi
 done
 FILES=`echo $A | sed "s/''/','/g"`

 mkdir -p $DIR/pre/$IMA/$SWATH
 cp $IMA.list $DIR/pre/$IMA/$SWATH/.
 cat << EOF > $DIR/pre/$IMA/$SWATH/topsApp_preproc.xml
<?xml version="1.0" encoding="UTF-8"?>
<topsApp>
<component name="topsinsar">
    <property name="Sensor name">SENTINEL1</property>
    <property name="swaths">[$SWATH]</property>
    <component name="master">
        <property name="safe">[$FILES]</property>
        <property name="output directory">$DIR/pre/$IMA/$SWATH</property>
        <property name="orbit directory">/home/laz048/mount/S1/ORBITS/S1$AorB</property>
        <property name="auxiliary data directory">/home/laz048/mount/S1/AUX</property>
        <property name="region of interest">[$lat1,$lat2,$lon1,$lon2]</property>
    </component>
  </component>
</topsApp>
EOF

 mkdir $DIR/$SWATH 2>/dev/null
   cd $DIR/pre/$IMA/$SWATH
   echo "Preprocessing "$IMA""
   MAXATTEMPTS=3
   i=0
  while [ ! -f IW$SWATH/burst_01.slc.vrt ] && [ ! $i == $MAXATTEMPTS ]; do
   let i=$i+1
   time topsApp.py topsApp_preproc.xml --end='preprocess' >tops_preproc.log 2>tops_preproc.err
   #Strange error about "broadcast input array" when trying to merge S1 files, though they are of same IPF..
   if [ `tail -n1 tops_preproc.err | grep -c broadcast` -gt 1 ]; then 
    #I should correct it other way, e.g. by processing image by image and then merging them together, generating $IMA.xml. Now I will only remove the bad burst
	#for B in `ls burst*slc`; do if [ ! -f $B.xml ]; then rm $B; fi
	#... no - actually i will remove it all and cancel this image then
	cd; rm -r $DIR/pre/$IMA/$SWATH
	echo "Strange broadcast input array error at preprocessing. Removing. Should process image by image - not hard to do but.. why.. (problem is for older images only)"
        rm $todelete
	exit
   fi
   
   if [ ! -f IW$SWATH/burst_01.slc.vrt ]; then 
    if [ `grep -c "Number of Bursts after cropping:  1" tops_preproc.log` -gt 0 ]; then
	 #maybe i can repair this error..
	 echo "Problem with only one burst after cropping. Will neglect this file :"
	 BADFILE=`grep "Number of Bursts after cropping:  1" tops_preproc.log -B 4 | head -n1 | awk {'print $2'}`
	 echo $BADFILE
	 sed -i '/'`basename $BADFILE .zip`'/d' $IMA.list
	 A='';for x in `cat $IMA.list | cut -d ',' -f1`; do A=`echo $A"'"$x.zip"'"`; done
	 FILES=`echo $A | sed "s/''/','/g"`
	 xmlstarlet ed -L -u "topsApp/component/component/property[@name='safe']" -v $FILES topsApp_preproc.xml
	 #time topsApp.py topsApp_preproc.xml --end='preprocess' >tops_preproc.log 2>tops_preproc.err
	fi
	if [ `tail -n2 tops_preproc.err | grep -c AUX_CAL` -gt 0 ]; then
	 echo "Problem with AUX file - this has many times happened with IPF 002.36. Now there are IPFs: "
	 grep IPF tops_preproc.log | awk {'print $6'}
	 sed -i '/AUX/d' topsApp_preproc.xml
	fi
	if [ `grep IPF tops_preproc.log | awk {'print $6'} | sort | uniq | wc -l` -gt 1 ]; then
	 echo "Problem with different IPFs.. Well, gemeroic to correct. Later. IPFs here are:"
	 grep IPF tops_preproc.log | awk {'print $6'}
	fi
	if [ `tail -n1 tops_preproc.err | grep -c "No suitable orbit"` -gt 0 ]; then
     echo "No precise orbits are available for this image. This file should not be used."
	 if [ $ORBIT == 1 ]; then 
	  echo "But now let's try:"
	  sed -i '/ORBITS/d' topsApp_preproc.xml
	 fi
	fi
   fi
  done
   if [ ! -f $DIR/pre/$IMA/$SWATH/IW$SWATH/burst_01.slc.vrt ]; then
    echo "Error at ISCE server! File "$IMA" was not preprocessed. Keeping the log files in "$DIR/pre/$IMA/$SWATH;
	echo "Error is: "; tail -n2 tops_preproc.err; rm $todelete; exit;
   fi
   #correct paths in xml files and move to more proper folder:
   mv $DIR/pre/$IMA/$SWATH/IW$SWATH/* $DIR/pre/$IMA/$SWATH/.
   mv $DIR/pre/$IMA/$SWATH/IW$SWATH.xml $DIR/pre/$IMA/$SWATH.xml
   echo $DIR/pre/$IMA/$SWATH | sed 's/\//\\\//g' > tmp.t
   sed -i 's/'`cat tmp.t`'/'$IMA'/g' $DIR/pre/$IMA/$SWATH.xml
   sed -i 's/IW'$SWATH'\///g' $DIR/pre/$IMA/$SWATH.xml
   mv $DIR/pre/$IMA/$SWATH.xml $DIR/$SWATH/$IMA.xml
   mkdir $DIR/$SWATH/$IMA
   cd $DIR/pre/$IMA/$SWATH
   for B in `ls bur*vrt`; do
#echo    gdal_translate -of GS7BG $B `basename $B .vrt`
    gdal_translate -of ENVI -ot CFloat32 $B `basename $B .vrt`
#tady musim opravit vrt soubor..
    sed -i '/SourceProperties/d' $B
    sed -i '/xml version/d' $B
    xmlstarlet ed -L -u 'VRTDataset/VRTRasterBand/SimpleSource/SourceFilename' -v $IMA/`basename $B .vrt` $B
    sed -i '/DstRect/d' $B
    sed -i '/SrcRect/d' $B
    xmlstarlet ed -L -u "/imageFile/property[@name='file_name']/value" -v $IMA/`basename $B .vrt` `basename $B .vrt`.xml
    sed -i '/xml version/d' $B
    mv `basename $B .vrt`* $DIR/$SWATH/$IMA/.
#exit
   done

 #copying preprocessed data to it4i
 echo "Copying to IT4I"
 scp -o IdentitiesOnly=yes -i ~/.ssh/id_rsa -r $DIR/$SWATH/$IMA $DIR/$SWATH/$IMA.xml laz048@salomon.it4i.cz:$DIRIT4I/.
 ssh -o IdentitiesOnly=yes -i ~/.ssh/id_rsa laz048@salomon.it4i.cz "rm $DIRIT4I/isce_processing 2>/dev/null; touch $DIRIT4I/finished"
echo "Cleaning a bit"
cd
rm -r $DIR
rm $todelete 2>/dev/null

echo "Done. Yours CESNETISCE."

