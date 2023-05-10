#!/bin/bash
#source ~/cz_s1/db_vars
#source ~/mount/S1/BASE/CZ/crop.in
#alias isceserver="ssh root@147.251.253.242"
export PROJECTIT4I=OPEN-11-37
export IT4S1STAMPSDIR=/home/laz048/TEMP/cz_s1/stamps
export IT4S1STORAGE=/scratch/work/user/laz048/.cz_s1/BASE
export IT4S1STORAGEtmp=/scratch/work/user/laz048/.cz_s1/BASEtmp
PARJOB=24
DATHR=0.4

# (c) Milan Lazecky, IT4Innovations, 2017

# This script will perform STAMPS PS processing for selected burst.
# it can be run directly from the computing node!

if [ -z $4 ]; then
 echo "Perform STAMPS PS processing of given burst. Possibility of starting SB (default: only PS)"
 echo "Usage: "`basename $0`" PROJECTNAME RELORB IW BURST [FROM_DATE] [TO_DATE]"
 echo "parameters: -crop LAT LON RADIUS.... will perform processing only for cropped area"
 echo "            -sb ...... will perform also SB processing"
 echo "            -dathr ... sets a DA threshold (original value is 0.4)"
 echo "  e.g. "`basename $0`" -crop 49.511058 18.415157 7 -sb dalnice 124 2 21422 20170206 20170916"
 exit
fi

crop=0;SB=0
while [ "$1" != "" ]; do
    case $1 in
        -crop )     crop=1
                    shift
                    LAT=$1
                    shift
                    LON=$1
                    shift
                    RADIUS=$1
                                ;;
        -sb )     SB=1
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

BASEDIR=$IT4S1STORAGE/$relorb/$SWATH
DIR=$IT4S1STAMPSDIR/$projname/$relorb'_'$SWATH'_'$BURST
if [ -d $DIR ]; then echo "Already existing. Will delete it in 10 seconds.. (Cancel me)"; sleep 10; rm -r $DIR; fi
mkdir -p $DIR; cd $DIR

#sourcing dataset metadata, identifying Grandmaster
source $BASEDIR/metadata.txt
grandmaster=$master

# let's use all available images
it4s1_list_burst.sh $relorb $SWATH $BURST | tail -n+2 > day.1.in
# and from there we can do subset
if [ ! -z $6 ]; then
 firstpos=`grep -n $5 day.1.in | cut -d ':' -f1`
 lastpos=`grep -n $6 day.1.in | cut -d ':' -f1`
 cp day.1.in tmpday
 head -n $lastpos tmpday | tail -n+$firstpos > day.1.in
 rm tmpday
 #change master to the middle of selection
 let maspos=`cat day.1.in | wc -l`/2
 master=`head -n $maspos day.1.in | tail -n1`
fi

#prepare basics
STAMPSPROCDIR=`pwd`/INSAR_$master
mkdir -p $STAMPSPROCDIR
cd $STAMPSPROCDIR
mv ../day.1.in .
#masterday should not be in day.1.in!
sed -i '/'$master'/d' day.1.in
echo $master > master_day.1.in
echo $lines > len.txt
echo $samples > width.txt

#preparation of heading, E,N,.. - thanks to D. Bekaert
echo "Extracting heading and look angle"
BURSTLOCAL=`grep "_"$BURST $BASEDIR/burst_to_id.txt | cut -d '=' -f1 | cut -d '_' -f2`
imageMath.py -e="-1*a_1-270" --a=$IT4S1STORAGEtmp/$relorb/$SWATH/$grandmaster/isce/geom_master/los_$BURSTLOCAL.rdr -o heading.tmp -s BIL >/dev/null
gdalinfo -stats heading.tmp.vrt | grep MEAN | cut -d '=' -f2 > heading.1.in
rm heading.tm*
#imageMath.py --eval='sin(rad(a_0))*cos(rad(a_1+90))' --a=$IT4S1STORAGEtmp/$relorb/$SWATH/$master/isce/geom_master/los_$BURSTLOCAL.rdr -t FLOAT -s BIL -o e.raw
#imageMath.py --eval='sin(rad(a_0)) * sin(rad(a_1+90))' --a=$IT4S1STORAGEtmp/$relorb/$SWATH/$master/isce/geom_master/los_$BURSTLOCAL.rdr -t FLOAT -s BIL -o n.raw
#imageMath.py --eval='cos(rad(a_0))' --a=$IT4S1STORAGEtmp/$relorb/$SWATH/$master/isce/geom_master/los_$BURSTLOCAL.rdr -t FLOAT -s BIL -o u.raw
imageMath.py -e="a_0" --a=$IT4S1STORAGEtmp/$relorb/$SWATH/$grandmaster/isce/geom_master/los_$BURSTLOCAL.rdr -o look_angle.raw -s BIL >/dev/null

