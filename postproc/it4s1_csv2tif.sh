#!/bin/bash
COHTR=0.65
COHTR=0.3

if [ -z $1 ]; then
 echo "Export STAMPS output CSV into TIFF. Currently only VEL."
 echo "Usage: "`basename $0`" input_csv [output_tif]"
 echo "  e.g. "`basename $0`" -coh 0.1 exported.csv [124_2_21422.tif]"
 echo "parameters: -coh ...... sets a COHER threshold (original value is "$COHTR")"
 exit
fi

while [ "$1" != "" ]; do
    case $1 in
        -coh )     COHTR=$2;
                                ;;
        * ) break ;;
    esac
    shift
done


IN=$1
if [ ! -z $2 ]; then OUT=$2; else OUT=`echo $IN | rev | cut -c 4- | rev`tif; fi

BASEFILE=`basename $IN`
cat << EOF > `echo $IN | rev | cut -c 4- | rev`vrt
<OGRVRTDataSource>
    <OGRVRTLayer name="`echo $BASEFILE | cut -d '.' -f1`">
        <SrcDataSource>$IN</SrcDataSource>
        <GeometryType>wkbPoint</GeometryType>
        <LayerSRS>WGS84</LayerSRS>
        <GeometryField encoding="PointFromColumns" x="LON" y="LAT" z="HEIGHT"/>
        <Field name="VEL" src="VEL" type="real" />
        <Field name="COHER" src="COHER" type="real" />
    </OGRVRTLayer>
</OGRVRTDataSource>
EOF

#gdal_rasterize -a VEL -tr 0.00075 0.00075 -l `echo $BASEFILE | cut -d '.' -f1` -a_nodata -999 -a_srs EPSG:4326 -where 'COHER>0.75' `echo $IN | rev | cut -c 4- | rev`vrt $OUT

gdal_rasterize -a VEL -tr 0.001 0.001 -l `echo $BASEFILE | cut -d '.' -f1` -a_nodata -32768 -a_srs EPSG:4326 -where 'COHER>'$COHTR `echo $IN | rev | cut -c 4- | rev`vrt $OUT
