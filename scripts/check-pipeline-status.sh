#!/bin/bash

# Check Pipeline Status
# Diagnose what went wrong with the pipeline execution

export AWS_PROFILE=DEVcloud
EXECUTION_ARN="arn:aws:states:ap-southeast-2:123456789101:execution:cloud-scientific-raster-sharing-ingestion-pipeline:2733f348-c075-41fa-b49d-08789215304a"

echo "========================================="
echo "Pipeline Execution Diagnostics"
echo "========================================="
echo ""

# Check if Zarr file was created
echo "1. Checking if Zarr file exists..."
aws s3 ls s3://cloud-scientific-raster-sharing-zarr-2e6c448c/zarr/A2002070120230731_MC_SST_std_coastal_v05.zarr --profile $AWS_PROFILE
if [ $? -eq 0 ]; then
    echo "✓ Zarr file exists"
else
    echo "✗ Zarr file NOT found"
fi
echo ""

# Check Zarr conversion logs
echo "2. Zarr Conversion Logs (last 50 lines):"
echo "----------------------------------------"
aws logs tail /ecs/zarr-conversion --since 30m --profile $AWS_PROFILE 2>/dev/null | tail -50
echo ""

# Check COG generation logs
echo "3. COG Generation Logs (last 50 lines):"
echo "----------------------------------------"
aws logs tail /ecs/cog-generation --since 30m --profile $AWS_PROFILE 2>/dev/null | tail -50
echo ""

# Check Step Functions execution details
echo "4. Step Functions Execution Status:"
echo "-----------------------------------"
aws stepfunctions describe-execution \
  --execution-arn $EXECUTION_ARN \
  --profile $AWS_PROFILE \
  --query '{status: status, startDate: startDate, stopDate: stopDate}' \
  --output json
echo ""

# Get failed task details
echo "5. Failed Task Details:"
echo "----------------------"
aws stepfunctions get-execution-history \
  --execution-arn $EXECUTION_ARN \
  --profile $AWS_PROFILE \
  --query 'events[?type==`TaskFailed`].{id: id, type: type, error: taskFailedEventDetails.error, cause: taskFailedEventDetails.cause}' \
  --output json | head -100
echo ""

echo "========================================="
echo "Diagnostic Complete"
echo "========================================="
