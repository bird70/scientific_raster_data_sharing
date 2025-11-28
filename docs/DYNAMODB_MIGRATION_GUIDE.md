# DynamoDB Migration Guide

## Overview

This guide provides step-by-step instructions for migrating the STAC (SpatioTemporal Asset Catalog) metadata storage from AWS OpenSearch to AWS DynamoDB. The migration follows a zero-downtime approach using dual-backend mode, allowing safe rollback at any stage.

**Expected Benefits:**
- **Cost Reduction**: ~90% savings ($100/month → $5-10/month)
- **Simplified Operations**: No cluster management, automatic scaling
- **Improved Performance**: Single-digit millisecond latency for key-based lookups
- **Better Reliability**: Built-in replication, point-in-time recovery

**Migration Timeline:** 2-4 hours (depending on data volume)

---

## Pre-Migration Checklist

Before starting the migration, ensure the following prerequisites are met:

### Infrastructure Requirements

- [ ] **Terraform Access**: Ensure you have AWS credentials with permissions to create DynamoDB tables
- [ ] **Backup OpenSearch Data**: Create a snapshot of the OpenSearch domain
  ```bash
  # Document current item count
  curl -X GET "https://<opensearch-endpoint>/stac/_count" -u admin:password
  ```
- [ ] **Review Current Data**: Verify STAC items are valid and complete
- [ ] **Check IAM Permissions**: Ensure ECS task role and Lambda execution role can be updated
- [ ] **Verify Disk Space**: Ensure sufficient space for migration logs and reports

### Application Requirements

- [ ] **Code Deployment**: Ensure latest code with DynamoDB support is deployed
  - `app/app/stac_lookup_dynamodb.py` exists
  - `app/app/stac_lookup_dual.py` exists
  - `scripts/migrate_stac_to_dynamodb.py` exists
- [ ] **Environment Variables**: Prepare environment variable updates
- [ ] **Monitoring Setup**: Ensure CloudWatch access for monitoring migration progress
- [ ] **Rollback Plan**: Document current configuration for quick rollback

### Communication

- [ ] **Notify Stakeholders**: Inform users of planned maintenance window (if needed)
- [ ] **Schedule Migration**: Choose low-traffic period for migration
- [ ] **Prepare Support**: Have team available during migration

---

## Migration Steps

### Phase 1: Deploy DynamoDB Infrastructure

**Duration:** 10-15 minutes

1. **Review Terraform Configuration**

   Verify the DynamoDB module is configured in `terraform/main.tf`:
   ```hcl
   module "dynamodb_stac" {
     source       = "./modules/dynamodb_stac"
     project_name = var.project_name
     tags         = local.common_tags
   }
   ```

2. **Plan Infrastructure Changes**

   ```bash
   cd terraform
   terraform plan -out=dynamodb-migration.tfplan
   ```

   Review the plan and verify:
   - DynamoDB table will be created with correct name
   - GSI indexes are configured (collection-index, datetime-index)
   - IAM permissions are updated for ECS and Lambda
   - No existing resources will be destroyed

3. **Apply Infrastructure Changes**

   ```bash
   terraform apply dynamodb-migration.tfplan
   ```

   Expected output:
   ```
   Apply complete! Resources: 3 added, 2 changed, 0 destroyed.
   
   Outputs:
   dynamodb_stac_table_name = "project-name-stac-items"
   dynamodb_stac_table_arn = "arn:aws:dynamodb:region:account:table/project-name-stac-items"
   ```

4. **Verify DynamoDB Table**

   ```bash
   aws dynamodb describe-table --table-name <table-name> --query 'Table.[TableName,TableStatus,GlobalSecondaryIndexes[*].IndexName]'
   ```

   Expected: Table status is "ACTIVE", GSIs are present

---

### Phase 2: Enable Dual Backend Mode

**Duration:** 15-20 minutes

