#!/bin/bash

export WDIR=`pwd`
mkdir $WDIR/output 2>/dev/null
mkdir $WDIR/temp 2>/dev/null

PARJOB=24
DATHR=0.4
CORRECTHGT=0
CLEAN=0

# (c) Milan Lazecky, IT4Innovations, 2017-2018

# This script will perform STAMPS PS processing for selected burst..or crop
# it can be run directly from the computing node!

if [ -z $4 ]; then
 echo "Perform STAMPS PS processing of given burst. Possibility of starting SB (default: only PS)"
 echo "Usage: "`basename $0`" PROJECTNAME RELORB IW BURST [FROM_DATE] [TO_DATE]"
 echo "parameters: -crop LAT LON RADIUS.... will perform processing only for cropped area"
 echo "            -ref LAT LON ........... will provide coordinates of reference area (150 m radius)"
 echo "            -sb ...... will perform also SB processing"
 echo "            -dathr ... sets a DA threshold (original value is 0.4)"
 echo "            -clean ... delete work folder after processing"
 echo "  e.g. "`basename $0`" -crop 49.511058 18.415157 7 -sb dalnice 124 2 21422 20170206 20170916"
 echo "reference point: setparm('ref_centre_lonlat',[-4.5687 36.7319]);setparm('ref_rad',150)"
 exit
fi

crop=0;SB=0;REFP=0
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
        -ref )      REFP=1
                    shift
                    REFLAT=$1
                    shift
                    REFLON=$1
                                ;;
        -sb )     SB=1
                                ;;
        -clean )     CLEAN=1
                                ;;
        -dathr )     DATHR=$2;
                     shift
                                ;;
        * ) break ;;
    esac
    shift
done

projname=$1
relorb=$2
SWATH=$3
BURST=$4

DIR=$WDIR/temp/$projname/$relorb'_'$SWATH'_'$BURST
cd $DIR

#prepare basics
echo "Starting at: "
date

#sourcing dataset metadata, identifying Grandmaster
cd INSAR_*
if [ ! -f metadata.txt ]; then 
 echo "error - some files not found. exiting"
 exit
fi
source metadata.txt
grandmaster=$master
cd -

STAMPSPROCDIR=`pwd`/INSAR_$master
cd $STAMPSPROCDIR

if [ $crop -eq 1 ]; then
echo "Checking if crop coordinates are inside the burst"
#rm lat lon hgt 2>/dev/null
#ln -s $IT4S1STORAGE/$relorb/$SWATH/$BURST/geom/lat
#ln -s $IT4S1STORAGE/$relorb/$SWATH/$BURST/geom/lon
#ln -s $IT4S1STORAGE/$relorb/$SWATH/$BURST/geom/hgt

cat << EOF > look_angle.raw.vrt2
<VRTDataset rasterXSize="$samples" rasterYSize="$lines">
  <SRS>EPSG:4326</SRS>
  <GeoTransform>0.0, 1.0, 0.0, 0.0, 0.0, 1.0</GeoTransform>
  <VRTRasterBand dataType="Float32" band="1" subClass="VRTRawRasterBand">
    <SourceFilename relativeToVRT="1">look_angle.raw</SourceFilename>
    <ImageOffset>0</ImageOffset>
    <PixelOffset>4</PixelOffset>
    <LineOffset>`echo $samples*4 | bc`</LineOffset>
    <ByteOrder>LSB</ByteOrder>
  </VRTRasterBand>
</VRTDataset>
EOF
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

#updating metadata.txt file for the average look angle
if [ -z $inc_angle ]; then
avginc=`gdalinfo -stats look_angle.raw.vrt | grep MEAN | cut -d '=' -f2 | cut -c -5`
echo "inc_angle="$avginc >> metadata.txt
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
cp ../master.xml .

