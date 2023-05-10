#!/bin/bash

export WDIR=`pwd`
mkdir $WDIR/temp 2>/dev/null
export IT4S1STAMPSDIR=$WDIR/temp

PARJOB=24
PARJOB=8
DATHR=0.52
QSB=0
QSBTHR=0.38
CORRECT_HGT=0
MERGED=1
LICSBAS=1
# (c) Milan Lazecky, IT4Innovations, 2017

# This script will perform STAMPS SB processing for selected burst.
# it can be run directly from the computing node!
# Also, it can be performed only if PS processing already finished.

if [ -z $4 ]; then
 echo "Perform STAMPS SB processing of given burst (after PS finished). It will also merge PS and SB results"
 echo "Usage: "`basename $0`" PROJNAME RELORB IW BURST [CROP] [DA_THR]"
 echo "  e.g. "`basename $0`" dalnice 124 2 21422 [1] [0.6]"
 echo "parameters: -qsb ...... will perform QSB processing instead of SB"
 echo "            -dathr .... sets a DA threshold (original value is "$DATHR")"
 exit
fi

while [ "$1" != "" ]; do
    case $1 in
        -qsb )     QSB=1; MERGED=0;
                                ;;
        -dathr )     DATHR=$2;
                                ;;
        * ) break ;;
    esac
    shift
done

projname=$1
relorb=$2
SWATH=$3
BURST=$4

if [ -z $5 ]; then CROP=0; else CROP=$5; fi
if [ ! -z $6 ]; then DATHR=$6; fi


#BASEDIR=$IT4S1STORAGE/$relorb/$SWATH
DIR=$IT4S1STAMPSDIR/$projname/$relorb'_'$SWATH'_'$BURST
if [ ! -d $DIR/INSAR* ]; then echo "Work directory does not exist. Run STAMPS PS first."; exit; fi
cd $DIR/INSAR*
STAMPSPROCDIRINSAR=`pwd`
#now i work with CROP work folder in case of cropping..
if [ $CROP -eq 1 ]; then
 CROPDIR=`ls -dt CROP* 2>/dev/null| head -n1`;
 if [ -z $CROPDIR ] || [ ! -d $CROPDIR ]; then echo "There was an error in PS cropping. Cancelling SB."; exit;
  else cd $CROPDIR; fi
fi

#echo "Preparing SB connections. Old way, I should improve it by considering periods of year (low coh during summer)"
rm tmp.txt 2>/dev/null
echo "Preparing SB connections"
LIMIT_HICOH=25
cat master_day.1.in day.1.in | sort > alldays.txt
for x in `cat alldays.txt`; do
  ONEMORE=`grep -A1 $x alldays.txt | tail -n1`
  SECOND=`grep -A2 $x alldays.txt | tail -n1`
  THIRD=`grep -A3 $x alldays.txt | tail -n1`
  FOURTH=`grep -A4 $x alldays.txt | tail -n1`
  for LAST in $ONEMORE $SECOND $THIRD $FOURTH; do
   if [ ! $x == $LAST ]; then
    echo $x $LAST >> tmp.txt
   fi
  done
  case `echo $x | cut -c 5-6` in 03|04|10|11)
     for MORE in `grep -A5 $x alldays.txt | tail -n+4`; do
       if [ ! $x == $MORE ] && [ `datediff $x $MORE` -lt $LIMIT_HICOH ]; then echo $x $MORE >> tmp.txt; fi
     done
     ;;
  esac
done
sort -u tmp.txt > small_baselines.list
#head -n -3 tmp.txt > small_baselines.list
rm tmp.txt

echo "Induced "`cat small_baselines.list | wc -l`" connections."

#preparing the basics
mkdir SMALL_BASELINES
cp heading.1.in slc_osfactor.1.in lambda.1.in pscdem.in psclonlat.in width.txt len.txt master_day.1.in day.1.in SMALL_BASELINES/.
cp small_baselines.list SMALL_BASELINES/ifgday.1.in
ln -s `pwd`/mask.ij `pwd`/SMALL_BASELINES/mask.ij
ln -s `pwd`/look_angle.raw `pwd`/SMALL_BASELINES/look_angle.raw
cd SMALL_BASELINES

