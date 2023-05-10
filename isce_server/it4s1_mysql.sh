#!/bin/bash
#this should run the mysql query through python
query=$1
outfile=$2

source ~/sw/it4s1/it4s1_skirit_moduleload

cat << EOF > $outfile.py
from sqlalchemy import create_engine

engine = create_engine(
     'mysql://{usr}:{psswd}@{hst}/{dbname}'.format(
 usr='it4s1user',
 psswd='sentineloshka',
 hst='s1metadb.cesnet.cz',
 dbname='it4s1_metadb',
 )
)

sqlQuery = "`cat $query`"
outfile = "$outfile"

connection = engine.connect()
result = connection.execute(sqlQuery)
o = open(outfile,"w+")
for row in result:
    o.write(row[0]+"\n")
o.close()
EOF

python3 $outfile.py

rm $query 2>/dev/null
rm $outfile.py