cat << EOF > tmp.sh
DATUM=\$1
mkdir \$DATUM; cd \$DATUM
sed 's/SLAVE/'\$DATUM'/' ../topsApp.xml > topsApp_bperp_\$DATUM'.xml'
ln -s ../master.xml
cp $STAMPSPROCDIR/isce/\$DATUM'.xml' slave.xml
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
it4s1_burstifg4stamps.sh $master \$1 $relorb $SWATH $BURST 0 $STAMPSPROCDIR \$1 >/dev/null
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
#echo $IT4S1STORAGE/$relorb/$SWATH/$BURST/geom/hgt >> pscdem.in
echo `pwd`/hgt >> pscdem.in
cat width.txt > psclonlat.in
#echo $IT4S1STORAGE/$relorb/$SWATH/$BURST/geom/lon >> psclonlat.in
#echo $IT4S1STORAGE/$relorb/$SWATH/$BURST/geom/lat >> psclonlat.in
echo `pwd`/lon >> psclonlat.in
echo `pwd`/lat >> psclonlat.in
cat width.txt > pscphase.in
ls `pwd`/*/cint.minrefdem.raw >> pscphase.in
#rm $SBDIR/calamp.in 2>/dev/null
#for x in `cat $SBDIR/day.1.in`; do
ls `pwd`/*/cint.minrefdem.raw > calamp.in
#done









echo "Calibrating amplitude (quick)"
date
calamp calamp.in `cat len.txt` calamp.out >/dev/null
if [ `grep -c 'w 0' calamp.out` -gt 0 ];
then
 echo "you have erroneous files here:"
 grep 'w 0' calamp.out | gawk {'print $1'}
 echo "removing them from processing"
 for x in `grep 'w 0' calamp.out | gawk {'print $1'} | rev | cut -d '/' -f2 | rev`; do
  rm -r $x
  n=`grep -n $x day.1.in | cut -d ':' -f1`
  sed -i $n'd' day.1.in
  sed -i $n'd' bperp.1.in
  sed -i $n'd' calamp.in
  sed -i $n'd' calamp.out
  let m=$n+1
  sed -i $m'd' pscphase.in
 done
fi
echo $DATHR > selpsc.in
cat width.txt >> selpsc.in
cat calamp.out >> selpsc.in



if [ $crop -eq 1 ]; then
  echo "Performing processing only at given crop."
  cd $WDIR
  it4s1_stamps_crop.sh $projname $relorb $SWATH $BURST $LAT $LON $RADIUS $SB $DATHR
  exit
 else
  echo "Performing full burst optimized PS processing"
fi



