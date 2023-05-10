#it4s1_csv2floreon.sh input_ps_or_sb.csv 2017-01-01
LASTDATES=5 #last 5 measurements will be selected
OUT=output_floreon #basename for output file

module load GDAL Octave PROJ
csvfile=$1
enddate=$2

#check the date:
#if [ `echo $enddate | cut -d '-' -f1` -lt 2016 ]; then
# echo "For better results... well actually why not"
# exit
#fi
cp $csvfile tmp_csv.csv
csvfile=tmp_csv.csv
head -n1 $csvfile > tmpheader.txt
#echo 25-May-2017 > tmpenddate.txt
echo $enddate > tmpenddate.txt

cat <<EOF > tmpmain.vrt
<OGRVRTDataSource>
    <OGRVRTLayer name="`basename $csvfile .csv`">
        <SrcDataSource>$csvfile</SrcDataSource>
        <GeometryType>wkbPoint</GeometryType>
        <LayerSRS>WGS84</LayerSRS>
        <GeometryField encoding="PointFromColumns" x="LON" y="LAT" z="HEIGHT"/>
        <Field name="VEL" src="VEL" type="real" />
        <Field name="COHER" src="COHER" type="real" />
EOF
cat <<EOF > tmptail.vrt
    </OGRVRTLayer>
</OGRVRTDataSource>
EOF

cat <<EOF > tmpextract.py
import csv
import datetime
with open('tmpheader.txt', 'rb') as csvfile:
    mx = csv.reader(csvfile, delimiter=',')
    head=list(mx)
mx=head[0]
dates=[]
for date in mx:
    if "-2" in date:
        dates.append(datetime.datetime.strptime(date,'%d-%b-%Y'))
with open('tmpenddate.txt', 'rb') as csvfile:
    a = csv.reader(csvfile)
    b = list(a)
#enddate = datetime.datetime.strptime(b[0][0],'%d-%b-%Y')
enddate = datetime.datetime.strptime(b[0][0],'%Y-%m-%d')
#update - find the closest date
enddate = sorted(dates, key=lambda d: abs(enddate - d))[0]
#dates.index(enddate)
trimes = enddate-datetime.timedelta(days=90)
trimes = sorted(dates, key=lambda d: abs(trimes - d))[0]
jedenmes = enddate-datetime.timedelta(days=30)
jedenmes = sorted(dates, key=lambda d: abs(jedenmes - d))[0]


for i in range(dates.index(trimes),dates.index(enddate)):
    with open('tmp_90d.txt',"a") as file:
        file.write(dates[i].strftime('%Y-%m-%d'))
        file.write('\n')
for i in range(dates.index(jedenmes),dates.index(enddate)):
    with open('tmp_30d.txt',"a") as file:
        file.write(dates[i].strftime('%Y-%m-%d'))
        file.write('\n')
for i in range(dates.index(enddate)-$LASTDATES,dates.index(enddate)):
    with open('tmp_lastdates.txt',"a") as file:
        file.write(dates[i].strftime('%Y-%m-%d'))
        file.write('\n')
for i in range(0,len(dates)):
    with open('tmp_dates_dbY.txt',"a") as file:
        file.write(dates[i].strftime('%d-%b-%Y'))
        file.write('\n')
#for i in range(dates.index(trimes),dates.index(enddate)):
#    with open('tmp3mes.txt',"a") as file:
#        file.write(dates[i].strftime('%d-%b-%Y'))
#        file.write('\n')
#for i in range(dates.index(jedenmes),dates.index(enddate)):
#    with open('tmp1mes.txt',"a") as file:
#        file.write(dates[i].strftime('%d-%b-%Y'))
#        file.write('\n')
#for i in range(dates.index(enddate)-5,dates.index(enddate)):
#    with open('tmplastdates.txt',"a") as file:
#        file.write(dates[i].strftime('%d-%b-%Y'))
#        file.write('\n')
EOF
python tmpextract.py

#rm tmpenddate.txt tmpheader.txt tmpextract.py

##last 5 measurements
#cp tmpmain.vrt tmpfinal.vrt
#cast=""
#lineone=`head -n1 tmplastdates.txt`
#lineoneDD=DD`echo $lineone | sed 's/-/BB/g'`
#for line in `cat tmplastdates.txt`; do
# linenew=DD`echo $line | sed 's/-/BB/g'`
# echo '        <Field name="'$linenew'" src="'$line'" type="real" />' >> tmpfinal.vrt
##making the first value zero
# cast=$cast", cast("$linenew"-"$lineoneDD" as integer) as "$linenew
#done

