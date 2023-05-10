#!/bin/bash
#workaround for starting in screen
#module load intel
#module add Octave/4.2.1-intel-2017a
#(c) 2017 Milan Lazecky, IT4Innovations
# Should be run from IT4I

# This script should check and correct sample and line difference (already happened couple of times..)

if [ -z $2 ]; then
 echo "This script will check and correct bursts that show different samples/lines than Master"
 echo "Usage: "`basename $0`" M S"
 echo "  e.g. "`basename $0`" 20160313 20160325"
 exit
fi

M=$1
S=$2

samples=`grep "VRTDataset rasterXSize" $M/burst_01.slc.vrt | cut -d '"' -f2`
lines=`grep "VRTDataset rasterXSize" $M/burst_01.slc.vrt | cut -d '"' -f4`
S_samples=`grep "VRTDataset rasterXSize" $S/burst_01.slc.vrt | cut -d '"' -f2`
S_lines=`grep "VRTDataset rasterXSize" $S/burst_01.slc.vrt | cut -d '"' -f4`

if [ ! $samples -eq $S_samples ]; then
 # I do backup now.. but I should not J
 echo "Backing up..."
 mkdir bck; cp -r $S $S.xml bck/.
 echo "Correcting number of samples for "$S
 echo "("$S" has "$S_samples" samples, framework needs "$samples")."
 let DIFFSAM=$S_samples-$samples
 if [ $DIFFSAM -gt 0 ]; then
  #check validity for cropping
  FVS=`grep firstvalidsample $S.xml -A1 | grep value | cut -d '>' -f2 | cut -d '<' -f1 | sort -n | tail -n1`
  NVS=`grep numberofvalidsamples $S.xml -A1 | grep value | cut -d '>' -f2 | cut -d '<' -f1 | sort -n | tail -n1`
  let MAXVS=$FVS+$NVS
  if [ $MAXVS -gt $samples ]; then
   echo "Cropping w.r.t. valid area"
   p=`grep firstvalidsample $S.xml -A1 | grep value | cut -d '>' -f2 | cut -d '<' -f1 | sort -n | head -n1`
   #for MINVS in `grep firstvalidsample $S.xml -A1 | grep value`; do
   for VAL in `grep firstvalidsample $S.xml -A1 | grep value | cut -d '>' -f2 | cut -d '<' -f1 | sort -n | uniq`; do
    let NEWVAL=$VAL-$p+1
	xml ed -L -O -u "productmanager_name/component/component/component[property[@name='firstvalidsample']/value="$VAL"]/property[@name='firstvalidsample']/value" -v $NEWVAL $S.xml
   done
  else
   p=1
  fi
  let P=$samples+$p-1
  echo "cpxfiddle -w "$S_samples" -q normal -o float -f cr4 -p"$p" -P"$P" \$1 > tmp 2>/dev/null; mv tmp \$1" > correctS.sh
 else
cat <<EOF > tmp_oct_xlineS
addpath('~/WORK/shared/skripty/MATLAB/insarmatlab');
a=freadbk('tmp',$S_lines,'cpxfloat32');
diff=$samples-$S_samples;
b=[a zeros($S_lines,diff)];
fwritebk(b,'tmp','cpxfloat32');
EOF
  echo "mv \$1 tmp; octave-cli -q tmp_oct_xlineS; mv tmp \$1" > correctS.sh
 fi
 LINEOFFM=`xml sel -t -v "VRTDataset/VRTRasterBand/LineOffset" $M/burst_01.slc.vrt`
 for SBURST in `ls $S/b*.slc`; do
  echo "Correcting "$SBURST
  sh correctS.sh $SBURST 2>/dev/null
  sed -i 's/ue>'$S_samples'</ue>'$samples'</' $SBURST.xml
  sed -i 's/="'$S_samples'"/="'$samples'"/' $SBURST.vrt
  xml ed -L -O -u "VRTDataset/VRTRasterBand/LineOffset" -v $LINEOFFM $SBURST.vrt
 done
 sed -i 's/ue>'$S_samples'</ue>'$samples'</' $S.xml
 sed -i 's/ue>'$S_samples'</ue>'$samples'</' slave.xml
fi

if [ ! $lines -eq $S_lines  ]; then
 echo "Correcting number of lines for "$S
 echo "("$S" has "$S_lines" lines, framework needs "$lines")."
 let DIFFLIN=$S_lines-$lines
 if [ $DIFFLIN -gt 0 ]; then
 #check validity for cropping
  FVL=`grep firstvalidline $S.xml -A1 | grep value | cut -d '>' -f2 | cut -d '<' -f1 | sort -n | tail -n1`
  NVL=`grep numberofvalidlines $S.xml -A1 | grep value | cut -d '>' -f2 | cut -d '<' -f1 | sort -n | tail -n1`
  let MAXVL=$FVL+$NVL
  if [ $MAXVL -gt $lines ]; then
   echo "Cropping w.r.t. valid area"
   l=`grep firstvalidline $S.xml -A1 | grep value | cut -d '>' -f2 | cut -d '<' -f1 | sort -n | head -n1`
   for VAL in `grep firstvalidline $S.xml -A1 | grep value | cut -d '>' -f2 | cut -d '<' -f1 | sort -n | uniq`; do
    let NEWVAL=$VAL-$l+1
	xml ed -L -O -u "productmanager_name/component/component/component[property[@name='firstvalidline']/value="$VAL"]/property[@name='firstvalidline']/value" -v $NEWVAL $S.xml
   done
  else
   l=1
  fi
  let L=$lines+$l-1
  echo "cpxfiddle -w "$samples" -q normal -o float -f cr4 -l"$l" -L"$L" \$1 > tmp 2>/dev/null; mv tmp \$1" > correctL.sh
 else
#cat <<EOF > tmp_oct_xlineL
#addpath('~/WORK/shared/skripty/MATLAB/insarmatlab');
#a=freadbk('tmp',$S_lines,'cpxfloat32');
#diff=$lines-$S_lines;
#b=[a; zeros(diff,$samples)];
#fwritebk(b,'tmp','cpxfloat32');
#EOF

cat <<EOF > tmp_py_xlineL
diffL = $lines - $S_lines
with open('tmp', 'ab') as f:
	f.write('\0' * 4 * 2 * $samples * diffL)
EOF

#  echo "mv \$1 tmp; octave-cli -q tmp_oct_xlineL; mv tmp \$1" > correctL.sh
  echo "mv \$1 tmp; python tmp_py_xlineL; mv tmp \$1" > correctL.sh
 fi
 for SBURST in `ls $S/b*.slc`; do
  echo "Correcting "$SBURST
  sh correctL.sh $SBURST 2>/dev/null
  sed -i 's/ue>'$S_lines'</ue>'$lines'</' $SBURST.xml
  sed -i 's/="'$S_lines'"/="'$lines'"/' $SBURST.vrt
 done
 sed -i 's/ue>'$S_lines'</ue>'$lines'</' $S.xml
 sed -i 's/ue>'$S_lines'</ue>'$lines'</' slave.xml
fi
