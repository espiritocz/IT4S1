#!/bin/bash
#(c) 2017-2018 Milan Lazecky, IT4Innovations

IT4S1STORAGE=/home/laz048/DATA/.cz_s1/BASE
WDIR=/home/laz048/TEMP/cz_s1/stamps

#This is to find radar coordinates of given WGS84 location, based on lat/lon
#Should be done after burst is ready for stamps processing..

if [ -z $7 ]; then
 echo "Usage: "`basename $0`" projname relorb iw burst LAT LON RADIUS(in km) [SB?] [DATHRES]"
 echo "  e.g. "`basename $0`" ostravice 73 3 8008 49.511058 18.415157 7 1 0.5"
 exit
fi

#if [ `pwd | rev | cut -d '/' -f1 | rev | grep -c INSAR` -lt 1 ]; then echo "This is not a stamps workdir"; exit; fi

#Sentinel-1 (very coarse) resolution in m
RESS=5
RESL=25
PARJOB=24

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
#find coordinates
cat << EOF > find_coord.m
mujlat=$LAT;
mujlon=$LON;
radius=$RADIUS;
resS=$RESS;
resL=$RESL;
%first compute coordinate centers
addpath('/home/laz048/WORK/IT4INSAR/shared/matlab/insarmatlab');
len=load('len.txt');
sam=load('width.txt');
lat=freadbk('lat',len,'float32');
lon=freadbk('lon',len,'float32');
lat2=lat-mujlat;
lon2=lon-mujlon;
lonlat2=abs(lon2.*lat2);
[L,S]=find(lonlat2 == min(min(lonlat2)))
%now compute coordinates of min and max for the crop
radiusS=round(radius*1000/resS);
radiusL=round(radius*1000/resL);
LMIN=max([1 L-radiusL])
LMAX=min([len L+radiusL])
SMIN=max([1 S-radiusS])
SMAX=min([sam S+radiusS])
samples=SMAX-SMIN+1
lines=LMAX-LMIN+1
EOF
octave --eval find_coord -q 2>/dev/null | grep = | sed 's/ //g' > crop.txt
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
cp crop.txt $CROPDIR/.
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

#for x in `ls 201* -d`; do
 #DATE=`echo $x | rev | cut -d '/' -f1 | rev`
# mkdir CROP/$x
# cpxfiddle -w $W -o float -f cr4 -q normal -l $LMIN -L $LMAX -p $SMIN -P $SMAX $x/cint.minrefdem.raw > $DATE/cint.minrefdem.raw 2>/dev/null
#done
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
#rm do_mask.m lat lat_crop

#Generating help files (full mean_vel and DA maps)
echo "Generating average mean_amp and DA maps (in background)"
it4s1_stamps_generate_avg.sh >/dev/null &

it4s1_stamps_patcher 2 2 10 10 >/dev/null

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

#mt_extract_cands 1 1 1 1 "f" 0 "mask.ij" >/dev/null

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
setparm('gamma_change_convergence',0.01);setparm('gamma_max_iterations',5); setparm('weed_time_win',730); \
setparm('clap_win',16); setparm('small_baseline_flag','n');setparm('weed_standard_dev',1.3); setparm('dens',40);\
stamps(2,2); ps_select(1); stamps(4,4);exit" >/dev/null
echo "Finished PATCH_"\$1":"
tail -n1 PATCH_\$1/STAMPS.log
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
matlab -nodesktop -nosplash -r "getparm; setparm('merge_resample_size',20); setparm('small_baseline_flag','n'); setparm('max_topo_err',20); \
setparm('unwrap_time',730); setparm('unwrap_gold_alpha',0.4);setparm('unwrap_gold_n_win',8); setparm('unwrap_grid',200); stamps(5,5); \
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
mv exported.csv $WDIR/$projname/$relorb'_'$SWATH'_'$BURST'_crop'$CROPNO'_ps.csv'

#mv exported_vdao.csv $WDIR/$projname/$relorb'_'$SWATH'_'$BURST'_crop'$CROPNO'_ps.csv'
echo "Result of PS processing saved as: "
ls $WDIR/$projname/$relorb'_'$SWATH'_'$BURST'_crop'$CROPNO'_ps.csv'
chmod 777 $WDIR/$projname/$relorb'_'$SWATH'_'$BURST'_crop'$CROPNO'_ps.csv'
#exit
echo "PS processing finished at" >> $WDIR/$projname/$relorb'_'$SWATH'_'$BURST//processing.log
date >> $WDIR/$projname/$relorb'_'$SWATH'_'$BURST//processing.log
echo "---------------------------------" >> $WDIR/$projname/$relorb'_'$SWATH'_'$BURST//processing.log
if [ $SB -eq 1 ]; then it4s1_stamps_sb_burst.sh $projname $relorb $SWATH $BURST 1 $DATHR_SB; fi