if [ $crop -eq 1 ]; then
echo "Checking if crop coordinates are inside the burst"
rm lat lon hgt 2>/dev/null
ln -s $IT4S1STORAGE/$relorb/$SWATH/$BURST/geom/lat
ln -s $IT4S1STORAGE/$relorb/$SWATH/$BURST/geom/lon
ln -s $IT4S1STORAGE/$relorb/$SWATH/$BURST/geom/hgt

#check if coordinates are inside the burst
sed 's/look_angle.raw/lon/' look_angle.raw.vrt > lon.vrt
sed 's/look_angle.raw/lat/' look_angle.raw.vrt > lat.vrt
gdalinfo -stats lon.vrt >/dev/null
gdalinfo -stats lat.vrt >/dev/null
MINLAT=`grep MINIM lat.vrt | xml sel -t -v "/"`
MAXLAT=`grep MAXIM lat.vrt | xml sel -t -v "/"`
MINLON=`grep MINIM lon.vrt | xml sel -t -v "/"`
MAXLON=`grep MAXIM lon.vrt | xml sel -t -v "/"`

if [ !  `echo "$LAT < $MAXLAT && $LAT > $MINLAT && $LON < $MAXLON && $LON > $MINLON" | bc` ]; then
 echo "Your coordinates are outside of the burst. Cancelling the task."
 echo "The min/max limits are:"
 echo "LAT: "$MINLAT" - "$MAXLAT
 echo "LON: "$MINLON" - "$MAXLON
 exit
fi
fi

#compute baselines
echo "Computing perp. baselines for PS combinations with master as "$master
mkdir temp; cd temp
cat << EOF > topsApp.xml
<topsApp>
<component name="topsinsar">
    <property name="Sensor name">SENTINEL1</property>
    <component name="master">
        <property name="output directory">$master</property>
    </component>
    <component name="slave">
        <property name="output directory">SLAVE</property>
    </component>
</component>
</topsApp>
EOF
ln -s $BASEDIR/isce/$master'.xml' master.xml

cat << EOF > tmp.sh
DATUM=\$1
mkdir \$DATUM; cd \$DATUM
sed 's/SLAVE/'\$DATUM'/' ../topsApp.xml > topsApp_bperp_\$DATUM'.xml'
ln -s ../master.xml
ln -s $BASEDIR/isce/\$DATUM'.xml' slave.xml
topsApp.py topsApp_bperp_\$DATUM'.xml' --dostep='computeBaselines' | grep Bperp | head -n1 | rev | gawk {'print \$1'} | rev > bperp
cd ..
EOF

chmod 775 tmp.sh
cat $STAMPSPROCDIR/day.1.in | parallel -j $PARJOB ./tmp.sh
rm tmp.sh
for DATUM in `cat $STAMPSPROCDIR/day.1.in`; do
 if [ -f $DATUM/bperp ]; then BP=`cat $DATUM/bperp`; else BP='nan'; fi
 #let's nullify situation of impossible bperp computation
 if [ -z $BP ]; then BP=0; fi
 if [ $BP == 'nan' ]; then BP=0; fi
 echo $BP  >> ../bperp.1.in
done
cd ..; rm -r temp

#prepare interferograms (parallelize)
echo "Generating "`cat day.1.in | wc -l`" interferograms"
cat << EOF > tmp.sh
#echo "Generating interferogram "$master" and "\$1
it4s1_burstifg.sh $master \$1 $relorb $SWATH $BURST 0 $STAMPSPROCDIR/\$1 >/dev/null
EOF
chmod 775 tmp.sh
cat day.1.in | parallel -j $PARJOB ./tmp.sh
rm tmp.sh

#naming conventions
for ifg in `ls */ifg`; do mv $ifg `echo $ifg | cut -d '/' -f1`/cint.minrefdem.raw; done