1. **Update Environment Variables**

   Update the ECS task definition or environment configuration:
   ```bash
   # Set STAC_BACKEND to dual mode
   export STAC_BACKEND=dual
   export DYNAMODB_STAC_TABLE=<table-name-from-terraform>
   ```

   For ECS, update task definition:
   ```json
   {
     "name": "STAC_BACKEND",
     "value": "dual"
   },
   {
     "name": "DYNAMODB_STAC_TABLE",
     "value": "project-name-stac-items"
   }
   ```

2. **Deploy Updated Configuration**

   ```bash
   # Update ECS service with new task definition
   aws ecs update-service \
     --cluster <cluster-name> \
     --service <service-name> \
     --task-definition <new-task-def> \
     --force-new-deployment
   ```

3. **Verify Dual Backend is Active**

   Check application logs:
   ```bash
   aws logs tail /aws/ecs/<cluster>/<service> --follow
   ```

   Look for log entries indicating dual backend mode:
   ```
   INFO: STAC backend mode: dual
   INFO: DynamoDB table: project-name-stac-items
   INFO: OpenSearch host: <opensearch-endpoint>
   ```

4. **Test New Ingestion**

   Upload a test NetCDF file and verify it's indexed in both backends:
   ```bash
   # Upload test file
   aws s3 cp test-data.nc s3://<bucket>/input/test-data.nc
   
   # Wait for ingestion (check Step Functions or Lambda logs)
   
   # Verify in DynamoDB
   aws dynamodb get-item \
     --table-name <table-name> \
     --key '{"id": {"S": "test-data-2024-01-01"}}'
   
   # Verify in OpenSearch
   curl -X GET "https://<opensearch-endpoint>/stac/_doc/test-data-2024-01-01"
   ```

---

### Phase 3: Migrate Existing Data

**Duration:** 1-3 hours (depending on data volume)

1. **Prepare Migration Script**

   Review migration script configuration:
   ```bash
   cd scripts
   python migrate_stac_to_dynamodb.py --help
   ```

2. **Run Dry-Run Migration**

   Test migration without writing to DynamoDB:
   ```bash
   python migrate_stac_to_dynamodb.py \
     --opensearch-host <opensearch-endpoint> \
     --dynamodb-table <table-name> \
     --dry-run \
     --log-level INFO
   ```

   Review output:
   - Total items to migrate
   - Sample transformed items
   - Any validation errors

3. **Execute Migration**

   Run the actual migration:
   ```bash
   python migrate_stac_to_dynamodb.py \
     --opensearch-host <opensearch-endpoint> \
     --dynamodb-table <table-name> \
     --batch-size 25 \
     --log-level INFO \
     2>&1 | tee migration-$(date +%Y%m%d-%H%M%S).log
   ```

   Monitor progress:
   - Check log output for progress updates
   - Monitor DynamoDB metrics in CloudWatch
   - Watch for throttling or errors

4. **Review Migration Report**

   After completion, review the migration report:
   ```
   Migration Complete
   ==================
   Total items processed: 1,234
   Successfully migrated: 1,230
   Failed items: 4
   Duration: 45 minutes
   
   Failed Items:
   - item-id-1: Missing required field 'geometry'
   - item-id-2: Invalid datetime format
   - item-id-3: DynamoDB throttling
   - item-id-4: Invalid bbox coordinates
   ```

5. **Handle Failed Items**

   For any failed items:
   ```bash
   # Review failed item details in logs
   grep "Failed to migrate" migration-*.log
   
   # Fix data issues and retry specific items
   python migrate_stac_to_dynamodb.py \
     --opensearch-host <opensearch-endpoint> \
     --dynamodb-table <table-name> \
     --item-ids item-id-1,item-id-2 \
     --log-level DEBUG
   ```

---

### Phase 4: Validate Migration

**Duration:** 30-45 minutes

1. **Compare Item Counts**

   ```bash
   # OpenSearch count
   curl -X GET "https://<opensearch-endpoint>/stac/_count" | jq '.count'
   
   # DynamoDB count
   aws dynamodb scan \
     --table-name <table-name> \
     --select COUNT \
     --query 'Count'
   ```

   Counts should match (within tolerance for new ingestions during migration)

