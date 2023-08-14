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

# Get the current primary's AZ
PRIMARY_AZ=$(aws elasticache describe-replication-groups \
  --replication-group-id "$CLUSTER_NAME" \
  --query "ReplicationGroups[0].PrimaryAvailabilityZone" \
  --output text \
  --region "$REGION")

if [ -z "$PRIMARY_AZ" ]; then
  echo "Failed to retrieve primary's Availability Zone."
  exit 1
fi

# Find the replica in the target AZ
REPLICA_AZ=$(aws elasticache describe-replication-groups \
  --replication-group-id "$CLUSTER_NAME" \
  --query "ReplicationGroups[0].MemberClusters[?AvailabilityZone=='$TARGET_AZ']" \
  --output text \
  --region "$REGION")

if [ -z "$REPLICA_AZ" ]; then
  echo "No replica found in target AZ $TARGET_AZ."
  exit 1
fi

try_failover() {
  aws elasticache move-replica \
    --replication-group-id "$CLUSTER_NAME" \
    --source-replica "$REPLICA_AZ" \
    --destination-availability-zone "$PRIMARY_AZ" \
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
