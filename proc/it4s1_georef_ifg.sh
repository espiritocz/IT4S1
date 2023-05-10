#!/bin/bash
#(c) 2017 Milan Lazecky, IT4Innovations
# Should be run from IT4I

if [ -z $5 ]; then
 echo "This script will georeference an interferogram."
 echo "Usage: "`basename $0`" ifg_name width length lon_file lat_file [real_only?] [outname] [do_kml?]"
 echo "  e.g. "`basename $0`" 20170820_20170901/cint.minrefdem.raw 500 200 lon lat [1] [a/b.tif] [0]"
 exit
fi

ifg=$1
wid=$2
len=$3
lon=$4
lat=$5

if [ ! -z $6 ]; then realfile=$6; else realfile=0; fi
if [ ! -z $7 ]; then OUT=$7; else OUT=$ifg'.tif'; fi
if [ ! -z $8 ]; then dokml=$8; else dokml=0; fi

OUT_COLOR=`echo $OUT | sed 's/.tif/_rgb.tif/'`

rm tmp_lat tmp_lon tmp_lat.vrt tmp_lon.vrt 2>/dev/null
ln -s $lat tmp_lat
ln -s $lon tmp_lon
#vrt files for lon and lat
#if [ ! -e $lon'.vrt' ]; then
cat << EOF > tmp_lon'.vrt'
<VRTDataset rasterXSize="$wid" rasterYSize="$len">
  <VRTRasterBand dataType="Float32" band="1" subClass="VRTRawRasterBand">
  <SourceFilename relativeToVRT="1">tmp_lon</SourceFilename>
  </VRTRasterBand>
</VRTDataset>
EOF
#fi

#if [ ! -e $lat'.vrt' ]; then
cat << EOF > tmp_lat.vrt
<VRTDataset rasterXSize="$wid" rasterYSize="$len">
  <VRTRasterBand dataType="Float32" band="1" subClass="VRTRawRasterBand">
  <SourceFilename relativeToVRT="1">tmp_lat</SourceFilename>
  </VRTRasterBand>
</VRTDataset>
EOF
#fi

#prepare temporary phase raster and connection with lon/lat
if [ $realfile -eq 0 ]; then
 cpxfiddle -w $wid -o float -q phase $ifg > temp_ifg 2>/dev/null
else
 ln -s $ifg temp_ifg
fi
cat << EOF > temp_ifg.vrt
<VRTDataset rasterXSize="$wid" rasterYSize="$len">
   <Metadata domain="GEOLOCATION">
     <MDI key="X_DATASET">tmp_lon.vrt</MDI>
     <MDI key="X_BAND">1</MDI>
     <MDI key="Y_DATASET">tmp_lat.vrt</MDI>
     <MDI key="Y_BAND">1</MDI>
     <MDI key="PIXEL_OFFSET">0</MDI>
     <MDI key="LINE_OFFSET">0</MDI>
     <MDI key="PIXEL_STEP">1</MDI>
     <MDI key="LINE_STEP">1</MDI>
   </Metadata>
  <VRTRasterBand dataType="Float32" band="1" subClass="VRTRawRasterBand">
     <SourceFilename relativeToVRT="1">temp_ifg</SourceFilename>
     <SourceBand>1</SourceBand>
     <ByteOrder>LSB</ByteOrder>
  </VRTRasterBand>
</VRTDataset>
EOF

#produce the output file
#echo $wid
gdalwarp -co TFW=YES -co COMPRESS=LZW -co PREDICTOR=3 -dstnodata 32768 -geoloc $PARAM -t_srs EPSG:4326 temp_ifg.vrt $OUT >/dev/null

if [ $dokml -eq 1 ]; then
 if [ $wid -gt 5000 ]; then PARAM="-tr 0.0005 0.0005"; echo "Reducing the size to KMZ"; fi
 gdalwarp -co TFW=YES -geoloc $PARAM -t_srs EPSG:4326 temp_ifg.vrt tmptmp.tif >/dev/null
 gdaldem color-relief -of GTiff tmptmp.tif `which hsv.txt` $OUT_COLOR >/dev/null
 rm tmptmp.tif
 geotiff2kml $OUT_COLOR 2>/dev/null >/dev/null
fi

#TIFWID=`gdalinfo $OUT | grep "Size is" | gawk {'print $3'} | cut -d ',' -f1`
#cpxfiddle -w $wid -q phase -o sunraster -c jet temp_ifg | convert temp_ifg.tif
##gdal_translate $PARAM -of KMLSUPEROVERLAY $OUT `echo $OUT | sed 's/tif/kmz/'` -co FORMAT=JPEG
#gdal_translate $PARAM -of KMLSUPEROVERLAY temp_ifg.png `echo $OUT | sed 's/tif/kmz/'` -co FORMAT=JPEG

#clean
rm temp_ifg temp_ifg.vrt
rm tmp_lat tmp_lon tmp_lat.vrt tmp_lon.vrt

echo "Georeferenced interferogram saved as "$OUT