2. **Spot-Check Random Items**

   ```bash
   # Get random item from OpenSearch
   ITEM_ID=$(curl -s "https://<opensearch-endpoint>/stac/_search?size=1" | jq -r '.hits.hits[0]._id')
   
   # Compare with DynamoDB
   aws dynamodb get-item \
     --table-name <table-name> \
     --key "{\"id\": {\"S\": \"$ITEM_ID\"}}" \
     | jq '.Item'
   ```

   Verify all fields match (id, geometry, properties, assets, etc.)

3. **Test Query Patterns**

   Test all supported query patterns:
   
   **By Collection:**
   ```bash
   # Via API
   curl "https://<api-endpoint>/stac/search?collection=sst-daily&limit=10"
   ```

   **By Datetime Range:**
   ```bash
   curl "https://<api-endpoint>/stac/search?datetime=2024-01-01/2024-01-31"
   ```

   **By Bounding Box:**
   ```bash
   curl "https://<api-endpoint>/stac/search?bbox=150,-35,151,-34"
   ```

4. **Verify API Response Format**

   Compare API responses between dual backend and OpenSearch-only:
   - Response structure matches
   - All fields present
   - Pagination works correctly
   - Performance is acceptable

5. **Monitor CloudWatch Metrics**

   Check DynamoDB metrics:
   - Read capacity units consumed
   - Write capacity units consumed
   - Throttled requests (should be 0)
   - Latency (p50, p95, p99)

---

### Phase 5: Switch to DynamoDB-Only Mode

**Duration:** 15-20 minutes

1. **Verify Dual Backend is Stable**

   Ensure no errors in logs for at least 24 hours:
   ```bash
   aws logs filter-log-events \
     --log-group-name /aws/ecs/<cluster>/<service> \
     --start-time $(date -d '24 hours ago' +%s)000 \
     --filter-pattern "ERROR"
   ```

2. **Update Environment Variables**

   Change STAC_BACKEND to dynamodb-only:
   ```bash
   export STAC_BACKEND=dynamodb
   ```

   Update ECS task definition:
   ```json
   {
     "name": "STAC_BACKEND",
     "value": "dynamodb"
   }
   ```

3. **Deploy Updated Configuration**

   ```bash
   aws ecs update-service \
     --cluster <cluster-name> \
     --service <service-name> \
     --task-definition <new-task-def> \
     --force-new-deployment
   ```

4. **Verify DynamoDB-Only Mode**

   Check logs for confirmation:
   ```
   INFO: STAC backend mode: dynamodb
   INFO: DynamoDB table: project-name-stac-items
   ```

5. **Run Smoke Tests**

   Test all API endpoints:
   ```bash
   # Test STAC search
   curl "https://<api-endpoint>/stac/search?collection=sst-daily"
   
   # Test tiles endpoint
   curl "https://<api-endpoint>/tiles/<item-id>/0/0/0.png"
   
   # Test timeseries endpoint
   curl "https://<api-endpoint>/timeseries?item=<item-id>&lat=-34.5&lon=150.5"
   ```

6. **Monitor for 48 Hours**

   Watch for any issues:
   - API errors
   - Performance degradation
   - Missing data
   - User complaints

---

### Phase 6: Remove OpenSearch Infrastructure

**Duration:** 20-30 minutes

⚠️ **WARNING**: This step is irreversible. Ensure DynamoDB is working correctly before proceeding.

1. **Final Verification**

   - [ ] DynamoDB-only mode has been running successfully for 48+ hours
   - [ ] No errors in application logs
   - [ ] All API endpoints working correctly
   - [ ] User acceptance testing passed
   - [ ] Backup of OpenSearch data exists

2. **Update Terraform Configuration**

   Comment out or remove OpenSearch resources in `terraform/main.tf`:
   ```hcl
   # module "opensearch" {
   #   source = "./modules/opensearch"
   #   ...
   # }
   ```

   Remove OpenSearch-related IAM policies, security groups, and VPC endpoints.