#prepare everything else
#cp *.1.in small_baselines.list $SBDIR
echo 1 > slc_osfactor.1.in
echo 0.05546576 > lambda.1.in
echo 2.3295 > rangepixelsize.1.in
#cp $SBDIR/small_baselines.list $SBDIR/ifgday.1.in
cat width.txt > pscdem.in
cp $IT4S1STORAGE/$relorb/$SWATH/metadata.txt .
echo $IT4S1STORAGE/$relorb/$SWATH/$BURST/geom/hgt >> pscdem.in
cat width.txt > psclonlat.in
echo $IT4S1STORAGE/$relorb/$SWATH/$BURST/geom/lon >> psclonlat.in
echo $IT4S1STORAGE/$relorb/$SWATH/$BURST/geom/lat >> psclonlat.in
cat width.txt > pscphase.in
ls `pwd`/*/cint.minrefdem.raw >> pscphase.in
#rm $SBDIR/calamp.in 2>/dev/null
#for x in `cat $SBDIR/day.1.in`; do
ls `pwd`/*/cint.minrefdem.raw > calamp.in
#done
echo "Calibrating amplitude (quick)"
calamp calamp.in `cat len.txt` calamp.out >/dev/null
echo $DATHR > selpsc.in
cat width.txt >> selpsc.in
cat calamp.out >> selpsc.in

if [ $crop -eq 1 ]; then
  echo "Performing processing only at given crop."
  it4s1_stamps_crop.sh $projname $relorb $SWATH $BURST $LAT $LON $RADIUS $SB
  exit
 else
  echo "Performing full burst optimized PS processing"
fi

