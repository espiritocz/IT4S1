#this is to generate full cz tiffs
startdate="2014-10-01"
enddate="2018-02-01"
module load GDAL PROJ GSL 2>/dev/null
echo "Merging all tiff outputs (all tiffs in this directory)"
gdal_merge.py -o FULL.tif -of GTiff -co COMPRESS=LZW -n -32768 -a_nodata -32768 -ot Int16 *.tif
echo "Resizing and converting to EPSG:3857"
gdalwarp -tr 0.001 0.001 FULL.tif temp_lowres.tif >/dev/null 2>/dev/null
gdalwarp temp_lowres.tif FULL_3857.tif -t_srs EPSG:3857
rm temp_lowres.tif
echo "Filtering using median filter"
pkfilter -i FULL_3857.tif -o temp_full.tif -dx 3 -dy 3 -f median
#saga_cmd grid_filter 6 -INPUT FULLCZ_3857.tif -MODE 1 -RADIUS 5 -THRESHOLD 0 -RESULT temp_full
#gdal_calc.py -A FULLCZ_3857.tif -B temp_full.sdat --NoDataValue=-999 --type='Int16' --co="COMPRESS=LZW" --outfile=temp_result.tif --calc="B+A*(B==0)"
echo "Adding back detailed pixels"
gdal_calc.py -A FULL_3857.tif -B temp_full.tif --NoDataValue=-32768 --type='Int16' --co="COMPRESS=LZW" --outfile=temp_result.tif --calc="B*(B!=-32768)+A*(B==-32768)" #>/dev/null 2>/dev/null
echo "Generating pyramids and writing statistics and metadata:"
IMAGEDESCRIPTION="Average velocity product (mm/year) from STAMPS PS processing of all available Sentinel-1 data over the Czech Republic from "$startdate"T0000+0100 until "$enddate"T0000+0100"
echo $IMAGEDESCRIPTION
gdal_translate -ot Int16 -of GTiff -stats -co "COMPRESS=LZW" -mo TIFFTAG_IMAGEDESCRIPTION="$IMAGEDESCRIPTION" temp_result.tif FULL_OUT.tif
gdaladdo -r nearest FULL_OUT.tif 2 4 8 16
rm temp_full* temp_result*

mv FULL_OUT.tif  avgvel_cz_$startdate"T0000+0100_"$enddate"T0000+0100".tif