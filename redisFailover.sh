#!/bin/bash

while getopts "c:z:r:" opt; do
  case $opt in
    c) CLUSTER_NAME="$OPTARG";;
    z) TARGET_AZ="$OPTARG";;
    r) REGION="$OPTARG";;
    \?) echo "Invalid option: -$OPTARG" >&2; exit 1;;
    :) echo "Option -$OPTARG requires an argument." >&2; exit 1;;
  esac
done

# Check if required parameters are provided
if [[ -z $CLUSTER_NAME || -z $TARGET_AZ || -z $REGION ]]; then
  echo "Usage: $0 -c <cluster> -z <target-az> -r <region>"
  exit 1
fi

PRIMARY_CLUSTER_ID=""
REPLICA_AZ=""

# Get a list of replicas and their Availability Zones
REPLICA_LIST=$(aws elasticache describe-replication-groups \
  --replication-group-id "$CLUSTER_NAME" \
  --query "ReplicationGroup.NodeGroups[0].NodeGroupMembers[?CurrentRole=='primary'].PreferredAvailabilityZone" \
  --output text \
  --region "$REGION")

# Iterate through the list of replicas to find the one in the target AZ
while IFS= read -r replica; do
  if [ "$replica" == "$TARGET_AZ" ]; then
    PRIMARY_CLUSTER_ID=$(aws elasticache describe-replication-groups \
      --replication-group-id "$CLUSTER_NAME" \
      --query "ReplicationGroup.NodeGroups[0].NodeGroupMembers[?CurrentRole=='primary'].CacheClusterId" \
      --output text \
      --region "$REGION")
    break
  fi
done <<< "$REPLICA_LIST"

if [ -z "$PRIMARY_CLUSTER_ID" ]; then
  echo "No primary instance found in target AZ $TARGET_AZ."
  exit 1
fi

try_failover() {
  aws elasticache move-replica \
    --replication-group-id "$CLUSTER_NAME" \
    --source-replica "$PRIMARY_CLUSTER_ID" \
    --destination-availability-zone "$TARGET_AZ" \
    --region "$REGION"

  if [ $? -ne 0 ]; then
    echo "Failed to initiate failover."
    exit 1
  fi

  # Wait for the failover to complete
  echo "Waiting for failover to complete..."
  aws elasticache wait cache-cluster-available \
    --cache-cluster-id "$CLUSTER_NAME" \
    --region "$REGION"

  echo "Failover complete. New primary in $TARGET_AZ."
}

try_failover

echo "Done!"
