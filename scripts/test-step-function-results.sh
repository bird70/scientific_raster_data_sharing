#!/bin/bash

# Test Step Function execution results
set -e

echo "🔍 Testing Step Function execution results..."

# Get bucket names
RAW_BUCKET=$(aws s3 ls | grep "cloud-scientific-raster-sharing-raw" | awk '{print $3}')
COG_BUCKET=$(aws s3 ls | grep "cloud-scientific-raster-sharing-cog" | awk '{print $3}')
ZARR_BUCKET=$(aws s3 ls | grep "cloud-scientific-raster-sharing-zarr" | awk '{print $3}')
STAC_BUCKET=$(aws s3 ls | grep "cloud-scientific-raster-sharing-stac" | awk '{print $3}')

echo "Buckets found:"
echo "  Raw: $RAW_BUCKET"
echo "  COG: $COG_BUCKET" 
echo "  Zarr: $ZARR_BUCKET"
echo "  STAC: $STAC_BUCKET"

# Check S3 buckets for processed data
echo -e "\n1. Checking S3 buckets for processed data..."

echo "Raw bucket contents:"
aws s3 ls s3://$RAW_BUCKET --recursive | head -10

echo -e "\nCOG bucket contents:"
aws s3 ls s3://$COG_BUCKET --recursive | head -10

echo -e "\nZarr bucket contents:"
aws s3 ls s3://$ZARR_BUCKET --recursive | head -10

echo -e "\nSTAC bucket contents:"
aws s3 ls s3://$STAC_BUCKET --recursive | head -10

# Check OpenSearch for STAC items
echo -e "\n2. Checking OpenSearch for STAC items..."
OPENSEARCH_ENDPOINT=$(aws opensearch describe-domains --domain-names cloud-sciraster-stac --query 'DomainStatusList[0].Endpoints.vpc' --output text)

if [ "$OPENSEARCH_ENDPOINT" != "None" ]; then
    echo "OpenSearch endpoint: $OPENSEARCH_ENDPOINT"
    
    # Count total documents
    echo "Total STAC items in OpenSearch:"
    curl -s "https://$OPENSEARCH_ENDPOINT/stac/_count" | jq '.count // "Error"'
    
    # Get sample documents
    echo -e "\nSample STAC items:"
    curl -s "https://$OPENSEARCH_ENDPOINT/stac/_search?size=3" | jq '.hits.hits[]._source.id // "No items found"'
else
    echo "❌ OpenSearch endpoint not found"
fi

# Test API endpoints with processed data
echo -e "\n3. Testing API endpoints..."
ALB_URL="http://cloud-sciraster-alb-1214303046.ap-southeast-2.elb.amazonaws.com"

echo "Collections endpoint:"
curl -s "$ALB_URL/api/collections" | jq '.'

echo -e "\nTesting timeseries endpoint (if collections exist):"
COLLECTIONS=$(curl -s "$ALB_URL/api/collections" | jq -r '.collections[]?' | head -1)

if [ ! -z "$COLLECTIONS" ]; then
    echo "Testing with collection: $COLLECTIONS"
    curl -s "$ALB_URL/api/timeseries?lon=150&lat=-33&start=2024-01-01T00:00:00Z&end=2024-12-31T23:59:59Z&variable=temperature" | jq '.'
else
    echo "No collections found - data may not be processed yet"
fi

# Check Step Function execution status
echo -e "\n4. Checking recent Step Function executions..."
aws stepfunctions list-executions --state-machine-arn $(aws stepfunctions list-state-machines --query 'stateMachines[?contains(name, `cloud-scientific-raster-sharing`)].stateMachineArn' --output text) --max-items 5 --query 'executions[].{Name:name,Status:status,StartDate:startDate}' --output table

echo -e "\n✅ Step Function results check complete!"
echo ""
echo "If no data found:"
echo "1. Check Step Function execution logs in CloudWatch"
echo "2. Verify input data was uploaded to raw bucket"
echo "3. Check Lambda function logs for errors"