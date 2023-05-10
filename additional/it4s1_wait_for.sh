#!/bin/bash
#This script waits to get some processing done, i.e. after a $FILE (finished) is created
#Second parameter will do the opposite - will create a file and wait until "someone" will delete it..
if [ -z $1 ]; then
 echo "Helping script to wait until given FILE is created. It will be removed afterwards."
 echo "Second parameter will do opposite - it will create a file and will wait until his removal."
 echo "Usage: "`basename $0`" FILE_to_finish [file_in_ISCESERVER_processing]"
 echo "  e.g. "`basename $0`" /path/to/finished [/path/to/isceserv_processing]"
 exit
fi

FILE=$1
if [ ! -z $2 ]; then ISCESER=$2; touch $ISCESER; fi
MUJLOGIN=`whoami`

echo "Waiting started at:"
date
echo "-------------"
if [ ! -z $ISCESER ]; then
 echo "..first waiting for ISCE server processing."
 while [ -f $ISCESER ]; do sleep 10; done
 echo "ISCE server processing finished at"
 date
 echo "-------------"
fi
while [ ! -f $FILE ]; do
 if [ `qstat | grep $MUJLOGIN | wc -l` -lt 1 ]; then echo "Processing not finished but there is nothing in queue :("; date; exit; fi
 sleep 10
done
echo "done. Finished at:"
date
echo ""
rm $FILE