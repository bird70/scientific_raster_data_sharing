# Ingestion Verification & Troubleshooting Guide

## Problem
After uploading NetCDF files, collections/variables/timeseries are not being returned by API queries.

## Quick Verification

Run the verification script:
```bash
chmod +x scripts/verify-ingestion-complete.sh
./scripts/verify-ingestion-complete.sh
```

This will check:
1. ✅ Uploaded files in S3
2. ✅ Step Functions executions
3. ✅ Processed files (Zarr, COG, STAC)
4. ✅ API endpoints
5. ✅ Diagnosis and recommendations

## Manual Step-by-Step Verification

### Step 1: Check if File Was Uploaded

```bash
# Get bucket name
cd terraform
RAW_BUCKET=$(terraform output -raw raw_bucket_name)
cd ..

# List files in ingestion folder
aws s3 ls s3://$RAW_BUCKET/ingestion/ --recursive --human-readable
```

**Expected**: You should see your NetCDF file(s)

**If empty**: Upload a test file:
```bash
aws s3 cp data/A2002070120230731_MC_SST_std_coastal_v05.nc s3://$RAW_BUCKET/ingestion/
```

### Step 2: Check Step Functions Execution

```bash
# Get state machine ARN
cd terraform
STATE_MACHINE_ARN=$(terraform output -raw ingestion_state_machine_arn)
cd ..

# List recent executions
aws stepfunctions list-executions \
  --state-machine-arn $STATE_MACHINE_ARN \
  --max-results 10 \
  --query 'executions[*].[name,status,startDate]' \
  --output table
```

**Expected**: You should see executions with status `SUCCEEDED`

**If no executions**: The trigger Lambda may not be configured. Check:
```bash
# Check S3 event notifications
aws s3api get-bucket-notification-configuration --bucket $RAW_BUCKET
```

**If executions FAILED**: Get details:
```bash
# Get the failed execution ARN from the list above
aws stepfunctions describe-execution --execution-arn <execution-arn>

# Get execution history to see where it failed
aws stepfunctions get-execution-history --execution-arn <execution-arn> | jq
```

### Step 3: Check Processed Files in S3

```bash
# Get bucket names
cd terraform
ZARR_BUCKET=$(terraform output -raw zarr_bucket_name)
COG_BUCKET=$(terraform output -raw cog_bucket_name)
STAC_BUCKET=$(terraform output -raw stac_bucket_name)
cd ..

# Check Zarr files
echo "Zarr files:"
aws s3 ls s3://$ZARR_BUCKET/zarr/ --recursive --human-readable

# Check COG files
echo "COG files:"
aws s3 ls s3://$COG_BUCKET/cog/ --recursive --human-readable

# Check STAC items
echo "STAC items:"
aws s3 ls s3://$STAC_BUCKET/stac/ --recursive --human-readable
```

**Expected**: You should see files in all three buckets

**If missing**:
- **No Zarr files**: Zarr conversion failed. Check logs:
  ```bash
  aws logs tail /ecs/zarr-conversion --since 1h
  ```

- **No COG files**: COG generation failed. Check logs:
  ```bash
  aws logs tail /ecs/cog-generation --since 1h
  ```

- **No STAC items**: STAC creation failed. Check logs:
  ```bash
  cd terraform
  PROJECT_NAME=$(terraform output -raw project_name)
  cd ..
  aws logs tail /aws/lambda/$PROJECT_NAME-stac-creator --since 1h
  ```

### Step 4: Check if Services Are Running

```bash
# Get cluster name
cd terraform
CLUSTER_NAME=$(terraform output -raw ecs_cluster_name)
cd ..

# Check service status
aws ecs describe-services \
  --cluster $CLUSTER_NAME \
  --services tiles-service timeseries-service \
  --query 'services[*].[serviceName,runningCount,desiredCount]' \
  --output table
```

**Expected**: `runningCount` should equal `desiredCount` (usually 1)

**If runningCount is 0**: Services are stopped. Start them:
```bash
./scripts/start-services.sh
```

Wait 2-3 minutes for services to start, then check again.

### Step 5: Test API Endpoints

```bash
# Get ALB DNS
cd terraform
ALB_DNS=$(terraform output -raw alb_dns_name)
cd ..

# Test health endpoint
curl http://$ALB_DNS/health

# Test collections endpoint
curl http://$ALB_DNS/api/collections | jq

# Test variables endpoint
curl http://$ALB_DNS/api/variables | jq
```

