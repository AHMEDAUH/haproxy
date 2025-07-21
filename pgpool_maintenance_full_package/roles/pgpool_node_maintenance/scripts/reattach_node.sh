#!/bin/bash
REGION_VIP=$1
NODE_ID=$2
PORT=9898
USER="pcpadmin"
if [ -z "$REGION_VIP" ] || [ -z "$NODE_ID" ]; then
 echo "Usage: $0 <REGION_VIP> <NODE_ID>"
 exit 1
fi
rm -rf /var/lib/pgsql/15/data/*
pgbackrest --stanza=main --delta restore
touch /var/lib/pgsql/15/data/standby.signal
chown postgres:postgres /var/lib/pgsql/15/data/standby.signal
systemctl start postgresql-15
pcp_attach_node -h $REGION_VIP -p $PORT -U $USER -n $NODE_ID
