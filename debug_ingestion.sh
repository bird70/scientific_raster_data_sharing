#!/bin/bash
# Debug Step Functions Ingestion Pipeline

export AWS_PROFILE=DEVcloud

STATE_MACHINE_ARN="arn:aws:states:ap-southeast-2:123456789101:stateMachine:cloud-scientific-raster-sharing-ingestion-pipeline"
BUCKET="cloud-scientific-raster-sharing-raw-2e6c448c"
TEST_FILE="ingestion/test-file_MC_SST.nc"

echo "=== Starting Step Functions Execution ==="

# Start execution
TIMESTAMP=$(date +%s)
EXECUTION_NAME="debug-test-$TIMESTAMP"
EVENT_TIME=$(date -u +"%Y-%m-%dTH:%M:%S.%3NZ")
INPUT="{\"bucket\": \"$BUCKET\", \"key\": \"$TEST_FILE\", \"metadata\": {\"source\": \"Debug script\", \"event_time\": \"$EVENT_TIME\"}}"

echo "Starting execution: $EXECUTION_NAME"
echo "Input: $INPUT"

EXECUTION=$(aws stepfunctions start-execution --state-machine-arn "$STATE_MACHINE_ARN" --name "$EXECUTION_NAME" --input "$INPUT")
EXECUTION_ARN=$(echo "$EXECUTION" | jq -r '.executionArn')

echo "Execution ARN: $EXECUTION_ARN"
echo "Waiting for execution to complete..."

# Wait for completion (max 5 minutes)
MAX_WAIT=300
WAITED=0
while [ $WAITED -lt $MAX_WAIT ]; do
    sleep 10
    WAITED=$((WAITED + 10))
    STATUS=$(aws stepfunctions describe-execution --execution-arn "$EXECUTION_ARN" | jq -r '.status')
    echo "Status: $STATUS (waited ${WAITED}s)"
    if [ "$STATUS" != "RUNNING" ]; then
        break
    fi
done

echo ""
echo "=== Execution Status ==="
aws stepfunctions describe-execution --execution-arn "$EXECUTION_ARN"

echo ""
echo "=== Execution History ==="
HISTORY=$(aws stepfunctions get-execution-history --execution-arn "$EXECUTION_ARN" --max-items 20)
echo "$HISTORY"

# Check for Lambda failures
LAMBDA_FAILURES=$(echo "$HISTORY" | jq -r '.events[] | select(.type == "TaskFailed" and .taskFailedEventDetails.resourceType == "lambda")')
if [ -n "$LAMBDA_FAILURES" ]; then
    echo ""
    echo "=== Lambda Zarr Conversion Logs ==="
    aws logs tail /aws/lambda/cloud-scientific-raster-sharing-zarr-converter --since 10m --format short
fi

# Check for ECS COG generation failures
ECS_FAILURES=$(echo "$HISTORY" | jq -r '.events[] | select(.type == "TaskFailed" and .taskFailedEventDetails.resourceType == "ecs")')
if [ -n "$ECS_FAILURES" ]; then
    echo ""
    echo "=== ECS COG Generation Logs ==="
    aws logs tail /ecs/cog-generation --since 10m --format short
fi

echo ""
echo "=== Debug Complete ==="
echo "Execution ARN: $EXECUTION_ARN"