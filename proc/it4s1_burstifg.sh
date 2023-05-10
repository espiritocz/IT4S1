#!/bin/bash

#(c) 2017 Milan Lazecky, IT4Innovations
# Should be run from IT4I

WDIR=`pwd`
mkdir $WDIR/temp 2>/dev/null
TMPDIR=$WDIR/temp

FIDDLEPAR="-M20/4"

if [ -z $5 ]; then
 echo "This script is to generate interferogram from two images in IT4IBASE (only per burst now)."
 echo "Usage: "`basename $0`" MASTER SLAVE relorb SWATH BURSTID [crop?] [OUTDIR] [SMIN SMAX LMIN LMAX]"
 echo "parameters: -coh .... will compute coherence map"
 echo "            -gold ... will perform goldstein filtering (must be with coh!)"
 echo "            -bperp... will include bperp computation"
 echo "            -geo .... will geocode the data to GeoTIFF (without colormap yet)"
 echo "            -unw .... will do unwrapping (in development)"
 echo "            -crop LAT LON RADIUS ... will crop according to WGS84 coordinates (radius in km) "
 echo "  e.g. "`basename $0`" 20160313 20160325 124 1 21660 [1 /home/output/20160313_20160325 100 2000 50 150]"
 exit
fi

bperp=0; coh=0; gold=0; geoloc=0; wgscrop=0; unw=0
while [ "$1" != "" ]; do
    case $1 in
        -bperp )     bperp=1
                                ;;
        -coh )     coh=1
                                ;;
        -gold )    gold=1
                                ;;
        -geo )    geoloc=1
                                ;;
        -unw )    unw=1
                                ;;
        -crop )    wgscrop=1
                   shift
                   wgslat=$1
                   shift
                   wgslon=$1
                   shift
                   cropradius=$1
                                ;;
        * ) break ;;
    esac
    shift
done

M=$1
S=$2
relorb=$3
SWATH=$4
BURSTID=$5
if [ -z $6 ]; then CROP=1; else CROP=$6; fi
if [ ! -z $7 ]; then TMPDIR=$7; fi
if [ -z ${11} ]; then CROP_CUSTOM=0; 
 else CROP_CUSTOM=1;
 SMIN=$8
 SMAX=$9
 LMIN=${10}
 LMAX=${11}
 let samples=$SMAX-$SMIN'+1'
 let lines=$LMAX-$LMIN'+1'
fi

if [ $wgscrop -gt 0 ]; then 
 it4s1_get_coord.sh $relorb $SWATH $BURSTID $wgslat $wgslon $cropradius;
 LMIN=`grep LMIN crop.txt | cut -d '=' -f2`
 LMAX=`grep LMAX crop.txt | cut -d '=' -f2`
 SMIN=`grep SMIN crop.txt | cut -d '=' -f2`
 SMAX=`grep SMAX crop.txt | cut -d '=' -f2`
 samples=`grep samples crop.txt | cut -d '=' -f2`
 lines=`grep lines crop.txt | cut -d '=' -f2`
 rm crop.txt
 CROP=1; CROP_CUSTOM=1
fi

INDIR=$IT4S1STORAGE/$relorb/$SWATH/$BURSTID

if [ ! -f $INDIR/*/$M.7z ]; then echo "Image "$M" does not exist in the BASE. Try coregistration?"`grep LAST $IT4S1STORAGE/$relorb/$SWATH/metadata.txt`; exit; fi
if [ ! -f $INDIR/*/$S.7z ]; then echo "Image "$S" does not exist in the BASE. Try coregistration?"`grep LAST $IT4S1STORAGE/$relorb/$SWATH/metadata.txt`; exit; fi

mkdir -p $TMPDIR
cd $TMPDIR

source $INDIR/metadata.txt #getting valid_lines etc.
SAMPLES=`grep samples $IT4S1STORAGE/$relorb/$SWATH/metadata.txt | cut -d '=' -f2` #need original sample size information
if [ ! -f M ]; then
 echo "decompressing "$M" from IT4I Base"
 7za x $INDIR/*/$M.7z >/dev/null
 mv $M.slc M
fi

if [ ! -f S ]; then
 echo "decompressing "$S" from IT4I Base"
 7za x $INDIR/*/$S.7z >/dev/null
 mv $S.slc S
fi

#cleaning before
rm lon lat 2>/dev/null