#prepare mask based on zero values (non-valid areas) of geom file
echo "Preparing mask (currently only for lat/lon=0)"
ln -s $IT4S1STORAGE/$relorb/$SWATH/$BURST/geom/lat 2>/dev/null
cat << EOF > do_mask.m
addpath('/home/laz048/WORK/IT4INSAR/shared/matlab/insarmatlab');
len=load('len.txt');
lat=freadbk('lat',len,'float32');
%means 1=to be masked, 0=to be used
mask=lat==0;
fid = fopen('mask.ij','wb');
fwrite(fid,mask','integer*1');
fclose(fid);
EOF
octave --eval do_mask -q >/dev/null 2>/dev/null
rm do_mask.m

#Generating help files (full mean_vel and DA maps)
echo "Generating average mean_amp and DA maps (in background)"
it4s1_stamps_generate_avg.sh >/dev/null &

it4s1_stamps_patcher 5 2 10 10 >/dev/null
echo "Extracting candidates (around 1 minute)"
cat << EOF > patch_extract.sh
cd PATCH*\$1
selpsc_patch ../selpsc.in patch.in pscands.1.ij pscands.1.da mean_amp.flt "f" 0 ../mask.ij >/dev/null
psclonlat ../psclonlat.in pscands.1.ij pscands.1.ll >/dev/null
pscdem ../pscdem.in pscands.1.ij pscands.1.hgt >/dev/null
pscphase ../pscphase.in pscands.1.ij pscands.1.ph >/dev/null
cd ..
EOF
chmod 777 patch_extract.sh 
cat patch.list | cut -d '_' -f2 | parallel -j $PARJOB ./patch_extract.sh

#script to extract look_angle file and make PATCH processing
cat << EOF > patch_preproc.sh
#running MATLAB in 10 seconds delay - this pile of software is full of problems
let SLEEP=(\$1-1)*10
sleep \$SLEEP
#to prepare look angle file
cpxfiddle -w$samples -f r4 -o float -q normal -p\`sed '1q;d' PATCH_\$1/patch.in\` -P\`sed '2q;d' PATCH_\$1/patch.in\` -l\`sed '3q;d' PATCH_\$1/patch.in\` -L\`sed '4q;d' PATCH_\$1/patch.in\` look_angle.raw > PATCH_\$1/look_angle.raw 2>/dev/null
A=\`sed '1q;d' PATCH_\$1/patch.in\`
B=\`sed '2q;d' PATCH_\$1/patch.in\`
let W=\$B-\$A+1
echo \$W > PATCH_\$1/width.txt
matlab -nodesktop -nosplash -r "cd PATCH_"\$1";stamps(1,1); setparm('filter_weighting','SNR'); setparm('max_topo_err',20); \
width = load('width.txt'); ps = load('ps1.mat'); lasavename = 'la1.mat';laname = 'look_angle.raw';fid = fopen(laname,'r'); \
pa = load('patch.in'); data_la = fread(fid,[width inf],'real*4');fclose(fid); \
ij = ps.ij; IND = sub2ind(size(data_la),ij(:,3)+2-pa(1),ij(:,2)+2-pa(3));clear ij; \
la=data_la(IND);la = la*pi./180;save(lasavename,'la'); \
setparm('gamma_change_convergence',0.01);setparm('gamma_max_iterations',5); setparm('weed_time_win',365); \
setparm('clap_win',32); setparm('small_baseline_flag','n');setparm('weed_standard_dev',1.25); setparm('dens',20);\
stamps(2,4);exit" >/dev/null
echo "Finished PATCH_"\$1":"
tail -n1 PATCH_\$1/STAMPS.log
EOF
chmod 775 patch_preproc.sh
echo "Performing parallel processing of "`cat patch.list | wc -l`" patches (can be a very long run..)"
cat patch.list | cut -d '_' -f2 | parallel -j $PARJOB ./patch_preproc.sh

#preparing csv export script
#cat << EOF > LAZY_export_to_csv.m
#    ps_output;
#    ij      = load('ps_ij.txt');         % PS radar coord.
#    ps_ll   = load('ps_ll.txt');      % PS geographic coord
#    load pm2
#    load hgt2
#load ps_plot_v-dao ph_disp
#ps_f    = [ij ps_ll(:,2) ps_ll(:,1) hgt ph_disp coh_ps ];
#save(['phy_v-dao.mat'], 'ps_f');
#LAZY_stamps2rwt_csv
#EOF

echo "Processing PS using STAMPS"
#plus code to convert look angle to la file (thanks to D. Bakeart)
matlab -nodesktop -nosplash -r "getparm; setparm('merge_resample_size',20); setparm('small_baseline_flag','n'); setparm('max_topo_err',20); \
setparm('unwrap_time',365); setparm('unwrap_gold_alpha',0.75);setparm('unwrap_gold_n_win',16); setparm('unwrap_grid',200); stamps(5,5); \
width = load('width.txt'); ps = load('ps2.mat'); lasavename = 'la2.mat';laname = 'look_angle.raw';fid = fopen(laname,'r'); \
data_la = fread(fid,[width inf],'real*4');fclose(fid);ij = ps.ij; IND = sub2ind(size(data_la),ij(:,3)+1,ij(:,2)+1);clear ij; \
la=data_la(IND);la = la*pi./180;save(lasavename,'la'); \
stamps(6,6); setparm('unwrap_spatial_cost_func_flag','n'); setparm('subtr_tropo','n'); stamps(7,7); \
ps_calc_ifg_std;a=load('ifgstd2.mat');setparm('scla_drop_i',find(a.ifg_std>50)'); \
stamps(6,6); setparm('unwrap_spatial_cost_func_flag','y'); stamps(7,7); \
aps_linear; setparm('subtr_tropo','y');  setparm('unwrap_spatial_cost_func_flag','n'); stamps(6,7); \
a=load('ifgstd2.mat');setparm('scla_drop_i',find(a.ifg_std>55)'); setparm('unwrap_hold_good_values','y'); \
for u=1:3, u, stamps(6,7); end; \
setparm('scla_deramp','y');stamps(6,7); stamps(6,6); ps_plot('V-dao','a_l',-1); \
it4s1_stamps2csv; exit"
#LAZY_export_to_csv; exit"

mv exported.csv $DIR/../$relorb'_'$SWATH'_'$BURST'_ps.csv'
echo "This is the result: "
ls $DIR/../$relorb'_'$SWATH'_'$BURST'_ps.csv'

if [ $SB == 1 ]; then
 echo "Now processing SB"
 it4s1_stamps_sb_burst.sh $projname $relorb $SWATH $BURST
fi



#rm *aps* 2>/dev/null
#matlab -nodesktop -nosplash -r "aps_linear; setparm('subtr_tropo','y');  setparm('unwrap_spatial_cost_func_flag','n'); stamps(6,7); \
#ps_calc_ifg_std;a=load('ifgstd2.mat');setparm('sb_scla_drop_i',find(a.ifg_std>50)'); setparm('unwrap_hold_good_values','y'); \
#for u=1:4, u, stamps(6,7); end; \
#setparm('scla_deramp','y'); stamps(6,7); stamps(6,6); ps_plot('V-dao','a_l',-1); exit" 

#matlab -nodesktop -nosplash -r "LAZY_rsb_update(1); \
#setparm('unwrap_hold_good_values','n'); stamps(6,6);aps_linear;stamps(7,7); setparm('unwrap_spatial_cost_func_flag','y'); stamps(6,7); exit"



#matlab -nodesktop -nosplash -r "ps_calc_ifg_std;a=load('ifgstd2.mat');setparm('sb_scla_drop_i',find(a.ifg_std>55)'); \
#setparm('unwrap_hold_good_values','y'); setparm('unwrap_spatial_cost_func_flag','n'); for u=1:4, stamps(6,7); end; \
#ps_calc_ifg_std;a=load('ifgstd2.mat');setparm('sb_scla_drop_i',find(a.ifg_std>60)'); for u=1:4, stamps(6,7); end; ps_plot('V-dao','a_l',-1); exit"
#matlab -nodesktop -nosplash -r "LAZY_export_to_csv; exit"
