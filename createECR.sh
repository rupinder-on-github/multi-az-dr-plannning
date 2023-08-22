#!/bin/bash

while getopts ":o:n:s:c:" opt; do
  case $opt in
    o) OLD_CLUSTER_NAME="$OPTARG";;
    n) NEW_CLUSTER_NAME="$OPTARG";;
    s) SUBNET_GROUP_NAME="$OPTARG";;
    c) CLUSTER_MODE="$OPTARG";;
    \?) echo "Invalid option: -$OPTARG" >&2; exit 1;;
    :) echo "Option -$OPTARG requires an argument." >&2; exit 1;;
  esac
done

if [ -z "$OLD_CLUSTER_NAME" ] || [ -z "$NEW_CLUSTER_NAME" ] || [ -z "$SUBNET_GROUP_NAME" ] || [ -z "$CLUSTER_MODE" ]; then
  echo "Usage: $0 -o <old_cluster_name> -n <new_cluster_name> -s <subnet_group_name> -c <true|false>"
  exit 1
fi

BUCKET_NAME="my-elasticache-backup-bucket"
REDIS_ENGINE_VERSION="6.x"  # Specify your desired Redis version here

# Create an S3 bucket for backup storage
aws s3api create-bucket --bucket $BUCKET_NAME

# Take a backup of the old Redis cluster
aws elasticache create-snapshot --snapshot-name $OLD_CLUSTER_NAME-backup --replication-group-id $OLD_CLUSTER_NAME

# Wait for the snapshot to complete
aws elasticache wait snapshot-available --snapshot-name $OLD_CLUSTER_NAME-backup

# Copy the snapshot to the S3 bucket
aws s3 cp s3://$BUCKET_NAME/$OLD_CLUSTER_NAME-backup/ $OLD_CLUSTER_NAME-backup/

# Determine the cluster mode configuration
if [ "$CLUSTER_MODE" = "true" ]; then
  CLUSTER_MODE_CONFIG="--num-node-groups 1 --replicas-per-node-group 1"
else
  CLUSTER_MODE_CONFIG="--num-node-groups 1 --replicas-per-node-group 0"
fi

# Create the new Redis cluster with the specific Redis engine version, subnet group, and cluster mode
aws elasticache create-replication-group \
  --replication-group-id $NEW_CLUSTER_NAME \
  --replication-group-description "New Redis Cluster" \
  --cache-node-type cache.m5.large \
  --engine redis \
  --engine-version $REDIS_ENGINE_VERSION \
  --cache-parameter-group default.redis5.0 \
  --snapshot-name $OLD_CLUSTER_NAME-backup \
  --automatic-failover-enabled \
  --cache-subnet-group-name $SUBNET_GROUP_NAME \
  $CLUSTER_MODE_CONFIG

# Wait for the new cluster to be available
aws elasticache wait replication-group-available --replication-group-id $NEW_CLUSTER_NAME

echo "Backup and restore completed successfully!"
