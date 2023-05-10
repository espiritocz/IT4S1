# This is to start SalsIt processing.
# please run it from some CROP folder!

# Milan Lazecky and Ivana Hlavacova, 2018

if [ ! -z $2 ]; then
 slat=$1
 slon=$2
else
 echo "note: by providing LAT LON parameters, you may choose stable ref area"
 echo "e.g. it4s1_salsit_ps.sh 36.846 -4.455"
 slat=''
 slon=''
fi


if [ ! `pwd | rev | cut -d '/' -f1 | rev | cut -c 1-4` == "CROP" ]; then
 echo "This should be run from a CROP folder. Exiting"; exit
fi

#module load Octave 2>/dev/null
cp /home/laz048/IT4S1/matlab/salsit_PS.m .
sed '/^path/d' /home/laz048/IT4S1/matlab/salsit/salsit_LS.m >> salsit_PS.m

#for customized (favourite) parameters
if [ ! -f set_params_LS_special.m ]; then
cp /home/laz048/IT4S1/matlab/salsit_params_`whoami` set_params_LS_special.m
fi

#provide lat lon of stable (reference) area
if [ ! -z $slat ]; then
 echo $slat","$slon > stablecoordlatlon.txt
fi

#Correction for local path (in it4i case..)
sed -i 's/\/home\/'`whoami`'\/TEMP/\/scratch\/temp\/'`whoami`'/' selpsc.in

echo "maybe it will not finish?"
echo "if not, check csv and run this merge command"
echo "paste -d "," resultLS_par_first.csv resultLS_mov_first.csv > salsit_result.csv"
octave-cli -q salsit_PS.m #2>/dev/null
cd results
paste -d "," resultLS_par_first.csv resultLS_mov_first.csv > salsit_result.csv
cp salsit_results.csv ../.