3. **Plan Infrastructure Removal**

   ```bash
   cd terraform
   terraform plan -out=remove-opensearch.tfplan
   ```

   Review carefully:
   - OpenSearch domain will be deleted
   - OpenSearch security group will be removed
   - OpenSearch IAM policies will be removed
   - No other resources affected

4. **Apply Infrastructure Changes**

   ```bash
   terraform apply remove-opensearch.tfplan
   ```

   This will delete the OpenSearch domain (takes 10-15 minutes).

5. **Verify Removal**

   ```bash
   # Verify OpenSearch domain is deleted
   aws opensearch describe-domain --domain-name <domain-name>
   # Should return: ResourceNotFoundException
   ```

6. **Update Application Configuration**

   Remove OpenSearch environment variables:
   - Remove `OPENSEARCH_HOST`
   - Remove `OPENSEARCH_PORT`
   - Remove any OpenSearch-related configuration

7. **Clean Up Code (Optional)**

   Remove OpenSearch-related code:
   - Archive `app/app/stac_lookup_opensearch.py` (if exists)
   - Remove OpenSearch dependencies from `requirements.txt`
   - Update documentation

---

## Rollback Procedure

If issues arise during migration, follow these steps to rollback:

### Rollback from Dual Backend Mode

**Scenario:** Issues detected during Phase 2-4

1. **Switch Back to OpenSearch-Only**

   ```bash
   export STAC_BACKEND=opensearch
   ```

   Update and deploy ECS task definition.

2. **Verify OpenSearch is Working**

   Test API endpoints to ensure OpenSearch is responding correctly.

3. **Investigate Issues**

   Review logs to identify the problem:
   - DynamoDB throttling
   - Data validation errors
   - Application bugs

4. **Fix and Retry**

   Address the issues and restart migration from Phase 2.

### Rollback from DynamoDB-Only Mode

**Scenario:** Issues detected during Phase 5

1. **Switch Back to Dual Backend**

   ```bash
   export STAC_BACKEND=dual
   ```

   This allows reads from both backends while you investigate.

2. **Verify Both Backends are Accessible**

   Test queries against both OpenSearch and DynamoDB.

3. **Identify Missing Data**

   If data is missing in DynamoDB:
   ```bash
   # Re-run migration for specific items
   python migrate_stac_to_dynamodb.py \
     --opensearch-host <opensearch-endpoint> \
     --dynamodb-table <table-name> \
     --resume
   ```

4. **Switch Back to OpenSearch-Only (if needed)**

   If DynamoDB issues cannot be resolved quickly:
   ```bash
   export STAC_BACKEND=opensearch
   ```

### Emergency Rollback

**Scenario:** Critical production issue

1. **Immediate Rollback**

   ```bash
   # Revert to previous ECS task definition
   aws ecs update-service \
     --cluster <cluster-name> \
     --service <service-name> \
     --task-definition <previous-task-def>
   ```

2. **Notify Stakeholders**

   Inform team and users of the rollback.

3. **Post-Mortem**

   Document what went wrong and plan corrective actions.

---

## Troubleshooting

### Issue: DynamoDB Throttling During Migration

**Symptoms:**
- Migration script reports throttling errors
- CloudWatch shows high throttled request count

**Solution:**
1. Reduce batch size in migration script:
   ```bash
   python migrate_stac_to_dynamodb.py --batch-size 10
   ```

2. Add delays between batches:
   ```bash
   python migrate_stac_to_dynamodb.py --delay 1.0
   ```

3. Consider switching to provisioned capacity temporarily:
   ```bash
   aws dynamodb update-table \
     --table-name <table-name> \
     --billing-mode PROVISIONED \
     --provisioned-throughput ReadCapacityUnits=100,WriteCapacityUnits=100
   ```

### Issue: Item Count Mismatch

**Symptoms:**
- DynamoDB has fewer items than OpenSearch

**Solution:**
1. Check migration logs for failed items:
   ```bash
   grep "Failed to migrate" migration-*.log
   ```