#echo "Generating interferograms with Goldstein spatial filtering (is it good idea?)"
echo "Generating interferograms (without Goldstein spatial filtering)"
STAMPSPROCDIR=`pwd`
#include master image
master=`cat master_day.1.in`
#prepare interferograms (parallelize)
if [ $LICSBAS -eq 1 ]; then more='-unw -gold'; else more=''; fi
cat << EOF > tmp_ifg.sh
OUT=\$1
if [ -d \$OUT ]; then exit; fi
M=\`echo \$OUT | cut -d '_' -f1\`
S=\`echo \$OUT | cut -d '_' -f2\`
#it4s1_burstifg4stamps.sh -coh -gold \$M \$S $relorb $SWATH $BURST 0 $STAMPSPROCDIRINSAR \$OUT >/dev/null
it4s1_burstifg4stamps.sh -coh $more \$M \$S $relorb $SWATH $BURST 0 $STAMPSPROCDIRINSAR \$OUT >/dev/null
EOF
#in Malaga case, a problem occurred with topography. This is to correct it:
if [ $CORRECT_HGT -eq 1 ]; then
 echo "LINENO=\`grep \"\$M \$S\" -n ifgday.1.in | cut -d ':' -f1\`" >> tmp_ifg.sh
 echo "BPERP=\`head -n\$LINENO bperp.1.in | tail -n1\`" >> tmp_ifg.sh
 echo "cd \$M'_'\$S" >> tmp_ifg.sh
 echo "sed 's/BPERP/'\$BPERP'/' ../tmp_oct_topocorr > tmp_oct_topocorr" >> tmp_ifg.sh
 echo "octave-cli -q tmp_oct_topocorr" >> tmp_ifg.sh
 echo "#mv ifgcorrected cint.minrefdem.raw" >> tmp_ifg.sh
 echo "cpxfiddle -w "`cat width.txt`" -o sunraster -c jet -M20/4 -q phase -f cr4 cint.minrefdem.raw > ifg_corrected.ras" >> tmp_ifg.sh
 echo "cd .." >> tmp_ifg.sh
 cat << EOF > tmp_oct_topocorr
addpath('$MATLABDIR');
lines=`cat len.txt`;
bperp=BPERP;
range=`grep slantrange $STAMPSPROCDIRINSAR/metadata.txt | cut -d '=' -f2`;
lambda=`cat lambda.1.in`;
%
lookang=freadbk('../look_angle.raw',lines,'float32');
hgt=freadbk('../../hgt',lines,'float32');
pha=(4*pi/lambda)*(bperp/range)*hgt./sind(lookang);
ifg=freadbk('cint.minrefdem.raw',lines,'cpxfloat32');
ifgpha=angle(ifg);
R=abs(ifg);
outpha=wrap(ifgpha-pha);
outifg=R.*exp(i*outpha);
fwritebk(outifg,'ifgcorrected','cpxfloat32');
EOF
fi
chmod 775 tmp_ifg.sh

#update - in case of cropped area..
if [ $CROP -eq 1 ]; then
 sed -i '/it4s1_burstifg4stamps.sh/d' tmp_ifg.sh
#it4s1_burstifg4stamps.sh -coh -gold \$M \$S $relorb $SWATH $BURST 0 $STAMPSPROCDIR \$OUT >/dev/null
 source ../crop.txt
 if [ $LICSBAS -eq 1 ]; then more='-unw -gold'; else more=''; fi
 #echo "it4s1_burstifg4stamps.sh -coh -gold \$M \$S $relorb $SWATH $BURST 1 $STAMPSPROCDIRINSAR \$OUT $SMIN $SMAX $LMIN $LMAX >/dev/null" >> tmp_ifg.sh
 echo "it4s1_burstifg4stamps.sh -coh $more \$M \$S $relorb $SWATH $BURST 1 $STAMPSPROCDIRINSAR \$OUT $SMIN $SMAX $LMIN $LMAX >/dev/null" >> tmp_ifg.sh
 #echo "it4s1_burstifg4stamps.sh -coh \$M \$S $relorb $SWATH $BURST 1 $STAMPSPROCDIRINSAR \$OUT $SMIN $SMAX $LMIN $LMAX >/dev/null" >> tmp_ifg.sh
fi
time sed 's/ /_/' ../small_baselines.list | parallel -j $PARJOB ./tmp_ifg.sh

if [ $LICSBAS -eq 1 ]; then
 echo "processing using LiCSBAS first.."
 tempdir=`pwd`
 cd $WDIR
 it4s1_licsbas.sh $projname $relorb $SWATH $BURST $CROP
 cd $tempdir
fi

# update 03/2018
# use average spat. coh. threshold to select ifgs for the SB processing
if [ $QSB -eq 1 ]; then
 echo "Performing Quasi-SB on threshold level "$QSBTHR
 echo "..computing average coherence"
 echo "cd \$1" > tmp.sh
 echo "octave-cli -q --eval=\"addpath('"$MATLABDIR"');lines=`cat ../len.txt`;a=freadbk('coh',lines,'float32');m=median(median(a));csvwrite('coh_med',m);exit\" >/dev/null" >> tmp.sh
 echo "cd .." >>tmp.sh
 chmod 777 tmp.sh
 sed 's/ /_/' ../small_baselines.list | parallel -j $PARJOB ./tmp.sh
 for x in `cat ../small_baselines.list | sed 's/ /_/'`; do
  echo `echo $x | sed 's/_/ /'` `cat $x/coh_med` >> small_baselines.coh
  #rm $x/coh_med
 done
 octave-cli -q --eval="a=dlmread('small_baselines.coh',' ');b=a(find(a(:,3)>"$QSBTHR"),1:2);dlmwrite('small_baselines.list',b,' ')"
 echo "..selected "`cat small_baselines.list | wc -l`" interferograms from "`cat ../small_baselines.list | wc -l`
 cp day.1.in day.1.in.bck; for x in `cat day.1.in`; do if [ `grep -c $x small_baselines.list` -lt 1 ]; then sed -i '/'$x'/d' day.1.in; fi; done
 echo ".."`cat day.1.in | wc -l`" images are used instead of original "`cat day.1.in.bck | wc -l`" images"
 count=0
 for a in `head -n-1 day.1.in`; do
  b=`grep -A1 $a day.1.in | tail -n1`
  if [ `grep -c $a" "$b small_baselines.list` -lt 1 ]; then
   let count=$count+1
   echo $a" "$b >> small_baselines.extra
  fi
 done
 echo "..updating SB list"
 cp ../small_baselines.list ../small_baselines.list.bck
 cat small_baselines.extra >> small_baselines.list
 sed 's/ /_/' small_baselines.list | sort -u | sed 's/_/ /' > ../small_baselines.list
 mv ifgday.1.in ifgday.1.in.bck
 cp ../small_baselines.list ifgday.1.in
 rm small_baselines.list
 mkdir removed
 for x in `ls 2* -d`; do if [ `sed 's/ /_/' ../small_baselines.list | grep -c $x` -lt 1 ]; then mv $x removed/.; fi; done
 echo "..generating "$count" additional interferograms"
 time sed 's/ /_/' ../small_baselines.list | parallel -j $PARJOB ./tmp_ifg.sh
fi


#Further preparation of SB project
#naming convention
#for ifg in `ls */ifg_filt`; do mv $ifg `echo $ifg | cut -d '/' -f1`/cint.minrefdem.raw; done
## 2020 change - use non filtered ifgs
for ifg in `ls */ifg`; do mv $ifg `echo $ifg | cut -d '/' -f1`/cint.minrefdem.raw; done

#no need for coh and orig, delete them
rm 2*/coh 2*/coh.ras 2*/ifg 2*/ifg.ras 2>/dev/null

#compute baselines
echo "Computing perp. baselines for SB combinations"
rm bperp.1.in 2>/dev/null
mkdir temp; cd temp
cat << EOF > topsApp.xml
<topsApp>
<component name="topsinsar">
    <property name="Sensor name">SENTINEL1</property>
    <component name="master">
        <property name="output directory">MASTER</property>
    </component>
    <component name="slave">
        <property name="output directory">SLAVE</property>
    </component>
</component>
</topsApp>
EOF
cat << EOF > tmp.sh
mkdir \$1; cd \$1
MASTER=\`echo \$1 | cut -d '_' -f1\`
SLAVE=\`echo \$1 | cut -d '_' -f2\`
sed 's/MASTER/'\$MASTER'/' ../topsApp.xml > topsApp_bperp_\$1'.xml'
sed 's/SLAVE/'\$SLAVE'/' ../topsApp.xml > topsApp_bperp_\$1'.xml'
ln -s $STAMPSPROCDIRINSAR/isce/\$MASTER'.xml' master.xml
ln -s $STAMPSPROCDIRINSAR/isce/\$SLAVE'.xml' slave.xml
topsApp.py topsApp_bperp_\$1'.xml' --dostep='computeBaselines' 2>/dev/null | grep Bperp | head -n1 | rev | gawk {'print \$1'} | rev > bperp 2>/dev/null
cd ..
EOF
chmod 775 tmp.sh
sed 's/ /_/' ../../small_baselines.list | parallel --will-cite -j $PARJOB ./tmp.sh
rm tmp.sh
for PAIR in `sed 's/ /_/' ../../small_baselines.list`; do
 if [ -f $PAIR/bperp ]; then BP=`cat $PAIR/bperp`; else BP='nan'; fi
 #let's ignore situation of impossible bperp computation
 if [ -z $BP ]; then BP=0; fi
 if [ $BP == 'nan' ]; then BP=0; fi
 echo $BP  >> ../bperp.1.in
done
cd ..; rm -r temp

#preparation for selection of PS candidates and calibration of amplitude
cat width.txt > pscphase.in
#cp selpsc.in selsbc.in

#if possible, make the PATCH processing in ramdisk:
#copy to ramdisk
RDAVAIL=`df | grep /ramdisk | gawk {'print $4'}`
SBCONTENT=`du . | tail -n1 | gawk {'print $1'}`
let RDSB=$RDAVAIL-$SBCONTENT
if [ $RDSB -gt 1400000 ]; then 
 echo "Copying SB ifg files to ramdisk (great speed up of SBC extraction)"
 RAMDISKYES=1
 if [ -z $PBS_JOBID ]; then PBS_JOBID=`ls /ramdisk | cut -d '/' -f2`; fi
 mkdir -p /ramdisk/$PBS_JOBID/$BURST/SMALL_BASELINES
 #cd ..
 time cp -r 2*_* /ramdisk/$PBS_JOBID/$BURST/SMALL_BASELINES/.
 ls /ramdisk/$PBS_JOBID/$BURST/SMALL_BASELINES/*/cint.minrefdem.raw >> pscphase.in
 ls /ramdisk/$PBS_JOBID/$BURST/SMALL_BASELINES/*/cint.minrefdem.raw > calamp.in
 #cd /ramdisk/$PBS_JOBID/$BURST/SMALL_BASELINES
 PARJOB2=$PARJOB
else
 RAMDISKYES=0
 PARJOB2=4
 ls `pwd`/*/cint.minrefdem.raw >> pscphase.in
 ls `pwd`/*/cint.minrefdem.raw > calamp.in
fi
if [ $QSB -eq 1 ]; then 
 for extra in `sed 's/ /_/' small_baselines.extra`; do
  sed -i '/'$extra'/d' calamp.in
 done
fi
echo "Calibrating amplitude"
time calamp calamp.in `cat len.txt` calamp.out >/dev/null
echo $DATHR > selpsc.in
cat width.txt >> selpsc.in
cat calamp.out >> selpsc.in

#Generating help files (full mean_vel and DA maps)
echo "Generating average mean_amp and DA maps (in background)"
it4s1_stamps_generate_avg.sh >/dev/null &

echo "Preparing patches"
#echo "TODO it, this is only for my one crop area.."
if [ `cat len.txt` -lt 250 ]; then PAT1=2; PAT2=1; clap=8;
 elif [ `cat len.txt` -lt 500 ]; then PAT1=3; PAT2=2; clap=16;
 elif [ `cat len.txt` -lt 750 ]; then PAT1=4; PAT2=2; clap=32;
 elif [ `cat len.txt` -lt 1000 ]; then PAT1=4; PAT2=3; clap=64;
 elif [ `cat len.txt` -lt 1250 ]; then PAT1=5; PAT2=3; clap=64;
 else PAT1=8; PAT2=3; clap=64
fi
it4s1_stamps_patcher $PAT1 $PAT2 10 10 >/dev/null
echo "Extracting candidates (around 1 minute)"

cat << EOF > patch_extract.sh
cd PATCH_\$1
#selpsc_patch ../selpsc.in patch.in pscands.1.ij pscands.1.da mean_amp.flt "f" 0 ../mask.ij >/dev/null
#selsbc_patch_new selsbc.in patch.in pscands.1.ij pscands.1.da mean_amp.flt "f" 0 ../mask.ij #>/dev/null
selsbc_patch ../selpsc.in patch.in pscands.1.ij pscands.1.da mean_amp.flt ../mask.ij >/dev/null
psclonlat ../psclonlat.in pscands.1.ij pscands.1.ll >/dev/null
pscdem ../pscdem.in pscands.1.ij pscands.1.hgt >/dev/null
pscphase ../pscphase.in pscands.1.ij pscands.1.ph >/dev/null
echo \`cat pscands.1.ij | wc -l \`" candidates in PATCH_"\$1" extracted"
cd ..
EOF
chmod 777 patch_extract.sh 
time cat patch.list | cut -d '_' -f2 | parallel -j $PARJOB2 ./patch_extract.sh
#remove empty patches
for p in `ls PATCH_* -d`; do
 NUMCAN=`cat $p/pscands.1.ij | wc -l`
 if [ $NUMCAN -eq 0 ]; then sed -i '/'$p'/d' patch.list; echo "Removing "$p; fi
done

#Clean ramdisk
if [ $RAMDISKYES -eq 1 ]; then rm -r /ramdisk/$PBS_JOBID/$BURST/SMALL_BASELINES; fi

#average maps of mean and DA
#it4s1_stamps_generate_avg.sh >/dev/null 2>/dev/null &

#Preparing initial processing
cat << EOF > patch_preproc.m
addpath('$STAMPSMATLABDIR');
getparm;setparm('small_baseline_flag','y');stamps(1,1);
setparm('filter_weighting','SNR'); setparm('max_topo_err',15);
psver=1; save('psver.mat','psver');
width = load('width.txt'); ps = load('ps1.mat');
%generating look angle values for points selection
lasavename = 'la1.mat';laname = 'look_angle.raw';fid = fopen(laname,'r');
pa = load('patch.in'); data_la = fread(fid,[width inf],'real*4');fclose(fid);
ij = ps.ij; IND = sub2ind(size(data_la),ij(:,3)+2-pa(1),ij(:,2)+2-pa(3));clear ij;
la=data_la(IND);la = la*pi./180;save(lasavename,'la');
%post-selecting points
setparm('gamma_change_convergence',0.04);setparm('gamma_max_iterations',5); 
setparm('clap_win',$clap); setparm('clap_low_pass_wavelen',600); 
stamps(2,2)
%skipping PS_selection since it is too long and not very effective
%setparm('dens',30); stamps(3,3)
ps_select(1);
%weeding
setparm('weed_time_win',730); setparm('weed_standard_dev',1);
stamps(4,4)
EOF

cat << EOF > patch_preproc.sh
let SLEEP=\$1*5
sleep \$SLEEP
#to prepare look angle file
cpxfiddle -w\`cat width.txt\` -f r4 -o float -q normal -p\`sed '1q;d' PATCH_\$1/patch.in\` -P\`sed '2q;d' PATCH_\$1/patch.in\` -l\`sed '3q;d' PATCH_\$1/patch.in\` -L\`sed '4q;d' PATCH_\$1/patch.in\` look_angle.raw > PATCH_\$1/look_angle.raw 2>/dev/null
A=\`sed '1q;d' PATCH_\$1/patch.in\`
B=\`sed '2q;d' PATCH_\$1/patch.in\`
let W=\$B-\$A+1
echo \$W > PATCH_\$1/width.txt
cd PATCH_\$1
cp ../patch_preproc.m .
matlab -nodesktop -nosplash -r "run('patch_preproc.m');exit" >/dev/null
cd ..
echo "Finished PATCH_"\$1":"
tail -n1 PATCH_\$1/STAMPS.log
EOF

echo "Performing paralleled initial processing. Wait for some 60 minutes or more.."
chmod 775 patch_preproc.sh
#module load MATLAB/2015b-EDU
#PARJOB=12
time cat patch.list | cut -d '_' -f2 | parallel -j $PARJOB ./patch_preproc.sh

#Checking results of initial processing
for p in `cat patch.list`; do 
 if [ `tail -n1 $p/STAMPS.log | grep PS_SELECT | grep -c Finished` -eq 1 ]; then
  echo "No points left in "$p". Removing"
  sed -i '/'$p'/d' patch.list
 fi
 if [ `tail -n1 $p/STAMPS.log | grep PS_WEED | grep -c Finished` -eq 0 ]; then
  echo "Some error occurred at "$p". Removing"
  sed -i '/'$p'/d' patch.list
 fi
done


if [ $CROP -eq 1 ]; then
 if [ `cat len.txt` -lt 500 ]; then
  echo "This is rather small area. Setting small windows, may have unwrapping errors"
  gold_n_win=8
  O=''; OBIT='n'
  else
  gold_n_win=16
  O='o'; OBIT='y'
 fi
 unwrap_grid=200
 csv_name=$relorb'_'$SWATH'_'$BURST'_crop'`echo $CROPDIR | cut -c 5-`'_sb.csv'
else
 gold_n_win=32
 unwrap_grid=200
 O='o'; OBIT='y'
 csv_name=$relorb'_'$SWATH'_'$BURST'_sb.csv'
fi
#Quasi SB does not work with unwrap_hold_good_values - simply no triangles here..
if [ $QSB -eq 1 ]; then HOLDGOOD='n'; else HOLDGOOD='y'; fi

echo "Finished. Processing SB using STAMPS"
echo "I will not include the rsb filter here for now.."
cat << EOF > sb_proc.m
addpath('$STAMPSMATLABDIR');addpath('$MATLABDIR');addpath('$TRAINMATLABDIR');
getparm;
setparm('merge_resample_size',50);
setparm('small_baseline_flag','y');
setparm('max_topo_err',20);
stamps(5,5);
setparm('unwrap_time',730);
setparm('unwrap_gold_alpha',0.8);
setparm('unwrap_gold_n_win',$gold_n_win);
setparm('unwrap_grid',$unwrap_grid);
%look angle solution
width = load('width.txt');ps = load('ps2.mat'); lasavename = 'la2.mat';laname = 'look_angle.raw';fid = fopen(laname,'r'); psver=2; save('../psver.mat','psver');
data_la = fread(fid,[width inf],'real*4');fclose(fid);ij = ps.ij; IND = sub2ind(size(data_la),ij(:,3)+1,ij(:,2)+1);clear ij;la=data_la(IND);la = la*pi./180;save(lasavename,'la');
setparm('unwrap_spatial_cost_func_flag','n');
scla_reset;
setparm('subtr_tropo','n');
setparm('scla_deramp','n');
setparm('unwrap_hold_good_values','n');
setparm('unwrap_m','3D_QUICK'); stamps(6,6);
ps_calc_ifg_std;a=load('ifgstd2.mat');setparm('sb_scla_drop_i',find(a.ifg_std>45)');
setparm('unwrap_hold_good_values','$HOLDGOOD');
stamps(7,7); 
%this function ends in error for SB in CROP
%setparm('unwrap_spatial_cost_func_flag','y');
stamps(6,7);
%aps_linear; setparm('subtr_tropo','y'); 
setparm('unwrap_spatial_cost_func_flag','n');
a=load('ifgstd2.mat');setparm('sb_scla_drop_i',find(a.ifg_std>50)');
%for u=1:3, u, stamps(6,7); end;
setparm('scla_deramp','$OBIT'); for u=1:3, u, stamps(6,7); end; 
ps_plot('V-d$O',-1);
%ps_plot('V-da$O','a_l',-1);
it4s1_stamps2csv
EOF
matlab -nodesktop -nosplash -r "run('sb_proc.m'); exit"

chmod 777 exported.csv
mv exported.csv $WDIR/output/$projname'_'$csv_name
it4s1_csv2tif.sh -coh 0 $WDIR/output/$projname'_'$csv_name
echo "Result of SB processing saved as: "
ls $WDIR/output/$projname'_'$csv_name
echo "SB processing finished at" >> $WDIR/output/logs/$projname.log
date >> $WDIR/output/logs/$projname.log

if [ $MERGED -eq 0 ]; then
 echo "Processing done, no merging will be performed"
 exit
fi
echo "Now as the last stage, the processing results should be merged."
cd $DIR/INSAR*
if [ $CROP -eq 1 ]; then
 CROPDIR=`ls CROP* -d | tail -n1 | rev | cut -d '/' -f1 | rev`
 INSARDIR=`pwd | rev | cut -d '/' -f1 | rev`
 cd $DIR
 mv $INSARDIR processing
 cd processing
 mv $CROPDIR $INSARDIR
 cd $INSARDIR
else
 cd $DIR/INSAR*
fi

cat << EOF > merge_proc.m
addpath('$STAMPSMATLABDIR');addpath('$MATLABDIR');addpath('$TRAINMATLABDIR');
cd MERGED;
getparm;
setparm('merge_resample_size',20);
setparm('small_baseline_flag','y');
setparm('unwrap_time',730);
setparm('unwrap_gold_alpha',0.8);
setparm('unwrap_gold_n_win',$gold_n_win);
setparm('unwrap_grid',$unwrap_grid);
setparm('unwrap_spatial_cost_func_flag','n');
setparm('subtr_tropo','n');
setparm('scla_deramp','n');
setparm('unwrap_hold_good_values','n');
setparm('unwrap_m','3D_QUICK');
stamps(6,6);
%ps_calc_ifg_std;a=load('ifgstd2.mat');setparm('sb_scla_drop_i',find(a.ifg_std>45)');
%setparm('unwrap_hold_good_values','$HOLDGOOD');
stamps(7,7); stamps(6,7);
aps_linear; setparm('subtr_tropo','y');  setparm('unwrap_spatial_cost_func_flag','n');
%a=load('ifgstd2.mat');setparm('sb_scla_drop_i',find(a.ifg_std>50)');
for u=1:3, u, stamps(6,7); end;
setparm('scla_deramp','$OBIT'); for u=1:3, u, stamps(6,7); end; ps_plot('V-da$O','a_l',-1);
it4s1_stamps2csv
EOF

matlab -nodesktop -nosplash -r "addpath('$STAMPSMATLABDIR');ps_sb_merge;merge_proc; exit"
cd MERGED
chmod 777 exported.csv
mv exported.csv $WDIR/output/$projname'_'`echo $csv_name | sed 's/_sb/_merged/'`
it4s1_csv2tif.sh -coh 0 $WDIR/output/$projname'_'`echo $csv_name | sed 's/_sb/_merged/'`
