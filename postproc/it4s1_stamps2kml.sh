#!/bin/bash

# (c) Milan Lazecky, IT4Innovations, 2018

# This script will convert basic results from STAMPS to a KML
# it should be run from the processing folder (that contains exported ps_plot_v-....mat file)

if [ -z $1 ]; then
 echo "Convert STAMPS processing results to a nice KML"
 echo "Usage: "`basename $0`" KMLFILENAME"
 echo "  e.g. "`basename $0`" ../../output/PS_result.kml"
 exit
fi

KMLFILENAME=$1
PLOTNAME=`ls ps_plot_v*mat | head -n1 | cut -d '.' -f1`
if [ ! -f $PLOTNAME.mat ] || [ -z $PLOTNAME ]; then
 echo "No ps_plot output detected. Are you in processing folder?"; exit
fi

echo "Converting result to KML (using MATLAB)"
cat << EOF > tokml.m
addpath('$STAMPSMATLABDIR');
load ps2
load pm2
load $PLOTNAME ph_disp
figure;scatter3(lonlat(:,1),lonlat(:,2),ph_disp(:),3,ph_disp(:),'filled');
view([0 90]);colormap(jet);colormap(fliplr(colormap));caxis([-25 10]);
gescatter('$KMLFILENAME',lonlat(:,1),lonlat(:,2),ph_disp(:),'scale',0.3,'clims',[-25 10],'colormap',fliplr(jet),'opacity',1)
EOF

matlab -nodesktop -nosplash -r "tokml;exit" >/dev/null 2>/dev/null

echo "done"