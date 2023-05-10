#!/bin/bash
#(c) 2018 Milan Lazecky, IT4Innovations

WDIR=`pwd`/temp
COHTRE=0.2

#This is to unwrap an ifg using snaphu

if [ -z $7 ]; then
 echo "Usage: "`basename $0`" ifg_file coh_file width length [output_file] [bperp..only for TOPO]"
 echo "  e.g. "`basename $0`" ifg_filt coh.raw \`cat width.txt\` \`cat len.txt\` [ifg_filt_uw] [123.5]"
 exit
fi

PARJOB=24

ifg=$1
coh=$2
wid=$3
len=$4

if [ ! -z $5 ]; then OUT=$5; else OUT=$ifg"_uw"; fi
if [ ! -z $6 ]; then MODE="TOPO"; ADDSNAPHU="-b "$6; else MODE="DEFO"; ADDSNAPHU=""; fi

#preparing conf file
cat << EOF > snaphu_tmp.conf
# CONFIG FOR SNAPHU
# ----------------------------------------------------------------
#
# Command to call snaphu:
#
#	snaphu -f snaphu_tmp.conf tmp_phase.raw $len
STATCOSTMODE $MODE
INITMETHOD MCF
VERBOSE TRUE
CORRFILE $coh
OUTFILE $OUT
LOGFILE snaphu_tmp.log
INFILEFORMAT COMPLEX_DATA
CORRFILEFORMAT FLOAT_DATA
OUTFILEFORMAT FLOAT_DATA
TRANSMITMODE REPEATPASS
ORBITRADIUS 7068948.96
EARTHRADIUS 6365859.646
LAMBDA 0.0554658
NEARRANGE 800705.775054
DR 2.3295621
DA 15.6025058
RANGERES 2653030.6018487
AZRES 81.9312378
NCORRLOOKS 23.8
NTILEROW 50
NTILECOL          50
ROWOVRLP          50
COLOVRLP          50
NPROC             $PARJOB
TILECOSTTHRESH 500
EOF

echo "Unwrapping interferogram"
snaphu $ADDSNAPHU -f snaphu_tmp.conf $ifg $len #>/dev/null 2>/dev/null
cpxfiddle -w $wid -o sunraster -c jet -q normal -f r4 -M20/4 $OUT > $OUT.ras 2>/dev/null
echo "done"