**Expected**:
- Health: `{"status": "healthy"}`
- Collections: Array of collection objects
- Variables: Array of variable objects

**If health fails**: Services not running or ALB misconfigured

**If collections/variables empty**: Data not indexed in OpenSearch


## Common Issues and Solutions

### Issue 1: Services Not Running

**Symptoms**:
- Health endpoint returns error or timeout
- Collections/variables endpoints return error

**Solution**:
```bash
# Start services
./scripts/start-services.sh

# Wait 2-3 minutes

# Verify services are running
cd terraform
CLUSTER_NAME=$(terraform output -raw ecs_cluster_name)
cd ..

aws ecs describe-services \
  --cluster $CLUSTER_NAME \
  --services tiles-service timeseries-service \
  --query 'services[*].[serviceName,runningCount]' \
  --output table
```

### Issue 2: STAC Items Not Indexed in OpenSearch

**Symptoms**:
- STAC files exist in S3
- API returns empty collections/variables

**Cause**: STAC Indexer Lambda may have failed

**Solution**:
```bash
# Check STAC indexer logs
cd terraform
PROJECT_NAME=$(terraform output -raw project_name)
cd ..

aws logs tail /aws/lambda/$PROJECT_NAME-stac-indexer --since 1h

# If indexer failed, you may need to re-index manually
# Check OpenSearch domain status
cd terraform
OPENSEARCH_ENDPOINT=$(terraform output -raw opensearch_domain_endpoint)
cd ..

# Check if index exists (requires AWS credentials)
curl -X GET "https://$OPENSEARCH_ENDPOINT/_cat/indices?v"
```

### Issue 3: Step Functions Execution Failed

**Symptoms**:
- Executions show FAILED status
- No processed files in S3

**Solution**:
```bash
# Get failed execution details
cd terraform
STATE_MACHINE_ARN=$(terraform output -raw ingestion_state_machine_arn)
cd ..

# List failed executions
aws stepfunctions list-executions \
  --state-machine-arn $STATE_MACHINE_ARN \
  --status-filter FAILED \
  --max-results 5

# Get details of most recent failure
FAILED_ARN=$(aws stepfunctions list-executions \
  --state-machine-arn $STATE_MACHINE_ARN \
  --status-filter FAILED \
  --max-results 1 \
  --query 'executions[0].executionArn' \
  --output text)

aws stepfunctions describe-execution --execution-arn $FAILED_ARN

# Get execution history to see which step failed
aws stepfunctions get-execution-history \
  --execution-arn $FAILED_ARN \
  --query 'events[?type==`TaskFailed` || type==`ExecutionFailed`]' \
  | jq
```

Common failure reasons:
1. **ECS task failed to start**: Check IAM permissions, ECR image exists
2. **Task ran but failed**: Check CloudWatch logs for the specific task
3. **Lambda timeout**: Increase Lambda timeout or memory
4. **S3 permissions**: Verify IAM roles have S3 access

### Issue 4: No Collections Despite Successful Ingestion

**Symptoms**:
- Step Functions shows SUCCEEDED
- Files exist in all S3 buckets
- API returns empty collections

**Possible Causes**:
1. **Services not running** (most common)
2. **OpenSearch not indexed**
3. **API querying wrong index**

**Solution**:

1. **Verify services are running**:
```bash
./scripts/start-services.sh
# Wait 2-3 minutes
curl http://$(cd terraform && terraform output -raw alb_dns_name)/health
```

2. **Check OpenSearch index**:
```bash
# This requires OpenSearch access
# Check AWS Console → OpenSearch → Indices
# Look for "stac" index
```

3. **Check API logs**:
```bash
aws logs tail /ecs/tiles-service --since 30m --follow
```

4. **Manually test OpenSearch query** (if you have access):
```bash
cd terraform
OPENSEARCH_ENDPOINT=$(terraform output -raw opensearch_domain_endpoint)
cd ..

# Query STAC index
curl -X GET "https://$OPENSEARCH_ENDPOINT/stac/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{"query": {"match_all": {}}}'
```

### Issue 5: Wrong Collection/Variable Names

**Symptoms**:
- Collections exist but have unexpected names
- Variables don't match NetCDF file

**Cause**: Collection/variable names are derived from NetCDF metadata

