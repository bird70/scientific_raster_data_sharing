#!/bin/bash
set -e

REGION="ap-southeast-2"
REPO_NAME="cloud-scientific-raster-sharing-repo"
STATE_MACHINE_ARN="arn:aws:states:ap-southeast-2:123456789101:stateMachine:cloud-scientific-raster-sharing-ingestion-pipeline"

echo "=== Cleaning up resources before terraform destroy ==="

# 1. Delete ECR images
echo "Deleting ECR images..."
IMAGE_IDS=$(aws ecr list-images --repository-name $REPO_NAME --region $REGION --query 'imageIds[*]' --output json 2>/dev/null || echo "[]")
if [ "$IMAGE_IDS" != "[]" ]; then
  aws ecr batch-delete-image \
    --repository-name $REPO_NAME \
    --image-ids "$IMAGE_IDS" \
    --region $REGION
  echo "✓ ECR images deleted"
else
  echo "✓ No ECR images to delete"
fi

# 2. Stop Step Functions executions
echo "Stopping Step Functions executions..."
EXECUTIONS=$(aws stepfunctions list-executions \
  --state-machine-arn $STATE_MACHINE_ARN \
  --status-filter RUNNING \
  --region $REGION \
  --query 'executions[*].executionArn' \
  --output text 2>/dev/null || echo "")

if [ -n "$EXECUTIONS" ]; then
  for exec_arn in $EXECUTIONS; do
    aws stepfunctions stop-execution \
      --execution-arn $exec_arn \
      --region $REGION
    echo "✓ Stopped execution: $exec_arn"
  done
else
  echo "✓ No running executions to stop"
fi

echo "=== Cleanup complete! Now run: terraform destroy ==="