if [ $CROP -eq 1 ]; then
  if [ $CROP_CUSTOM -eq 1 ]; then
   echo "Cropping to custom limits"
   mv M M.orig
   mv S S.orig
   cpxfiddle -w $SAMPLES -o float -f cr4 -q normal -p $SMIN -P $SMAX -l $LMIN -L $LMAX M.orig > M 2>/dev/null
   cpxfiddle -w $SAMPLES -o float -f cr4 -q normal -p $SMIN -P $SMAX -l $LMIN -L $LMAX S.orig > S 2>/dev/null
   cpxfiddle -w $SAMPLES -o float -f r4 -q normal -p $SMIN -P $SMAX -l $LMIN -L $LMAX $IT4S1STORAGE/$relorb/$SWATH/$BURSTID/geom/lon > lon 2>/dev/null
   cpxfiddle -w $SAMPLES -o float -f r4 -q normal -p $SMIN -P $SMAX -l $LMIN -L $LMAX $IT4S1STORAGE/$relorb/$SWATH/$BURSTID/geom/lat > lat 2>/dev/null
   SAMPLES=$samples
   LINES=$lines
   FIDDLEPAR="-M5/1"
   rm M.orig S.orig
  else
   echo "Cropping input images for valid area"
   LINES=$valid_lines
   mv M M.orig
   mv S S.orig
   #cpxfiddle -w $SAMPLES -o float -f cr4 -q normal -p $p -P $P -l $l -L $L $INDIR/*/$M.slc > M 2>/dev/null
   #cpxfiddle -w $SAMPLES -o float -f cr4 -q normal -p $p -P $P -l $l -L $L $INDIR/*/$S.slc > S 2>/dev/null
   cpxfiddle -w $SAMPLES -o float -f cr4 -q normal -p $p -P $P -l $l -L $L M.orig > M 2>/dev/null
   cpxfiddle -w $SAMPLES -o float -f cr4 -q normal -p $p -P $P -l $l -L $L S.orig > S 2>/dev/null
   cpxfiddle -w $SAMPLES -o float -f r4 -q normal -p $p -P $P -l $l -L $L $IT4S1STORAGE/$relorb/$SWATH/$BURSTID/geom/lat > lat 2>/dev/null
   cpxfiddle -w $SAMPLES -o float -f r4 -q normal -p $p -P $P -l $l -L $L $IT4S1STORAGE/$relorb/$SWATH/$BURSTID/geom/lon > lon 2>/dev/null
   SAMPLES=$valid_samples
   rm M.orig S.orig
  fi
 else
  echo "Linking from IT4I Base"
  #ln -s $INDIR/*/$M.slc M
  #ln -s $INDIR/*/$S.slc S
  ln -s $IT4S1STORAGE/$relorb/$SWATH/$BURSTID/geom/lat
  ln -s $IT4S1STORAGE/$relorb/$SWATH/$BURSTID/geom/lon
  LINES=`grep lines $IT4S1STORAGE/$relorb/$SWATH/metadata.txt | cut -d '=' -f2`
 fi
cat << EOF > tmp_oct
addpath('$MATLABDIR')
lines=$LINES;
MO=freadbk('M',lines,'cpxfloat32');
SO=freadbk('S',lines,'cpxfloat32');
ifg=MO .* conj(SO);
fwritebk(ifg,'ifg','cpxfloat32');
clear all;
EOF

echo "Processing interferogram"
octave-cli -q tmp_oct 2>/dev/null
cpxfiddle -w $SAMPLES -q phase -o sunraster -c jet $FIDDLEPAR ifg > ifg.ras 2>/dev/null
#cpxfiddle -w $SAMPLES -q mag -o sunraster -c gray -M10/2 ifg > mag.ras 2>/dev/null

if [ $coh -eq 1 ]; then
 echo "Computing coherence (using doris)"
cat << EOF > M.res
Start_process_control
crop:               1
End_process_control
*_Start_crop:
Data_output_file:	M
Data_output_format:     complex_real4
First_line (w.r.t. original_image):             1
Last_line (w.r.t. original_image):	$LINES
First_pixel (w.r.t. original_image):            1
Last_pixel (w.r.t. original_image):  $SAMPLES
Number of lines (non-multilooked):              $LINES
Number of pixels (non-multilooked):             $SAMPLES
* End_crop:_NORMAL
EOF
cat << EOF > S.res
Start_process_control
resample:		1
End_process_control
*_Start_resample:
Data_output_file:	S
Data_output_format:                             complex_real4
First_line (w.r.t. original_image):             1
Last_line (w.r.t. original_image):	$LINES
First_pixel (w.r.t. original_image):            1
Last_pixel (w.r.t. original_image):  $SAMPLES
Number of lines (non-multilooked):              $LINES
Number of pixels (non-multilooked):             $SAMPLES
* End_resample:_NORMAL
EOF
cat << EOF > coh.in
BATCH ON
SCREEN ERROR
PROCESS COHERENCE
LOGFILE temp.dorout
M_RESFILE M.res
S_RESFILE S.res
I_RESFILE doris.out
COH_METHOD     REFPHASE_ONLY
COH_OUT_COH    coh
COH_MULTILOOK   1 1
COH_WINSIZE     2 10
STOP
EOF
doris coh.in >/dev/null 2>/dev/null
cpxfiddle -w $SAMPLES -q normal -o sunraster -c gray -r 0.0/1.0 -f r4 $FIDDLEPAR coh > coh.ras 2>/dev/null
 if [ $gold -eq 1 ]; then
  echo "Filtering using Goldstein filter (by doris)"
