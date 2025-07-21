#!/bin/bash
REGION_VIP=$1
NODE_ID=$2
PORT=9898
USER="pcpadmin"

if [ -z "$REGION_VIP" ] || [ -z "$NODE_ID" ]; then
  echo "Usage: $0 <REGION_VIP> <NODE_ID>"
  exit 1
fi

ROLE=$(pcp_node_info -h $REGION_VIP -p $PORT -U $USER -n $NODE_ID | grep -o 'primary\|standby')

if [ "$ROLE" = "primary" ]; then
  echo "[ERROR] Node $NODE_ID is primary! Switchover must occur before maintenance."
  exit 1
fi

echo "[INFO] Detaching node $NODE_ID from Pgpool..."
pcp_detach_node -h $REGION_VIP -p $PORT -U $USER -n $NODE_ID

echo "[INFO] Stopping PostgreSQL..."
systemctl stop postgresql-15
