#!/bin/bash

# Upload test data to trigger Step Function
set -e

echo "📤 Uploading test data to trigger Step Function..."

# Get raw bucket name
RAW_BUCKET=$(aws s3 ls | grep "cloud-scientific-raster-sharing-raw" | awk '{print $3}')

if [ -z "$RAW_BUCKET" ]; then
    echo "❌ Raw bucket not found"
    exit 1
fi

echo "Raw bucket: $RAW_BUCKET"

# Check if test data exists locally
if [ -f "data/your-data.nc" ]; then
    echo "✅ Found local test data: data/your-data.nc"
    
    # Upload to S3 (this should trigger the Step Function)
    echo "Uploading to S3..."
    aws s3 cp data/your-data.nc s3://$RAW_BUCKET/test-data/your-data.nc
    
    echo "✅ Upload complete!"
    echo ""
    echo "Step Function should be triggered automatically."
    echo "Wait 2-3 minutes, then run: ./scripts/test-step-function-results.sh"
    
else
    echo "❌ No test data found at data/your-data.nc"
    echo ""
    echo "To create test data:"
    echo "1. Add a NetCDF file to data/ directory"
    echo "2. Or download sample data:"
    echo "   wget -O data/sample.nc 'https://example.com/sample-data.nc'"
    echo "3. Then run this script again"
fi

# Show recent Step Function executions
echo -e "\nRecent Step Function executions:"
aws stepfunctions list-executions --state-machine-arn $(aws stepfunctions list-state-machines --query 'stateMachines[?contains(name, `cloud-scientific-raster-sharing`)].stateMachineArn' --output text) --max-items 3 --query 'executions[].{Name:name,Status:status,StartDate:startDate}' --output table 2>/dev/null || echo "No executions found"