cat << EOF > doris2.out
Start_process_control
interfero:              1
coherence:              1
End_process_control
*_Start_interfero:
Data_output_file:                       ifg
Data_output_format:                     complex_real4
First_line (w.r.t. original_master):    1
Last_line (w.r.t. original_master):     $LINES
First_pixel (w.r.t. original_master):   1
Last_pixel (w.r.t. original_master):    $SAMPLES
Multilookfactor_azimuth_direction:	1
Multilookfactor_range_direction:        1
Number of lines (multilooked):          $LINES
Number of pixels (multilooked):         $SAMPLES
* End_interfero:_NORMAL
****
EOF
grep -A15 "Start_coherence" doris.out >> doris2.out
#depending on the size, choose different filter overlap
if [ $LINES -lt 1020 ]; then OVERLAP=15; else OVERLAP=3; fi
cat << EOF > gold.in
BATCH ON
SCREEN ERROR
PROCESS FILTPHASE
LOGFILE temp.dorout
M_RESFILE M.res
S_RESFILE S.res
I_RESFILE doris2.out
PF_METHOD      goldstein
PF_OUT_FILE    ifg_filt
PF_ALPHA       0.85
PF_BLOCKSIZE   32
PF_OVERLAP     $OVERLAP
STOP
EOF
doris gold.in >/dev/null 2>/dev/null
cpxfiddle -w $SAMPLES -q phase -o sunraster -c jet $FIDDLEPAR ifg_filt > ifg_filt.ras 2>/dev/null
 fi
rm M.res S.res coh.in temp.dorout doris.out doris2.out gold.in
else
 if [ $gold -eq 1 ]; then
  echo "Filtering will not be performed without prior coherence computation"
  gold=0
 fi
fi


if [ $unw -eq 1 ]; then
#cpxfiddle -w $SAMPLES -q phase -f cr4 -o float ifg_filt > ifg_filt_pha 2>/dev/null
cat << EOF > snaphu.conf
INFILEFORMAT COMPLEX_DATA
CORRFILEFORMAT FLOAT_DATA
OUTFILEFORMAT FLOAT_DATA
NTILEROW 1
NTILECOL 1
NPROC 1
STATCOSTMODE DEFO
EOF
#have to multilook if first..
cpxfiddle -V -w $SAMPLES -q normal -f r4 -o float -M20/4 coh > coh20 2> coh.log
cpxfiddle -w $SAMPLES -q normal -f cr4 -o float -M20/4 ifg_filt > ifg20 2>/dev/null
cpxfiddle -w $SAMPLES -q normal -f r4 -o float -M20/4 lon > lon20 2>>/dev/null
cpxfiddle -w $SAMPLES -q normal -f r4 -o float -M20/4 lat > lat20 2>>/dev/null
MLSAMPLES=`grep "output pixels" coh.log | rev | gawk {'print $1'} | rev`
MLLINES=`grep "output lines" coh.log | rev | gawk {'print $1'} | rev`
#snaphu2 -c coh -o unw -f snaphu.conf ifg_filt $LINES
snaphu2 -c coh20 -o unw20 -f snaphu.conf ifg20 $MLLINES
#cpxfiddle -w $SAMPLES -q normal -f r4 -o sunraster -c jet $FIDDLEPAR unw > unw.ras 2>/dev/null
cpxfiddle -w $MLSAMPLES -q normal -f r4 -o sunraster -c jet unw20 > unw20.ras 2>/dev/null

#will do geocoding anyway here:
it4s1_georef_ifg.sh unw20 $MLSAMPLES $MLLINES lon20 lat20 1 $M'_'$S.tif 0
#rm snaphu.conf coh.log
fi

if [ $bperp -eq 1 ]; then
 echo "Computing Bperp"
 mkdir bperp; cd bperp
cat << EOF > topsApp.xml
<topsApp>
<component name="topsinsar">
    <property name="Sensor name">SENTINEL1</property>
    <component name="master">
        <property name="output directory">$M</property>
    </component>
    <component name="slave">
        <property name="output directory">$S</property>
    </component>
</component>
</topsApp>
EOF
 ln -s $IT4S1STORAGE/$relorb/$SWATH/isce/$M'.xml' master.xml
 ln -s $IT4S1STORAGE/$relorb/$SWATH/isce/$S'.xml' slave.xml
 topsApp.py topsApp.xml --dostep='computeBaselines' 2>/dev/null | grep Bperp | head -n1 | rev | gawk {'print $1'} | rev > ../bperp.txt 2>/dev/null
 cd ..; rm -r bperp
 echo "Bperp is " `cat bperp.txt` " m"
fi

if [ $geoloc -eq 1 ]; then
 echo "Georeferencing the final interferogram"
 if [ $gold -eq 1 ]; then IFGNAME="ifg_filt"; else IFGNAME="ifg"; fi
 if [ ! -f lon ]; then 
   ln -s $IT4S1STORAGE/$relorb/$SWATH/$BURSTID/geom/lon;
   ln -s $IT4S1STORAGE/$relorb/$SWATH/$BURSTID/geom/lat;
 fi
 it4s1_georef_ifg.sh $IFGNAME $SAMPLES $LINES lon lat 0 $M'_'$S.tif
fi
echo "Cleaning. Done. Check result:"
rm M S tmp_oct lon lat 2>/dev/null
echo gthumb `pwd`/*.ras
