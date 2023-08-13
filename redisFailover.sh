#!/bin/bash

while getopts "c:a:z:r:" opt; do
  case $opt in
    c) CLUSTER_NAME="$OPTARG";;
    a) ACTION="$OPTARG";;
    z) FAILOVER_AZ="$OPTARG";;
    r) REGION="$OPTARG";;
    \?) echo "Invalid option: -$OPTARG" >&2; exit 1;;
    :) echo "Option -$OPTARG requires an argument." >&2; exit 1;;
  esac
done

# Check if required parameters are provided
if [[ -z $CLUSTER_NAME || -z $ACTION || -z $FAILOVER_AZ || -z $REGION ]]; then
  echo "Usage: $0 -c <cluster> -a <action> -z <az> -r <region>"
  exit 1
fi

if [[ $ACTION != "failover" && $ACTION != "failback" ]]; then
  echo "Invalid action parameter. Use 'failover' or 'failback'."
  exit 1
fi

# Check if AZ is valid
VALID_AZS=("us-east-2a" "us-east-2b" "us-east-2c")
if [[ ! " ${VALID_AZS[@]} " =~ " $FAILOVER_AZ " ]]; then
  echo "Invalid AZ parameter. Choose from: ${VALID_AZS[@]}"
  exit 1
fi

try_failover() {
  aws elasticache modify-replication-group \
    --replication-group-id "$CLUSTER_NAME" \
    --replication-group-region "$REGION" \
    --primary-replication-group-id "$CLUSTER_NAME-replica-$FAILOVER_AZ" \
    --apply-immediately

  if [ $? -ne 0 ]; then
    echo "Failed to initiate failover."
    exit 1
  fi

  # Wait for the promotion to complete
  echo "Waiting for the promotion to complete..."
  aws elasticache wait cache-cluster-available \
    --cache-cluster-id "$CLUSTER_NAME" \
    --region "$REGION"

  echo "Failover complete. New primary in $FAILOVER_AZ."
}

try_failback() {
  aws elasticache modify-replication-group \
    --replication-group-id "$CLUSTER_NAME" \
    --replication-group-region "$REGION" \
    --primary-replication-group-id "$CLUSTER_NAME" \
    --apply-immediately

  if [ $? -ne 0 ]; then
    echo "Failed to initiate failback."
    exit 1
  fi

  # Wait for the failback to complete
  echo "Waiting for failback to complete..."
  aws elasticache wait cache-cluster-available \
    --cache-cluster-id "$CLUSTER_NAME" \
    --region "$REGION"

  echo "Failback complete. Original primary restored."
}

if [ "$ACTION" = "failover" ]; then
  try_failover
elif [ "$ACTION" = "failback" ]; then
  try_failback
fi

echo "Done!"