#convert all to %Y-%m-%d
cp tmpmain.vrt tmpfinal.vrt
cast=""
for line in `cat tmp_dates_dbY.txt`; do
 #tricking through DD and BB to make ogr2ogr work (later)
 lineout=DD`date -d$line +%Y-%m-%d | sed 's/-/BB/g'`
 echo '        <Field name="'$lineout'" src="'$line'" type="real" />' >> tmpfinal.vrt
 cast=$cast", cast("$lineout" as integer)"
done
# as $lineout
#done

#count 1 month and 3 month medians
for N in 30 90; do
 cp tmpmain.vrt med_$N'd.vrt'
 sql="SELECT "
 for line in `cat tmp_$N'd.txt'`; do
  linenew=DD`echo $line | sed 's/-/BB/g'`
  echo '        <Field name="'$linenew'" src="'`LANG=C date -d $line +%d-%b-%Y`'" type="real" />' >> med_$N'd.vrt'
  sql=$sql" "$linenew", "
 done
 cat tmptail.vrt >> med_$N'd.vrt'
 sql=`echo $sql | rev | cut -c 2- | rev`" from "`basename $csvfile .csv`
 ogr2ogr -f CSV med_$N'd.csv' med_$N'd.vrt' -sql "$sql"
 sed -i '1d' med_$N'd.csv'
 #sed -i '1s/BB/-/g' avg$N'm.csv'
 #sed -i '1s/DD//g' avg$N'm.csv'
 # will reference the values towards median of first three samples
 octave-cli -q --eval "a=csvread('med_"$N"d.csv');b=a-median(a(:,[1 2 3]),2);c=round(median(b,2));csvwrite('med_"$N"d.col',c)"
 echo MED_$N'D' > med_$N'd.out'
 cat med_$N'd.col' >> med_$N'd.out'
 paste $csvfile med_$N'd.out' -d ',' > $csvfile'tmp'
 mv $csvfile'tmp' $csvfile
 echo '        <Field name="MED_'$N'D" src="MED_'$N'D" type="integer" />' >> tmpfinal.vrt
done
cat tmptail.vrt >> tmpfinal.vrt

#using casting here - should be rounding but we want result in 1 mm/year tolerance
sql="SELECT cast(VEL AS integer) as VEL_TOTAL, cast(COHER*100 as integer) as COH, MED_30D, MED_90D"$cast" from "`basename $csvfile .csv`

ogr2ogr -s_srs EPSG:4326 -t_srs EPSG:3857 -f CSV tmpfinal.csv tmpfinal.vrt -lco GEOMETRY=AS_XY -sql "$sql"
sql=`echo $sql | sed 's/SELECT/SELECT cast(X as integer), cast(Y as integer),/' | sed 's/tmp_csv/tmpfinal/' | sed 's/VEL AS/VEL_TOTAL as/' | sed 's/COHER\*100/COH/'`
ogr2ogr -f CSV $OUT.csv tmpfinal.csv -sql "$sql"
sed -i '1s/BB/-/g' $OUT.csv
sed -i '1s/DD//g' $OUT.csv

#prepare metadata
META=$OUT.meta
echo "File name: "$OUT.csv > $META
echo "Description: Result of Sentinel-1 PS InSAR processing based on IT4S1 approach. On-demand processing using "`cat tmp_dates_dbY.txt | wc -l`" images." >> $META
echo "Coordinate system: EPSG:3857" >> $META
#bounding box
gdal_rasterize -a VEL -tr 0.001 0.001 -l tmp_csv -a_srs EPSG:4326 tmpfinal.vrt tmpfinal.tif >/dev/null
gdalwarp -s_srs EPSG:4326 -t_srs EPSG:3857 tmpfinal.tif tmpfinal_3857.tif >/dev/null
gdalinfo tmpfinal_3857.tif | grep "Corner Coor" -A5 | sed 's/Corner Coordinates/Bounding Box/' >> $META
echo "Reference date: INEEDTOFINISHTHIS" >> $META
echo "Selected end date: "$enddate >> $META
echo "Number of samples for visualization: "$LASTDATES >> $META
a="";for x in `cat tmp_lastdates.txt`; do a=$a","$x; done
echo "Dates of samples for visualization: "`echo $a | cut -c 2-` >> $META
echo "Table contents (id,column_name,unit,description):" >> $META
echo "1,X,meter,X coordinate" >> $META
echo "2,Y,meter,Y coordinate" >> $META
echo "3,VEL_TOTAL,mm/year,Estimated total velocity in the dataset" >> $META
echo "4,COH,%,Coherence (quality) of the given point" >> $META
echo "5,MED_30D,mm,Median aggregate of 30 days before the end date" >> $META
echo "6,MED_90D,mm,Median aggregate of 90 days before the end date" >> $META
i=7;for datum in `cat tmp_dates_dbY.txt`; do 
 echo $i","$datum",mm,LOS displacement value in given date" >> $META
 let i=$i+1
done

