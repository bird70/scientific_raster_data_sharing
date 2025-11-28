#!/bin/bash
# Comprehensive script to verify ingestion pipeline completion and data availability

set -e

echo "🔍 Verifying Ingestion Pipeline and Data Availability"
echo "═══════════════════════════════════════════════════════════"
echo ""

# Get configuration from Terraform
cd terraform
RAW_BUCKET=$(terraform output -raw raw_bucket_name 2>/dev/null)
ZARR_BUCKET=$(terraform output -raw zarr_bucket_name 2>/dev/null)
COG_BUCKET=$(terraform output -raw cog_bucket_name 2>/dev/null)
STAC_BUCKET=$(terraform output -raw stac_bucket_name 2>/dev/null)
STATE_MACHINE_ARN=$(terraform output -raw ingestion_state_machine_arn 2>/dev/null)
ALB_DNS=$(terraform output -raw alb_dns_name 2>/dev/null)
cd ..

if [ -z "$RAW_BUCKET" ]; then
    echo "❌ Error: Could not get bucket names from Terraform"
    exit 1
fi

echo "📊 Configuration:"
echo "  Raw Bucket: $RAW_BUCKET"
echo "  Zarr Bucket: $ZARR_BUCKET"
echo "  COG Bucket: $COG_BUCKET"
echo "  STAC Bucket: $STAC_BUCKET"
echo "  ALB DNS: $ALB_DNS"
echo ""

# Step 1: Check for uploaded files
echo "═══════════════════════════════════════════════════════════"
echo "STEP 1: Check for Uploaded NetCDF Files"
echo "═══════════════════════════════════════════════════════════"
echo ""

echo "📁 Files in raw bucket (ingestion/):"
aws s3 ls s3://$RAW_BUCKET/ingestion/ --recursive --human-readable 2>/dev/null || echo "  ⚠️  No files found or bucket not accessible"
echo ""

# Step 2: Check Step Functions executions
echo "═══════════════════════════════════════════════════════════"
echo "STEP 2: Check Step Functions Executions"
echo "═══════════════════════════════════════════════════════════"
echo ""

echo "📊 Recent executions (last 10):"
aws stepfunctions list-executions \
    --state-machine-arn $STATE_MACHINE_ARN \
    --max-results 10 \
    --query 'executions[*].[name,status,startDate]' \
    --output table 2>/dev/null || echo "  ⚠️  Could not fetch executions"
echo ""

# Count by status
SUCCEEDED=$(aws stepfunctions list-executions \
    --state-machine-arn $STATE_MACHINE_ARN \
    --status-filter SUCCEEDED \
    --max-results 100 \
    --query 'executions | length(@)' \
    --output text 2>/dev/null || echo "0")

FAILED=$(aws stepfunctions list-executions \
    --state-machine-arn $STATE_MACHINE_ARN \
    --status-filter FAILED \
    --max-results 100 \
    --query 'executions | length(@)' \
    --output text 2>/dev/null || echo "0")

RUNNING=$(aws stepfunctions list-executions \
    --state-machine-arn $STATE_MACHINE_ARN \
    --status-filter RUNNING \
    --max-results 100 \
    --query 'executions | length(@)' \
    --output text 2>/dev/null || echo "0")

echo "📈 Execution Summary:"
echo "  ✅ Succeeded: $SUCCEEDED"
echo "  ❌ Failed: $FAILED"
echo "  ⏳ Running: $RUNNING"
echo ""

# Step 3: Check processed files
echo "═══════════════════════════════════════════════════════════"
echo "STEP 3: Check Processed Files in S3"
echo "═══════════════════════════════════════════════════════════"
echo ""

