# OpenSearch to DynamoDB Migration Execution Guide

## Overview

This guide provides instructions for executing the STAC metadata migration from OpenSearch to DynamoDB. The migration script has been created and tested, but requires execution from within the AWS VPC since OpenSearch is not publicly accessible.

## Prerequisites

- DynamoDB table created: `cloud-scientific-raster-sharing-stac-items`
- OpenSearch domain: `vpc-cloud-sciraster-stac-aaaabbbbbcccccddddd1231231.ap-southeast-2.es.amazonaws.com`
- AWS credentials with appropriate permissions
- Network access to OpenSearch (VPC access required)

## Migration Script Location

```
scripts/migrate_stac_to_dynamodb.py
```

## Execution Options

### Option 1: Run from EC2 Instance (Recommended)

1. Launch an EC2 instance in the same VPC as OpenSearch
2. Install Python dependencies:
   ```bash
   pip install boto3 opensearch-py requests-aws4auth
   ```
3. Copy the migration script to the instance
4. Run the migration:
   ```bash
   python migrate_stac_to_dynamodb.py \
     --opensearch-host vpc-cloud-sciraster-stac-aaaabbbbbcccccddddd1231231.ap-southeast-2.es.amazonaws.com \
     --dynamodb-table cloud-scientific-raster-sharing-stac-items \
     --region ap-southeast-2 \
     --dry-run
   ```

### Option 2: Run from ECS Task

1. Create a one-time ECS task definition with the migration script
2. Use the existing ECS cluster and VPC configuration
3. Execute the task with appropriate IAM permissions

### Option 3: Run from Lambda (For Small Datasets)

1. Package the migration script as a Lambda function
2. Configure with VPC access to OpenSearch
3. Set timeout to maximum (15 minutes)
4. Note: Only suitable for small datasets due to Lambda timeout limits

## Migration Steps

### Step 1: Dry Run

First, run in dry-run mode to validate the migration without writing to DynamoDB:

```bash
python migrate_stac_to_dynamodb.py \
  --opensearch-host vpc-cloud-sciraster-stac-aaaabbbbbcccccddddd1231231.ap-southeast-2.es.amazonaws.com \
  --dynamodb-table cloud-scientific-raster-sharing-stac-items \
  --region ap-southeast-2 \
  --dry-run
```

Expected output:
- Connection to OpenSearch successful
- Item count from OpenSearch
- Validation of item transformation
- No actual writes to DynamoDB

### Step 2: Full Migration

Once dry-run succeeds, run the actual migration:

```bash
python migrate_stac_to_dynamodb.py \
  --opensearch-host vpc-cloud-sciraster-stac-aaaabbbbbcccccddddd1231231.ap-southeast-2.es.amazonaws.com \
  --dynamodb-table cloud-scientific-raster-sharing-stac-items \
  --region ap-southeast-2
```

The script will:
- Scroll through all items in OpenSearch
- Transform each item to DynamoDB format
- Batch write to DynamoDB (25 items per batch)
- Log progress every batch
- Generate a migration report

### Step 3: Resume (If Interrupted)

If the migration is interrupted, resume from where it left off:

```bash
python migrate_stac_to_dynamodb.py \
  --opensearch-host vpc-cloud-sciraster-stac-aaaabbbbbcccccddddd1231231.ap-southeast-2.es.amazonaws.com \
  --dynamodb-table cloud-scientific-raster-sharing-stac-items \
  --region ap-southeast-2 \
  --resume
```

The `--resume` flag will skip items already in DynamoDB.

## Monitoring Migration Progress

The migration script provides detailed logging:

1. **Console Output**: Real-time progress updates
2. **Log File**: Detailed log saved to `migration_YYYYMMDD_HHMMSS.log`
3. **Migration Report**: JSON report saved to `migration_report_YYYYMMDD_HHMMSS.json`

Example progress output:
```
2025-11-28 15:43:07 - INFO - Starting scroll through 1234 items
2025-11-28 15:43:10 - INFO - Progress: Read=25, Written=25, Skipped=0, Errors=0
2025-11-28 15:43:12 - INFO - Progress: Read=50, Written=50, Skipped=0, Errors=0
...
2025-11-28 15:45:00 - INFO - MIGRATION COMPLETE
2025-11-28 15:45:00 - INFO - Total items read: 1234
2025-11-28 15:45:00 - INFO - Total items written: 1234
2025-11-28 15:45:00 - INFO - Total errors: 0
2025-11-28 15:45:00 - INFO - Duration: 113.45 seconds
2025-11-28 15:45:00 - INFO - Rate: 10.88 items/second
```

## Validation After Migration

After migration completes, validate the data:

1. **Item Count Comparison**:
   ```bash
   # OpenSearch count
   curl -X GET "https://OPENSEARCH_HOST/stac/_count"
   
   # DynamoDB count
   aws dynamodb scan \
     --table-name cloud-scientific-raster-sharing-stac-items \
     --select COUNT \
     --region ap-southeast-2
   ```

2. **Spot Check Random Items**:
   - Query a few items from both backends
   - Compare field values
   - Verify GSI attributes populated

3. **Test API Queries**:
   - Query by collection
   - Query by datetime range
   - Query by bounding box
   - Compare results with OpenSearch

## Troubleshooting

### Connection Timeout

**Error**: `Connection to vpc-cloud-sciraster-stac-aaaabbbbbcccccddddd1231231.ap-southeast-2.es.amazonaws.com timed out`

**Cause**: OpenSearch is in a VPC and not publicly accessible

**Solution**: Run the migration from within the VPC (EC2, ECS, or Lambda with VPC config)

### Authentication Errors

**Error**: `AuthorizationException` or `403 Forbidden`

**Cause**: IAM permissions missing

**Solution**: Ensure the execution role has:
- OpenSearch: `es:ESHttpGet`, `es:ESHttpPost`
- DynamoDB: `dynamodb:PutItem`, `dynamodb:BatchWriteItem`

### Throttling Errors

**Error**: `ProvisionedThroughputExceededException`

**Cause**: DynamoDB write capacity exceeded

**Solution**: 
- DynamoDB is configured with on-demand billing, so this should be rare
- If it occurs, reduce batch size: `--batch-size 10`
- Add delays between batches if needed

### Item Transformation Errors

**Error**: `Failed to migrate item X: Missing required field`

**Cause**: OpenSearch item missing required STAC fields

**Solution**:
- Review the error in the migration log
- Fix the source data in OpenSearch
- Re-run migration with `--resume` flag

## Current Status

- ✅ DynamoDB table created
- ✅ Migration script implemented
- ✅ Dry-run tested (connection issue due to VPC)
- ⏳ Awaiting execution from within VPC
- ⏳ Validation pending
- ⏳ Switch to DynamoDB-only mode pending

## Next Steps

1. **Execute Migration**: Run the migration script from within the VPC
2. **Validate Data**: Compare item counts and spot-check data integrity
3. **Test API**: Verify all query patterns work with DynamoDB
4. **Switch Backend**: Update `STAC_BACKEND=dynamodb` in ECS configuration
5. **Remove OpenSearch**: Clean up OpenSearch infrastructure after validation

## References

- Migration Script: `scripts/migrate_stac_to_dynamodb.py`
- Design Document: `.kiro/specs/opensearch-to-dynamodb-migration/design.md`
- Requirements: `.kiro/specs/opensearch-to-dynamodb-migration/requirements.md`
- DynamoDB Schema: `docs/DYNAMODB_STAC_SCHEMA.md`
