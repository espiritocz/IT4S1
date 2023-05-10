#this is to be used in parallel way for generation maps of weekly displacements
IN=$1
YEAR=$2
WEEKNO=$3

mkdir temp_$IN
cd temp_$IN
cp ../$IN .
head -n1 $IN > temp_head
tail -n+2 $IN > temp_body.txt

a=0; for x in `head -n1 $IN | sed 's/,/ /g'`; do let a=$a+1; if [ `echo $x | grep -c 20` -gt 0 ]; then octave-cli -q --eval "datenum('$x','dd-mmm-YYYY')" | gawk {'print $3'} >> temp_dates.txt; echo $a >> temp_dates_num.txt; fi;
for MORE in LAT LON COHER; do
 if [ `echo $x | grep -c $MORE` -gt 0 ]; then echo "$MORE="$a >> temp_add.txt; fi;
done
done

cat << EOF > temp_oct.m
year=$YEAR;
weekno=$WEEKNO;
startingday=datenum(year,01,01);
startingday=startingday+7*weekno;
%datestr(startingday,'YYYY-mm-dd')
%datestr(startingday,'dd-mmm-YYYY')

in=csvread('temp_dates.txt');
sorted=in-startingday;
[M,I]=min(abs(sorted));
if (I==length(sorted))
 J=I-1;
elseif (I==1)
 J=2;
else
 J=I+1;
endif
I
J
LEN=abs(sorted(J)-sorted(I))
DATUM=datestr(startingday,'YYYY-mm-dd')
EOF

octave-cli -q temp_oct.m | sed 's/ //g' >> temp_add.txt
source temp_add.txt
COLI=`head -n $I temp_dates_num.txt | tail -n1`
COLJ=`head -n $J temp_dates_num.txt | tail -n1`

octave-cli -q --eval="a=csvread('temp_body.txt');lat=a(:,$LAT);lon=a(:,$LON);coher=a(:,$COHER);coli=a(:,$COLI);colj=a(:,$COLJ);disp=((colj-coli)/$LEN)*7;X=([lon lat coher disp]);csvwrite('temp_week.txt',X);"
echo "LON,LAT,COHER,DISP" > temp_disp.csv
cat temp_week.txt >> temp_disp.csv

BASEFILE=`basename $IN`
cat << EOF > temp_disp.vrt
<OGRVRTDataSource>
    <OGRVRTLayer name="temp_disp">
        <SrcDataSource>temp_disp.csv</SrcDataSource>
        <GeometryType>wkbPoint</GeometryType>
        <LayerSRS>WGS84</LayerSRS>
        <GeometryField encoding="PointFromColumns" x="LON" y="LAT" />
        <Field name="DISP" src="DISP" type="real" />
        <Field name="COHER" src="COHER" type="real" />
    </OGRVRTLayer>
</OGRVRTDataSource>
EOF

OUT="disp_"`basename $IN '.csv'`"_"$DATUM"T0000+0100.tif"
gdal_rasterize -a DISP -tr 0.0005 0.0005 -l temp_disp -a_nodata -32768 -a_srs EPSG:4326 -where 'COHER>0.2' temp_disp.vrt $OUT

cd ..
mv temp_$IN/$OUT .
rm -r temp_$IN