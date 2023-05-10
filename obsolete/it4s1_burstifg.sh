#!/bin/bash

#(c) 2017 Milan Lazecky, IT4Innovations
# Should be run from IT4I

export IT4S1STORAGE=/scratch/work/user/laz048/.cz_s1/BASE
#export IT4S1BASEDIR=/home/laz048/mount/S1/BASE/CZ
FIDDLEPAR="-M20/4"

if [ -z $5 ]; then
 echo "This script is to generate interferogram from two images in IT4IBASE (only per burst now)."
 echo "Usage: "`basename $0`" MASTER SLAVE relorb SWATH BURSTID [crop?] [OUTDIR] [SMIN SMAX LMIN LMAX]"
 echo "parameters: -coh .... will compute coherence map"
 echo "            -gold ... will perform goldstein filtering (must be with coh!)"
 echo "  e.g. "`basename $0`" 20160313 20160325 124 1 21660 [1 /home/output.ras 100 2000 50 150]"
 exit
fi

coh=0; gold=0
while [ "$1" != "" ]; do
    case $1 in
        -coh )     coh=1
                                ;;
        -gold )    gold=1
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
if [ -z $7 ]; then TMPDIR=/home/laz048/TEMP/cz_s1/temp_ifg/$relorb/$SWATH/$BURSTID/$M'_'$S; else TMPDIR=$7; fi
if [ -z ${11} ]; then CROP_CUSTOM=0; else CROP_CUSTOM=1; fi

INDIR=$IT4S1STORAGE/$relorb/$SWATH/$BURSTID

if [ ! -f $INDIR/*/$M.slc ]; then echo "Image "$M" does not exist in the BASE. Try coregistration?"`grep LAST $IT4S1STORAGE/$relorb/$SWATH/metadata.txt`; exit; fi
if [ ! -f $INDIR/*/$S.slc ]; then echo "Image "$S" does not exist in the BASE. Try coregistration?"`grep LAST $IT4S1STORAGE/$relorb/$SWATH/metadata.txt`; exit; fi

mkdir -p $TMPDIR
cd $TMPDIR

source $INDIR/metadata.txt #getting valid_lines etc.
SAMPLES=`grep samples $IT4S1STORAGE/$relorb/$SWATH/metadata.txt | cut -d '=' -f2` #need original sample size information
if [ $CROP -eq 1 ]; then
  if [ $CROP_CUSTOM -eq 1 ]; then
   echo "Cropping to custom limits"
   cpxfiddle -w $SAMPLES -o float -f cr4 -q normal -p $8 -P $9 -l ${10} -L ${11} $INDIR/*/$M.slc > M 2>/dev/null
   cpxfiddle -w $SAMPLES -o float -f cr4 -q normal -p $8 -P $9 -l ${10} -L ${11} $INDIR/*/$S.slc > S 2>/dev/null
   let SAMPLES=$9-$8'+1'
   let LINES=${11}-${10}'+1'
  else
   echo "Cropping input images for valid area"
   LINES=$valid_lines
   cpxfiddle -w $SAMPLES -o float -f cr4 -q normal -p $p -P $P -l $l -L $L $INDIR/*/$M.slc > M 2>/dev/null
   cpxfiddle -w $SAMPLES -o float -f cr4 -q normal -p $p -P $P -l $l -L $L $INDIR/*/$S.slc > S 2>/dev/null
   SAMPLES=$valid_samples
  fi
 else
  echo "Linking from IT4I Base"
  ln -s $INDIR/*/$M.slc M
  ln -s $INDIR/*/$S.slc S
  LINES=`grep lines $IT4S1STORAGE/$relorb/$SWATH/metadata.txt | cut -d '=' -f2`
 fi
cat << EOF > tmp_oct
addpath('~/WORK/shared/skripty/MATLAB/insarmatlab')
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
COH_WINSIZE     10 2
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
if [ $LINES -lt 500 ]; then OVERLAP=15; else OVERLAP=3; fi
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
 fi
fi

echo "Cleaning. Done. Check result:"
rm M S tmp_oct
echo gthumb `pwd`/ifg.ras