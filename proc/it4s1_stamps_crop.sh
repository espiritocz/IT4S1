#!/bin/bash
#(c) 2017-2018 Milan Lazecky, IT4Innovations

WEED=1.5
WDIR=`pwd`/temp

#This is to find radar coordinates of given WGS84 location, based on lat/lon
#Should be done after burst is ready for stamps processing..

if [ -z $7 ]; then
 echo "Usage: "`basename $0`" projname relorb iw burst LAT LON RADIUS(in km) [SB?] [DATHRES]"
 echo "  e.g. "`basename $0`" ostravice 73 3 8008 49.511058 18.415157 7 1 0.5"
 echo "(run it from the base WORKDIR, i.e. WORKDIR/temp/ostravice/73_3_8008/IN*.."
 exit
fi

PARJOB=24

#unwraptime=8
unwraptime=30

projname=$1
relorb=$2
SWATH=$3
BURST=$4
#radius in km
LAT=$5
LON=$6
RADIUS=$7
if [ ! -z $8 ]; then SB=$8; else SB=0; fi
if [ ! -z $9 ]; then DATHR=$9; DATHR_SB=`echo $DATHR+0.15 | bc`; else DATHR=0.4; DATHR_SB=''; fi

WORKDIR=$WDIR/$projname/$relorb'_'$SWATH'_'$BURST/IN*
if [ `ls -d $WORKDIR 2>/dev/null | wc -l` -lt 1 ]; then echo "This burst is not processed. Cancelling"; exit; fi
cd $WORKDIR
echo "---------------------------------" >> ../processing.log
echo "Starting processing of command" >> ../processing.log
echo `basename $0` $1 $2 $3 $4 $5 $6 $7 $8 $9 >> ../processing.log
date >> ../processing.log
echo "---------------------------------" >> ../processing.log

it4s1_get_coord.sh $relorb $SWATH $BURST $LAT $LON $RADIUS metadata.txt
source crop.txt
#rm lon lat.vrt lon.vrt

echo "Cropping interferograms"
if [ -d CROP ]; then
  let CROPNO=1+`ls -d CROP* | wc -l`;
  CROPDIR="CROP"$CROPNO
 else CROPDIR="CROP"; CROPNO=1;
fi
mkdir $CROPDIR
cp *.1.in $CROPDIR/.
cp crop.txt metadata.txt $CROPDIR/.
#mv mask.ij psc* 201* look_an* selpsc.in BCK/.
W=`cat width.txt`
#cp width.txt len.txt BCK/.
echo $samples > $CROPDIR/width.txt
echo $lines > $CROPDIR/len.txt
cat << EOF > tmp.sh
mkdir $CROPDIR/\$1
cpxfiddle -w $W -o float -f cr4 -q normal -l $LMIN -L $LMAX -p $SMIN -P $SMAX \$1/cint.minrefdem.raw > $CROPDIR/\$1/cint.minrefdem.raw 2>/dev/null
EOF
chmod 777 tmp.sh
ls 201* -d | parallel -j $PARJOB ./tmp.sh
rm tmp.sh

cpxfiddle -w $W -o float -f r4 -q normal -l $LMIN -L $LMAX -p $SMIN -P $SMAX look_angle.raw > $CROPDIR/look_angle.raw 2>/dev/null
cpxfiddle -w $W -o float -f r4 -q normal -l $LMIN -L $LMAX -p $SMIN -P $SMAX lat > $CROPDIR/lat 2>/dev/null
cpxfiddle -w $W -o float -f r4 -q normal -l $LMIN -L $LMAX -p $SMIN -P $SMAX lon > $CROPDIR/lon 2>/dev/null
cpxfiddle -w $W -o float -f r4 -q normal -l $LMIN -L $LMAX -p $SMIN -P $SMAX hgt > $CROPDIR/hgt 2>/dev/null
for x in `ls psc*`; do
 echo $samples > $CROPDIR/$x
