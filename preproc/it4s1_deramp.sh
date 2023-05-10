#!/bin/bash
PARJOB=24
#(c) 2017 Milan Lazecky, IT4Innovations
# Should be run from IT4I

if [ -z $1 ]; then
 echo "This script will flatten out all bursts in BURSTFOLDER by their rangeoff screens."
 echo "Usage: "`basename $0`" BURSTFOLDER"
 echo "  e.g. "`basename $0`" fine_coreg"
 exit
fi

FOLDER=$1

echo "Deramping. Original coregistered images will be overwritten!"
for B in `ls $FOLDER/burst*.slc`; do
 NO=`basename $B .slc | cut -d '_' -f2`
 echo $NO >> tmp_parjobs
cat << EOF > tmp_oct_$NO
addpath('~/WORK/shared/skripty/MATLAB/insarmatlab')
lines=`head -n1 $B'.vrt' | cut -d '"' -f4`;
I=freadbk('$B',lines,'cpxfloat32');
R=freadbk('fine_offsets/range_$NO.off',lines,'float32');
lambda=`it4s1_get_xmlvalue.sh radarwavelength master.xml`;
resol=`it4s1_get_xmlvalue.sh rangepixelsize master.xml`;
fact=4*pi*resol/lambda;
IR=exp(i*fact*R);
OUT=I .* (-IR);
fwritebk(OUT,'$B','cpxfloat32');
clear all;
EOF
done

cat << EOF > tmp.sh
echo "Deramping burst_"\$1
octave-cli -q tmp_oct_\$1 2>/dev/null
rm tmp_oct_\$1
EOF

chmod 775 tmp.sh
cat tmp_parjobs | parallel -j $PARJOB ./tmp.sh
rm tmp_parjobs
touch $FOLDER/deramped