echo "📁 Zarr files:"
ZARR_COUNT=$(aws s3 ls s3://$ZARR_BUCKET/zarr/ --recursive 2>/dev/null | wc -l)
if [ "$ZARR_COUNT" -gt 0 ]; then
    echo "  ✅ Found $ZARR_COUNT Zarr files"
    aws s3 ls s3://$ZARR_BUCKET/zarr/ --recursive --human-readable | head -10
else
    echo "  ❌ No Zarr files found"
fi
echo ""

echo "📁 COG files:"
COG_COUNT=$(aws s3 ls s3://$COG_BUCKET/cog/ --recursive 2>/dev/null | wc -l)
if [ "$COG_COUNT" -gt 0 ]; then
    echo "  ✅ Found $COG_COUNT COG files"
    aws s3 ls s3://$COG_BUCKET/cog/ --recursive --human-readable | head -10
else
    echo "  ❌ No COG files found"
fi
echo ""

echo "📁 STAC items:"
STAC_COUNT=$(aws s3 ls s3://$STAC_BUCKET/stac/ --recursive 2>/dev/null | wc -l)
if [ "$STAC_COUNT" -gt 0 ]; then
    echo "  ✅ Found $STAC_COUNT STAC items"
    aws s3 ls s3://$STAC_BUCKET/stac/ --recursive --human-readable | head -10
else
    echo "  ❌ No STAC items found"
fi
echo ""

# Step 4: Check API endpoints
echo "═══════════════════════════════════════════════════════════"
echo "STEP 4: Check API Endpoints"
echo "═══════════════════════════════════════════════════════════"
echo ""

echo "🌐 Testing API endpoints..."
echo ""

# Check health
echo "1️⃣  Health Check:"
HEALTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://$ALB_DNS/health 2>/dev/null || echo "000")
if [ "$HEALTH_STATUS" = "200" ]; then
    echo "  ✅ Health endpoint: OK (200)"
else
    echo "  ❌ Health endpoint: Failed ($HEALTH_STATUS)"
    echo "  ⚠️  Services may not be running. Check: ./scripts/start-services.sh"
fi
echo ""

# Check collections
echo "2️⃣  Collections API:"
COLLECTIONS_RESPONSE=$(curl -s http://$ALB_DNS/api/collections 2>/dev/null || echo "{}")
COLLECTIONS_COUNT=$(echo "$COLLECTIONS_RESPONSE" | jq -r '.collections | length' 2>/dev/null || echo "0")
if [ "$COLLECTIONS_COUNT" -gt 0 ]; then
    echo "  ✅ Found $COLLECTIONS_COUNT collections"
    echo "$COLLECTIONS_RESPONSE" | jq -r '.collections[].id' 2>/dev/null | head -10 | sed 's/^/     - /'
else
    echo "  ❌ No collections found"
    echo "  Response: $COLLECTIONS_RESPONSE"
fi
echo ""

# Check variables
echo "3️⃣  Variables API:"
VARIABLES_RESPONSE=$(curl -s http://$ALB_DNS/api/variables 2>/dev/null || echo "{}")
VARIABLES_COUNT=$(echo "$VARIABLES_RESPONSE" | jq -r 'length' 2>/dev/null || echo "0")
if [ "$VARIABLES_COUNT" -gt 0 ]; then
    echo "  ✅ Found $VARIABLES_COUNT variables"
    echo "$VARIABLES_RESPONSE" | jq -r '.[].name' 2>/dev/null | head -10 | sed 's/^/     - /'
else
    echo "  ❌ No variables found"
    echo "  Response: $VARIABLES_RESPONSE"
fi
echo ""

# Step 5: Check OpenSearch
echo "═══════════════════════════════════════════════════════════"
echo "STEP 5: Check OpenSearch Index"
echo "═══════════════════════════════════════════════════════════"
echo ""

echo "🔍 Checking OpenSearch STAC index..."
# This would require OpenSearch endpoint and credentials
echo "  ℹ️  OpenSearch check requires additional setup"
echo "  ℹ️  Check AWS Console → OpenSearch → Indices"
echo ""

# Step 6: Diagnosis
echo "═══════════════════════════════════════════════════════════"
echo "DIAGNOSIS & RECOMMENDATIONS"
echo "═══════════════════════════════════════════════════════════"
echo ""

if [ "$SUCCEEDED" -eq 0 ]; then
    echo "❌ ISSUE: No successful ingestion executions"
    echo ""
    echo "Possible causes:"
    echo "  1. No files have been uploaded yet"
    echo "  2. Step Functions not triggered"
    echo "  3. Ingestion pipeline has errors"
    echo ""
    echo "Next steps:"
    echo "  1. Upload a test file:"
    echo "     aws s3 cp data/your-file.nc s3://$RAW_BUCKET/ingestion/"
    echo ""
    echo "  2. Monitor execution:"
    echo "     ./scripts/monitor-ingestion-pipeline.sh"
    echo ""
    echo "  3. Check logs if execution fails:"
    echo "     aws logs tail /ecs/zarr-conversion --follow"
    echo ""
fi

if [ "$SUCCEEDED" -gt 0 ] && [ "$STAC_COUNT" -eq 0 ]; then
    echo "⚠️  ISSUE: Executions succeeded but no STAC items found"
    echo ""
    echo "Possible causes:"
    echo "  1. STAC indexer Lambda failed"
    echo "  2. S3 bucket permissions issue"
    echo "  3. STAC items in different location"
    echo ""
    echo "Next steps:"
    echo "  1. Check STAC indexer logs:"
    echo "     aws logs tail /aws/lambda/\$(cd terraform && terraform output -raw project_name)-stac-indexer --follow"
    echo ""
    echo "  2. Check Step Functions execution details:"
    echo "     aws stepfunctions describe-execution --execution-arn <arn>"
    echo ""
fi

if [ "$STAC_COUNT" -gt 0 ] && [ "$COLLECTIONS_COUNT" -eq 0 ]; then
    echo "⚠️  ISSUE: STAC items exist but API returns no collections"
    echo ""
    echo "Possible causes:"
    echo "  1. ECS services not running"
    echo "  2. OpenSearch not indexed"
    echo "  3. API configuration issue"
    echo ""
    echo "Next steps:"
    echo "  1. Start ECS services:"
    echo "     ./scripts/start-services.sh"
    echo ""
    echo "  2. Wait 2-3 minutes for services to start"
    echo ""
    echo "  3. Check service status:"
    echo "     aws ecs describe-services --cluster \$(cd terraform && terraform output -raw ecs_cluster_name) --services tiles-service"
    echo ""
    echo "  4. Check service logs:"
    echo "     aws logs tail /ecs/tiles-service --follow"
    echo ""
fi

if [ "$COLLECTIONS_COUNT" -gt 0 ]; then
    echo "✅ SUCCESS: Collections are available via API"
    echo ""
    echo "You can now:"
    echo "  1. Query collections:"
    echo "     curl http://$ALB_DNS/api/collections | jq"
    echo ""
    echo "  2. Query variables:"
    echo "     curl http://$ALB_DNS/api/variables | jq"
    echo ""
    echo "  3. Query time series:"
    echo "     curl 'http://$ALB_DNS/api/timeseries?collection=<collection>&variable=<variable>&lat=<lat>&lon=<lon>' | jq"
    echo ""
fi

echo "═══════════════════════════════════════════════════════════"
echo ""

