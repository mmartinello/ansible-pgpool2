#!/bin/bash

# Replicates users from PostgreSQL to Pgpool

# Configuration
PASSWD_FILE=/etc/pgpool-II/pool_passwd
TEMP_FILE=/tmp/users.tmp
POSTGRES_HOST=postgres1
POSTGRES_USER=postgres
pgpool_nodes=("proxy1" "proxy2" "proxy3")

# Fetch data from Postgres and save them to temporary file
psql -c "select rolname,rolpassword from pg_authid;" "host=$POSTGRES_HOST user=$POSTGRES_USER dbname=postgres" > $TEMP_FILE

# then go through the file to remove/add the entry in pool_passwd file
cat $TEMP_FILE | awk 'BEGIN {FS="|"}{print $1" "$2}' | grep md5 | while read f1 f2
do
 echo "setting passwd of $f1 in $PASSWD_FILE"
 # delete the line if exits
 sed -i -e "/^${f1}:/d" $PASSWD_FILE
 echo $f1:$f2 >> $PASSWD_FILE
done

# Copy files to other nodes and reload Pgpool2
for node in ${pgpool_nodes[@]}; do
    echo "Copying passwd file to ${node} ..."
    scp -q $PASSWD_FILE ${node}:$PASSWD_FILE
    echo "Reloading Pgpool2 on ${node} ..."
    ssh -q ${node} systemctl reload pgpool
done
