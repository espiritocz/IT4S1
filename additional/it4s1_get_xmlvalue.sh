#!/bin/bash

#(c) 2017 Milan Lazecky, IT4Innovations


if [ -z $1 ]; then
 echo "This script will get xml value of given parameter."
 echo "Usage: "`basename $0`" XMLPARAMETER XMLFILE"
 echo "  e.g. "`basename $0`" rangepixelsize master.xml"
 exit
fi

PAR=$1
FILE=$2
grep -A1 $PAR $FILE | grep -oPm1 "(?<=<value>)[^<]+"