#prepare mask based on zero values (non-valid areas) of geom file
echo "Preparing mask (currently only for lat/lon=0)"
#ln -s $IT4S1STORAGE/$relorb/$SWATH/$BURST/geom/lat 2>/dev/null
#ln -s $IT4S1STORAGE/$relorb/$SWATH/$BURST/geom/lon 2>/dev/null
cat << EOF > do_mask.m
addpath('$MATLABDIR');
len=load('len.txt');
lat=freadbk('lat',len,'float32');
%means 1=to be masked, 0=to be used
mask=lat==0;
fid = fopen('mask.ij','wb');
fwrite(fid,mask','integer*1');
fclose(fid);
EOF
octave-cli --eval do_mask -q >/dev/null 2>/dev/null
rm do_mask.m

#Generating help files (full mean_vel and DA maps)
echo "Generating average mean_amp and DA maps (in background)"
date
it4s1_stamps_generate_avg.sh >/dev/null &

it4s1_stamps_patcher 6 4 20 20 >/dev/null
#echo "Extracting candidates (around 1 minute)"
cat << EOF > patch_extract.sh
cd PATCH_\$1
selpsc_patch ../selpsc.in patch.in pscands.1.ij pscands.1.da mean_amp.flt "f" 0 ../mask.ij >/dev/null
psclonlat ../psclonlat.in pscands.1.ij pscands.1.ll >/dev/null
pscdem ../pscdem.in pscands.1.ij pscands.1.hgt >/dev/null
pscphase ../pscphase.in pscands.1.ij pscands.1.ph >/dev/null
cd ..
EOF
chmod 777 patch_extract.sh
#putting this line to the 'second job'
#cat patch.list | cut -d '_' -f2 | parallel -j $PARJOB ./patch_extract.sh

#patch for octave/matlab fusion
rm parms 2>/dev/null
ln -s parms.mat parms

#script to extract look_angle file and make PATCH processing
cat << EOF > patch_preproc.sh
#to prepare look angle file
cpxfiddle -w$samples -f r4 -o float -q normal -p\`sed '1q;d' PATCH_\$1/patch.in\` -P\`sed '2q;d' PATCH_\$1/patch.in\` \
  -l\`sed '3q;d' PATCH_\$1/patch.in\` -L\`sed '4q;d' PATCH_\$1/patch.in\` look_angle.raw > PATCH_\$1/look_angle.raw 2>/dev/null
A=\`sed '1q;d' PATCH_\$1/patch.in\`
B=\`sed '2q;d' PATCH_\$1/patch.in\`
let W=\$B-\$A+1
echo \$W > PATCH_\$1/width.txt
cd PATCH_\$1

#good try with octave but it did not work - why? because lscov showed strange error :((

#oh and, you need to be patching octave result after stamps(1,1):
#for x in \`ls\`; do if [ \`echo \$x | grep -c '\.'\` -eq 0 ]; then ln -s \$x \$x.mat; fi; done
#matlab -nodesktop -nosplash -r "

rm parms.mat 2>/dev/null
for x in bp1 da1 hgt1 ps1 ph1 psver bp2 da2 hgt2 ps2 ph2 select1 select2 la2 pm1 pm2 rc2 weed1 parms; do ln -s \$x \$x.mat; done

gamma_max_iterations=3 #it was 5 before, but some bursts did not finish processing within one (free) hour...

octave-cli -q --eval "warning('off','all'); save_default_options ('-mat7-binary'); pkg local_list '$OCTAVEPKG/.octave_packages'; pkg load control signal; addpath('$OCTAVEPKG'); \
addpath('$STAMPSMATLABDIR'); stamps(1,1); setparm('filter_weighting','SNR'); setparm('max_topo_err',80); \
width = load('width.txt'); ps = load('ps1.mat'); lasavename = 'la1.mat';laname = 'look_angle.raw';fid = fopen(laname,'r'); \
pa = load('patch.in'); data_la = fread(fid,[width inf],'real*4');fclose(fid); \
ij = ps.ij; IND = sub2ind(size(data_la),ij(:,3)+2-pa(1),ij(:,2)+2-pa(3));clear ij; \
la=data_la(IND);la = la*pi./180;save(lasavename,'la'); \
setparm('gamma_change_convergence',0.01);setparm('gamma_max_iterations',3); setparm('weed_time_win',730); \
setparm('clap_win',32); setparm('small_baseline_flag','n');setparm('weed_standard_dev',1.4); setparm('dens',20); \
stamps(2,2)" # ps_select(1);exit

#lscov does not work, need to do it in matlab :(
matlab -nodesktop -nosplash -r "addpath('$STAMPSMATLABDIR');ps_select(1); stamps(4,4);exit" >/dev/null
echo "Finished PATCH_"\$1":"
tail -n1 STAMPS.log
EOF
chmod 775 patch_preproc.sh







echo "this should be for the second run"
#octave-cli -q --eval "warning('off','all');save_default_options ('-mat7-binary');pkg prefix $OCTAVEPKG; pkg load control signal; addpath('$OCTAVEPKG');\
#i remove deramping and APS, it is too experimental and cannot be applied everywhere..
#setparm('scla_deramp','y');stamps(6,7); stamps(6,6); ps_plot('V-dao','a_l',-1); \
#you may change to:
#setparm('scla_deramp','n');stamps(6,7); stamps(6,6); ps_plot('V-D',-1); \
#LAZY_export_to_csv; exit"

#source ~/IT4S1/bashrc

cat << EOF > $relorb'_'$SWATH'_'$BURST'_ps2'
cd `pwd`
echo "Extracting PS candidates"
cat patch.list | cut -d '_' -f2 | parallel -j $PARJOB ./patch_extract.sh

echo "Performing parallel processing of "`cat patch.list | wc -l`" patches (can be a very long run..)"
cat patch.list | cut -d '_' -f2 | parallel -j $PARJOB ./patch_preproc.sh

#Checking results of initial processing
for p in \`cat patch.list\`; do 
 if [ \`tail -n1 \$p/STAMPS.log | grep PS_WEED | grep -c Finished\` -eq 0 ]; then
  echo "Some error occurred at "\$p". Removing"
  sed -i '/'\$p'/d' patch.list
 fi
done

echo "Processing PS using STAMPS"
#plus code to convert look angle to la file (thanks to D. Bakeart)
#establishing reference point
if [ $REFP -gt 0 ]; then
 SETREFP="setparm('ref_radius',150);setparm('ref_centre_lonlat',["$REFLON" "$REFLAT"]);"
else
 SETREFP=""
fi

matlab -nodesktop -nosplash -r "addpath('"$STAMPSMATLABDIR"');addpath('"$TRAINMATLABDIR"'); addpath('$MATLABDIR');\
getparm; setparm('merge_resample_size',50); setparm('small_baseline_flag','n'); setparm('max_topo_err',25); \
setparm('unwrap_time',90); setparm('unwrap_gold_alpha',0.75);setparm('unwrap_gold_n_win',16); setparm('unwrap_grid',320); stamps(5,5); \
width = load('width.txt'); ps = load('ps2.mat'); lasavename = 'la2.mat';laname = 'look_angle.raw';fid = fopen(laname,'r'); \
data_la = fread(fid,[width inf],'real*4');fclose(fid);ij = ps.ij; IND = sub2ind(size(data_la),ij(:,3)+1,ij(:,2)+1);clear ij; \
la=data_la(IND);la = la*pi./180;save(lasavename,'la'); \
$SETREFP stamps(6,6); setparm('unwrap_spatial_cost_func_flag','n'); setparm('subtr_tropo','n'); stamps(7,7); \
ps_calc_ifg_std;a=load('ifgstd2.mat');setparm('scla_drop_i',find(a.ifg_std>50)'); \
stamps(6,6); setparm('unwrap_spatial_cost_func_flag','y'); stamps(7,7); \
aps_linear; setparm('subtr_tropo','n');  setparm('unwrap_spatial_cost_func_flag','n'); stamps(6,7); \
a=load('ifgstd2.mat');setparm('scla_drop_i',find(a.ifg_std>55)'); setparm('unwrap_hold_good_values','y'); \
for u=1:2, u, stamps(6,7); end; \
setparm('scla_deramp','y');stamps(6,7); stamps(6,6); ps_plot('V-do',-1); \
it4s1_stamps2csv; exit"

cp metadata.txt $WDIR/output/$projname'_'$relorb'_metadata.txt'
mv exported.csv $WDIR/output/$projname'_'$relorb'_'$SWATH'_'$BURST'_ps.csv'
it4s1_csv2tif.sh $WDIR/output/$projname'_'$relorb'_'$SWATH'_'$BURST'_ps.csv'
echo "This is the result: "
ls $WDIR/output/$projname'_'$relorb'_'$SWATH'_'$BURST'_ps.csv'

if [ $SB == 1 ]; then
 echo "Now processing SB"
 cd $WDIR
 it4s1_stamps_sb.sh $projname $relorb $SWATH $BURST $crop
fi

if [ $CLEAN -eq 1 ]; then
 cd $WDIR
 rm -r $WDIR/temp/$projname/$relorb'_'$SWATH'_'$BURST
fi

EOF

chmod 777 $relorb'_'$SWATH'_'$BURST'_ps2'
qsub -q qexp ./$relorb'_'$SWATH'_'$BURST'_ps2'

sleep 360 #just waiting to be sure that avg and da maps are created..