2. Re-run migration with resume flag:
   ```bash
   python migrate_stac_to_dynamodb.py --resume
   ```

3. Verify items were not deleted during migration:
   ```bash
   # Check OpenSearch for items not in DynamoDB
   ```

### Issue: Query Results Don't Match

**Symptoms:**
- API returns different results from DynamoDB vs OpenSearch

**Solution:**
1. Verify GSI attributes are populated:
   ```bash
   aws dynamodb get-item \
     --table-name <table-name> \
     --key '{"id": {"S": "<item-id>"}}' \
     | jq '.Item | {collection, datetime}'
   ```

2. Check query logic in `stac_lookup_dynamodb.py`:
   - Verify KeyConditionExpression is correct
   - Check FilterExpression for bbox queries

3. Compare raw data:
   ```bash
   # Get item from both backends and compare
   ```

### Issue: High DynamoDB Costs

**Symptoms:**
- DynamoDB costs higher than expected

**Solution:**
1. Review read/write capacity units:
   ```bash
   aws cloudwatch get-metric-statistics \
     --namespace AWS/DynamoDB \
     --metric-name ConsumedReadCapacityUnits \
     --dimensions Name=TableName,Value=<table-name> \
     --start-time $(date -u -d '1 day ago' +%Y-%m-%dT%H:%M:%S) \
     --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
     --period 3600 \
     --statistics Sum
   ```

2. Optimize query patterns:
   - Use GetItem instead of Query when possible
   - Avoid Scan operations
   - Add caching layer (Redis)

3. Review GSI usage:
   - Ensure GSIs are necessary
   - Consider removing unused GSIs

### Issue: Missing Fields in Migrated Items

**Symptoms:**
- Some STAC fields are missing in DynamoDB

**Solution:**
1. Review transformation logic in migration script:
   ```python
   def transform_item(item: Dict) -> Dict:
       # Verify all fields are mapped correctly
   ```

2. Check for nested field issues:
   - DynamoDB has limits on nested depth
   - May need to flatten some structures

3. Re-migrate affected items:
   ```bash
   python migrate_stac_to_dynamodb.py --item-ids <comma-separated-ids>
   ```

### Issue: Application Errors After Migration

**Symptoms:**
- API returns 500 errors
- Application logs show DynamoDB errors

**Solution:**
1. Check IAM permissions:
   ```bash
   # Verify ECS task role has DynamoDB permissions
   aws iam get-role-policy \
     --role-name <ecs-task-role> \
     --policy-name DynamoDBAccess
   ```

2. Verify environment variables:
   ```bash
   # Check ECS task definition
   aws ecs describe-task-definition \
     --task-definition <task-def> \
     | jq '.taskDefinition.containerDefinitions[0].environment'
   ```

3. Review application logs:
   ```bash
   aws logs tail /aws/ecs/<cluster>/<service> --follow
   ```

---

## Post-Migration Tasks

After successful migration:

1. **Document Cost Savings**
   - Track DynamoDB costs for first month
   - Compare with previous OpenSearch costs
   - Update cost documentation

2. **Update Monitoring**
   - Set up DynamoDB CloudWatch alarms
   - Create DynamoDB dashboard
   - Remove OpenSearch monitoring

3. **Update Documentation**
   - Update architecture diagrams
   - Update API documentation
   - Update runbooks

4. **Team Training**
   - Train team on DynamoDB operations
   - Document new query patterns
   - Update troubleshooting guides

5. **Performance Tuning**
   - Review query performance
   - Optimize slow queries
   - Consider adding caching

---

## Support and Resources

- **AWS DynamoDB Documentation**: https://docs.aws.amazon.com/dynamodb/
- **STAC Specification**: https://stacspec.org/
- **Project Documentation**: See `docs/` directory
- **Migration Script**: `scripts/migrate_stac_to_dynamodb.py`
- **DynamoDB Schema**: `docs/DYNAMODB_STAC_SCHEMA.md`

For issues or questions, contact the platform team or create an issue in the project repository.