done
cd $CROPDIR
echo `pwd`/hgt >> pscdem.in
echo `pwd`/lon >> psclonlat.in
echo `pwd`/lat >> psclonlat.in
ls `pwd`/*/cint.minrefdem.raw >> pscphase.in
echo $DATHR > selpsc.in
echo $samples >> selpsc.in
INPROJ=`pwd | rev | cut -d '/' -f2 | rev`
tail -n+3 ../selpsc.in | sed 's/'$INPROJ'/'$INPROJ'\/'$CROPDIR'/' >> selpsc.in

echo "Preparing mask (only lat/lon=0)"
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
#rm do_mask.m lat lat_crop

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
selpsc_patch ../selpsc.in patch.in pscands.1.ij pscands.1.da mean_amp.flt "f" 0 ../mask.ij >/dev/null
psclonlat ../psclonlat.in pscands.1.ij pscands.1.ll >/dev/null
pscdem ../pscdem.in pscands.1.ij pscands.1.hgt >/dev/null
pscphase ../pscphase.in pscands.1.ij pscands.1.ph >/dev/null
cd ..
EOF
chmod 777 patch_extract.sh 
cat patch.list | cut -d '_' -f2 | parallel -j $PARJOB ./patch_extract.sh

#mt_extract_cands 1 1 1 1 "f" 0 "mask.ij" >/dev/null

#script to extract look_angle file and make PATCH processing
cat << EOF > patch_preproc.sh
#to prepare look angle file
cpxfiddle -w$samples -f r4 -o float -q normal -p\`sed '1q;d' PATCH_\$1/patch.in\` -P\`sed '2q;d' PATCH_\$1/patch.in\` -l\`sed '3q;d' PATCH_\$1/patch.in\` -L\`sed '4q;d' PATCH_\$1/patch.in\` look_angle.raw > PATCH_\$1/look_angle.raw 2>/dev/null
A=\`sed '1q;d' PATCH_\$1/patch.in\`
B=\`sed '2q;d' PATCH_\$1/patch.in\`
let W=\$B-\$A+1
echo \$W > PATCH_\$1/width.txt
cd PATCH_\$1
rm parms.mat 2>/dev/null

#(dumb) patch to use stamps with octave
for x in bp1 da1 hgt1 ps1 ph1 psver bp2 da2 hgt2 ps2 ph2 select1 select2 la2 pm1 pm2 rc2 weed1 parms; do ln -s \$x \$x.mat; done

octave-cli -q --eval "warning('off','all'); save_default_options ('-mat7-binary');pkg local_list '$OCTAVEPKG/.octave_packages'; pkg load control signal; addpath('$OCTAVEPKG'); \
addpath('$STAMPSMATLABDIR'); stamps(1,1); setparm('filter_weighting','SNR'); setparm('max_topo_err',30); \
width = load('width.txt'); ps = load('ps1.mat'); lasavename = 'la1.mat';laname = 'look_angle.raw';fid = fopen(laname,'r'); \
pa = load('patch.in'); data_la = fread(fid,[width inf],'real*4');fclose(fid); \
ij = ps.ij; IND = sub2ind(size(data_la),ij(:,3)+2-pa(1),ij(:,2)+2-pa(3));clear ij; \
la=data_la(IND);la = la*pi./180;save(lasavename,'la'); \
setparm('gamma_change_convergence',0.01);setparm('gamma_max_iterations',5); setparm('weed_time_win',730); \
setparm('clap_win',$clap); setparm('small_baseline_flag','n');setparm('weed_standard_dev',$WEED); setparm('dens',40); \
stamps(2,2)" # ps_select(1);exit"

#lscov does not work in octave, donno why, need to do it in matlab :(
matlab -nodesktop -nosplash -r "addpath('$STAMPSMATLABDIR');ps_select(1); stamps(4,4);exit" >/dev/null
echo "Finished PATCH_"\$1":"
tail -n1 STAMPS.log
EOF


chmod 775 patch_preproc.sh
echo "Performing parallel processing of "`cat patch.list | wc -l`" patches (can be a very long run..)"
cat patch.list | cut -d '_' -f2 | parallel -j $PARJOB ./patch_preproc.sh

#Checking results of initial processing
for p in `cat patch.list`; do 
 if [ `tail -n1 $p/STAMPS.log | grep PS_WEED | grep -c Finished` -eq 0 ]; then
  echo "Some error occurred at "$p". Removing"
  sed -i '/'$p'/d' patch.list
 fi
done

#if the area is too small, do not make deramping!
if [ `cat len.txt` -lt 750 ]; then O=''; else O='o'; fi

#preparing csv export script
#cat << EOF > LAZY_export_to_csv.m
#    ps_output;
#    ij      = load('ps_ij.txt');         % PS radar coord.
#    ps_ll   = load('ps_ll.txt');      % PS geographic coord
#    load pm2
#    load hgt2
#load ps_plot_v-d$O ph_disp
#ps_f    = [ij ps_ll(:,2) ps_ll(:,1) hgt ph_disp coh_ps ];
#save(['phy_v-dao.mat'], 'ps_f');
#LAZY_stamps2rwt_csv
#EOF

echo "Processing PS using STAMPS"
#plus code to convert look angle to la file (thanks to D. Bakeart)
matlab -nodesktop -nosplash -r "addpath('"$STAMPSMATLABDIR"');addpath('"$MATLABDIR"');addpath('"$TRAINMATLABDIR"');getparm; setparm('merge_resample_size',20); setparm('small_baseline_flag','n'); setparm('max_topo_err',20); \
setparm('unwrap_time',$unwraptime); setparm('unwrap_gold_alpha',0.4);setparm('unwrap_gold_n_win',8); setparm('unwrap_grid',200); stamps(5,5); \
width = load('width.txt'); ps = load('ps2.mat'); lasavename = 'la2.mat';laname = 'look_angle.raw';fid = fopen(laname,'r'); \
data_la = fread(fid,[width inf],'real*4');fclose(fid);ij = ps.ij; IND = sub2ind(size(data_la),ij(:,3)+1,ij(:,2)+1);clear ij; \
la=data_la(IND);la = la*pi./180;save(lasavename,'la'); \
stamps(6,6); setparm('unwrap_spatial_cost_func_flag','n'); setparm('subtr_tropo','n'); stamps(7,7); \
ps_calc_ifg_std;a=load('ifgstd2.mat');setparm('scla_drop_i',find(a.ifg_std>45)'); \
stamps(6,6); setparm('unwrap_spatial_cost_func_flag','y'); stamps(7,7); \
ps_calc_ifg_std;a=load('ifgstd2.mat');setparm('scla_drop_i',find(a.ifg_std>50)'); \
setparm('unwrap_spatial_cost_func_flag','n'); stamps(6,7); \
setparm('unwrap_hold_good_values','y'); \
for u=1:3, u, stamps(6,7); end; \
setparm('scla_deramp','y');stamps(6,7); stamps(6,6); ps_plot('V-d"$O"',-1); \
it4s1_stamps2csv; exit"
#LAZY_export_to_csv; exit"
chmod 777 exported.csv
#mv exported.csv $WDIR/../output/$projname'_'$csv_name
mv exported.csv $WDIR/$projname'_'$relorb'_'$SWATH'_'$BURST'_crop'$CROPNO'_ps.csv'
if [ -d $WDIR/../output ]; then
 cp $WDIR/$projname'_'$relorb'_'$SWATH'_'$BURST'_crop'$CROPNO'_ps.csv' $WDIR/../output/.; 
 it4s1_csv2tif.sh $WDIR/../output/$projname'_'$relorb'_'$SWATH'_'$BURST'_crop'$CROPNO'_ps.csv'
fi
#mv exported_vdao.csv $WDIR/$projname/$relorb'_'$SWATH'_'$BURST'_crop'$CROPNO'_ps.csv'
echo "Result of PS processing saved as: "
ls $WDIR/$projname'_'$relorb'_'$SWATH'_'$BURST'_crop'$CROPNO'_ps.csv'
#ls $WDIR/$projname/$relorb'_'$SWATH'_'$BURST'_crop'$CROPNO'_ps.csv'
#chmod 777 $WDIR/$projname/$relorb'_'$SWATH'_'$BURST'_crop'$CROPNO'_ps.csv'
#exit
echo "PS processing finished at" >> $WDIR/$projname/$relorb'_'$SWATH'_'$BURST//processing.log
date >> $WDIR/$projname/$relorb'_'$SWATH'_'$BURST//processing.log
echo "---------------------------------" >> $WDIR/$projname/$relorb'_'$SWATH'_'$BURST//processing.log
if [ $SB -eq 1 ]; then 
 echo "SB processing started" >> $WDIR/$projname/$relorb'_'$SWATH'_'$BURST//processing.log
 it4s1_stamps_sb.sh $projname $relorb $SWATH $BURST 1 $DATHR_SB;
fi
