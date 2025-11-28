# Dual Backend Deployment Guide

This guide walks through deploying and testing the dual backend mode for the OpenSearch to DynamoDB migration.

## Overview

Dual backend mode allows the application to:
- **Read**: Try DynamoDB first, fall back to OpenSearch if not found
- **Write**: Write to both DynamoDB and OpenSearch simultaneously
- **Monitor**: Track backend usage via CloudWatch metrics

This enables zero-downtime migration from OpenSearch to DynamoDB.

## Prerequisites

1. DynamoDB infrastructure deployed (Task 1 completed)
2. Application code updated with dual backend support (Tasks 3-5 completed)
3. Terraform configuration updated with `stac_backend` variable
4. AWS credentials configured with appropriate permissions

## Deployment Steps

### Step 1: Verify Terraform Configuration

Check that `terraform/terraform.tfvars` has the correct setting:

```hcl
stac_backend = "dual"
```

### Step 2: Plan Terraform Changes

```bash
cd terraform
terraform plan -out=dual-backend.tfplan
```

Review the plan to ensure:
- DynamoDB table exists or will be created
- ECS task definitions will be updated with `STAC_BACKEND=dual`
- Lambda functions will be updated with `STAC_BACKEND=dual`
- No unexpected resource changes

### Step 3: Apply Terraform Changes

```bash
terraform apply dual-backend.tfplan
```

This will:
- Create/update DynamoDB table with GSIs
- Update ECS task definitions with new environment variables
- Update Lambda functions with new environment variables
- Deploy monitoring alarms and dashboards

### Step 4: Verify Deployment

Run the validation script:

```bash
python scripts/validate_dual_backend.py
```

This checks:
1. DynamoDB table is active with correct GSIs
2. ECS services have `STAC_BACKEND=dual` configured
3. CloudWatch metrics are being emitted
4. CloudWatch logs show dual backend activity

### Step 5: Test API Queries

Test that API queries work from both backends:

```bash
# Get ALB endpoint
ALB_ENDPOINT=$(terraform output -raw alb_dns_name)

# Test health endpoint
curl http://${ALB_ENDPOINT}/health

# Test collections endpoint (should work from either backend)
curl http://${ALB_ENDPOINT}/api/collections
```

### Step 6: Test Ingestion Pipeline

Upload a test NetCDF file to trigger the ingestion pipeline:

```bash
# Upload test file
aws s3 cp data/your-data.nc s3://YOUR-RAW-BUCKET/test/your-data.nc

# Monitor Step Functions execution
aws stepfunctions list-executions \
  --state-machine-arn YOUR-STATE-MACHINE-ARN \
  --max-results 1

# Check STAC indexer Lambda logs
aws logs tail /aws/lambda/YOUR-STAC-INDEXER-FUNCTION --follow
```

### Step 7: Verify Dual Writes

After ingestion completes, verify the STAC item was written to both backends:

```bash
# Check DynamoDB
aws dynamodb get-item \
  --table-name YOUR-DYNAMODB-TABLE \
  --key '{"id": {"S": "YOUR-STAC-ITEM-ID"}}'

# Check OpenSearch (requires VPC access or bastion)
curl -X GET "https://YOUR-OPENSEARCH-ENDPOINT/stac/_doc/YOUR-STAC-ITEM-ID"
```

### Step 8: Monitor CloudWatch

Check CloudWatch for backend usage metrics:

1. Go to CloudWatch Console
2. Navigate to Metrics → STAC/DualBackend
3. View metrics:
   - `DynamoDBUsage` - Operations served by DynamoDB
   - `OpenSearchUsage` - Operations served by OpenSearch (fallback)

Check CloudWatch Logs for dual backend activity:

```bash
# Tiles service logs
aws logs tail /ecs/tiles-service --follow --filter-pattern "dual backend"

# Timeseries service logs
aws logs tail /ecs/timeseries-service --follow --filter-pattern "dual backend"

# STAC indexer Lambda logs
aws logs tail /aws/lambda/YOUR-STAC-INDEXER-FUNCTION --follow
```

## Validation Checklist

- [ ] DynamoDB table is ACTIVE with 2 GSIs
- [ ] ECS tiles service has `STAC_BACKEND=dual`
- [ ] ECS timeseries service has `STAC_BACKEND=dual`
- [ ] Lambda STAC indexer has `STAC_BACKEND=dual`
- [ ] API health endpoint returns 200
- [ ] API collections endpoint returns data
- [ ] Test ingestion completes successfully
- [ ] STAC item exists in DynamoDB
- [ ] STAC item exists in OpenSearch
- [ ] CloudWatch metrics show DynamoDB usage
- [ ] CloudWatch logs show dual backend activity

## Troubleshooting

### Issue: ECS tasks fail to start

**Symptoms**: ECS tasks are in STOPPED state

**Solution**:
1. Check CloudWatch logs for error messages
2. Verify IAM permissions include DynamoDB access
3. Verify environment variables are set correctly
4. Check that DynamoDB table exists and is ACTIVE

### Issue: API queries return 500 errors

**Symptoms**: API returns internal server errors

**Solution**:
1. Check CloudWatch logs for Python exceptions
2. Verify `DYNAMODB_STAC_TABLE` environment variable is set
3. Verify `OPENSEARCH_HOST` environment variable is set
4. Test DynamoDB and OpenSearch connectivity from ECS tasks

### Issue: Ingestion writes only to one backend

**Symptoms**: STAC item exists in only DynamoDB or OpenSearch

**Solution**:
1. Check Lambda logs for errors
2. Verify Lambda has `STAC_BACKEND=dual` environment variable
3. Verify Lambda IAM role has permissions for both backends
4. Check for partial write failures in Lambda logs

### Issue: No CloudWatch metrics

**Symptoms**: STAC/DualBackend namespace is empty

**Solution**:
1. Verify API requests are being made
2. Check that application code is emitting metrics
3. Verify IAM permissions include `cloudwatch:PutMetricData`
4. Wait a few minutes for metrics to appear (can take 5-10 minutes)

## Rollback Procedure

If issues occur, rollback to OpenSearch-only mode:

1. Update `terraform/terraform.tfvars`:
   ```hcl
   stac_backend = "opensearch"
   ```

2. Apply changes:
   ```bash
   cd terraform
   terraform apply
   ```

3. Verify services restart with OpenSearch-only mode:
   ```bash
   python scripts/validate_dual_backend.py
   ```

## Next Steps

After successful dual backend deployment:

1. **Monitor for 24-48 hours**: Ensure stability and no errors
2. **Run migration script**: Migrate existing OpenSearch data to DynamoDB (Task 11)
3. **Validate migration**: Compare item counts and spot-check data integrity
4. **Switch to DynamoDB-only**: Update `stac_backend = "dynamodb"` (Task 12)
5. **Remove OpenSearch**: Decommission OpenSearch infrastructure (Task 13)

## References

- [DynamoDB Migration Guide](./DYNAMODB_MIGRATION_GUIDE.md)
- [DynamoDB STAC Schema](./DYNAMODB_STAC_SCHEMA.md)
- [Architecture Analysis](./ARCHITECTURE_ANALYSIS.md)
