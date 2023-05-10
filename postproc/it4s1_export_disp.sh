#convert all csvs to disp with given year and week number
module load parallel Octave
module load GDAL PROJ GSL 2>/dev/null
YEARD=$1
WEEKD=$2
PARJOB=24
ls ALL*csv > temp_csvs.txt
echo "Generating disp maps"
cat temp_csvs.txt | parallel -j $PARJOB it4s1_csv2tif_disp.sh {} $YEARD $WEEKD >/dev/null 2>/dev/null
rm temp_csvs.txt

echo "Merging all tiff outputs (all tiffs in this directory)"
gdal_merge.py -o ttFULL.tif -of GTiff -co COMPRESS=LZW -n -32768 -a_nodata -32768 -ot Int16 disp*.tif
echo "Resizing and converting to EPSG:3857"
gdalwarp -tr 0.001 0.001 ttFULL.tif temp_lowres.tif >/dev/null 2>/dev/null
gdalwarp temp_lowres.tif ttFULL_3857.tif -t_srs EPSG:3857
rm temp_lowres.tif
echo "Filtering using median filter"
pkfilter -i ttFULL_3857.tif -o temp_full.tif -dx 3 -dy 3 -f median
echo "Adding back detailed pixels"
gdal_calc.py -A ttFULL_3857.tif -B temp_full.tif --NoDataValue=-32768 --type='Int16' --co="COMPRESS=LZW" --outfile=temp_result.tif --calc="B*(B!=-32768)+A*(B==-32768)" #>/dev/null 2>/dev/null
echo "Generating pyramids and writing statistics and metadata:"
IMAGEDESCRIPTION="Displacements map (mm/week) from STAMPS PS processing of all available Sentinel-1 data over the Czech Republic for week "$WEEKD" of year "$YEARD
echo $IMAGEDESCRIPTION
gdal_translate -ot Int16 -of GTiff -stats -co "COMPRESS=LZW" -mo TIFFTAG_IMAGEDESCRIPTION="$IMAGEDESCRIPTION" temp_result.tif ttFULL_OUT.tif
gdaladdo -r nearest ttFULL_OUT.tif 2 4 8 16
rm temp_full* temp_result*
SDATE=`ls disp*tif | head -n1 | rev | cut -d '_' -f1 | cut -d '.' -f2 | rev`
mv ttFULL_OUT.tif  disp_cz_$SDATE.tif
rm ttFULL.tif ttFULL_3857.tif