**Solution**:

1. **Check NetCDF file structure**:
```bash
# Install ncdump if not available: apt-get install netcdf-bin
ncdump -h your-file.nc
```

2. **Check STAC item content**:
```bash
cd terraform
STAC_BUCKET=$(terraform output -raw stac_bucket_name)
cd ..

# Download and inspect STAC item
aws s3 cp s3://$STAC_BUCKET/stac/your-file.json - | jq
```

3. **Verify collection mapping**:
- Collections are typically derived from file path or metadata
- Variables are extracted from NetCDF variable names
- Check `app/app/stac_lookup.py` for collection logic

## Complete Verification Workflow

Here's a complete workflow to verify everything is working:

```bash
# 1. Upload test file
cd terraform
RAW_BUCKET=$(terraform output -raw raw_bucket_name)
cd ..

aws s3 cp data/A2002070120230731_MC_SST_std_coastal_v05.nc \
  s3://$RAW_BUCKET/ingestion/test-file.nc

# 2. Monitor ingestion
./scripts/monitor-ingestion-pipeline.sh
# Select option 1: Show recent executions
# Wait for execution to complete (10-20 minutes)

# 3. Verify processed files
cd terraform
ZARR_BUCKET=$(terraform output -raw zarr_bucket_name)
COG_BUCKET=$(terraform output -raw cog_bucket_name)
STAC_BUCKET=$(terraform output -raw stac_bucket_name)
cd ..

aws s3 ls s3://$ZARR_BUCKET/zarr/
aws s3 ls s3://$COG_BUCKET/cog/
aws s3 ls s3://$STAC_BUCKET/stac/

# 4. Start services if not running
./scripts/start-services.sh

# 5. Wait for services to be healthy (2-3 minutes)
sleep 180

# 6. Test API
cd terraform
ALB_DNS=$(terraform output -raw alb_dns_name)
cd ..

curl http://$ALB_DNS/health
curl http://$ALB_DNS/api/collections | jq
curl http://$ALB_DNS/api/variables | jq

# 7. If collections found, test time series query
# Replace <collection>, <variable>, <lat>, <lon> with actual values
curl "http://$ALB_DNS/api/timeseries?collection=<collection>&variable=<variable>&lat=-35&lon=150" | jq
```

## Quick Diagnostic Commands

```bash
# Check everything at once
./scripts/verify-ingestion-complete.sh

# Monitor pipeline in real-time
./scripts/monitor-ingestion-pipeline.sh

# Check service status
cd terraform
aws ecs describe-services \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --services tiles-service timeseries-service \
  --query 'services[*].[serviceName,runningCount,desiredCount]' \
  --output table
cd ..

# Check recent logs
aws logs tail /ecs/tiles-service --since 10m
aws logs tail /ecs/zarr-conversion --since 30m

# Check Step Functions
cd terraform
aws stepfunctions list-executions \
  --state-machine-arn $(terraform output -raw ingestion_state_machine_arn) \
  --max-results 5 \
  --query 'executions[*].[name,status]' \
  --output table
cd ..
```

## Getting Help

If you're still having issues:

1. **Run the verification script** and share the output:
   ```bash
   ./scripts/verify-ingestion-complete.sh > verification-output.txt
   ```

2. **Check CloudWatch logs** for errors:
   ```bash
   aws logs tail /ecs/zarr-conversion --since 1h > zarr-logs.txt
   aws logs tail /ecs/tiles-service --since 30m > api-logs.txt
   ```

3. **Get Step Functions execution details**:
   ```bash
   cd terraform
   STATE_MACHINE_ARN=$(terraform output -raw ingestion_state_machine_arn)
   cd ..
   
   EXECUTION_ARN=$(aws stepfunctions list-executions \
     --state-machine-arn $STATE_MACHINE_ARN \
     --max-results 1 \
     --query 'executions[0].executionArn' \
     --output text)
   
   aws stepfunctions describe-execution \
     --execution-arn $EXECUTION_ARN > execution-details.json
   ```

4. **Check the runbook**: `docs/ECS_ZARR_MIGRATION_RUNBOOK.md`

---

**Created**: 2024  
**Related Docs**:
- `docs/ECS_ZARR_MIGRATION_RUNBOOK.md`
- `docs/INGESTION_PIPELINE.md`
- `scripts/monitor-ingestion-pipeline.sh`

