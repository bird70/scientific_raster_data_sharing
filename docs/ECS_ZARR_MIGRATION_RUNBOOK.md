# ECS Zarr Conversion Migration - Operations Runbook

## Quick Reference

**Purpose**: Operational guide for the ECS-based Zarr conversion pipeline

**Key Resources**:
- State Machine: `{project_name}-ingestion-pipeline`
- ECS Cluster: `{project_name}-cluster`
- Task Definitions: `zarr-conversion`, `cog-generation`
- CloudWatch Dashboard: `{project_name}-ingestion-pipeline`

**Emergency Contacts**: Platform team

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Common Operations](#common-operations)
3. [Monitoring and Alerts](#monitoring-and-alerts)
4. [Troubleshooting Guide](#troubleshooting-guide)
5. [Rollback Procedures](#rollback-procedures)
6. [Cost Management](#cost-management)
7. [Decommissioning Legacy Components](#decommissioning-legacy-components)

---

## Architecture Overview

### Current Architecture (ECS-based)

```
S3 Upload → Trigger Lambda → Step Functions
                              ↓
                         ECS Task: Zarr Conversion (0.5 vCPU, 2GB)
                              ↓ (ResultSelector extracts zarr_key)
                         ECS Task: COG Generation (0.5 vCPU, 2GB)
                              ↓ (ResultSelector extracts cog_key)
                         Lambda: STAC Creation
                              ↓ (returns stac_key)
                         Lambda: STAC Indexing
                              ↓
                         Success/Failure → SNS Notification
```

### Key Innovation: ResultSelector Data Flow

The critical breakthrough in this implementation is using Step Functions' `ResultSelector` to extract
output information from the ECS task configuration itself, rather than attempting to read results
from S3 or task output.

**Why this works**:
- Step Functions has full visibility into ContainerOverrides it passes to ECS
- Output keys can be computed deterministically from input keys
- No S3 reads/writes needed for result passing
- Zero latency overhead
- 100% reliable


**Example ResultSelector**:
```json
{
  "ResultSelector": {
    "zarr_key.$": "States.Format('zarr/{}', States.StringReplace(
      States.ArrayGetItem(States.StringSplit(
        $.Overrides.ContainerOverrides[0].Environment[?(@.Name == 'INPUT_KEY')].Value, 
        '/'
      ), 1), 
      '.nc', '.zarr'
    ))",
    "zarr_bucket": "my-zarr-bucket",
    "status": "success"
  }
}
```

This transforms `ingestion/file.nc` → `zarr/file.zarr` without any S3 operations.

---

## Common Operations

### 1. Check Pipeline Status

**Quick Status Check**:
```bash
# Using monitoring script
./scripts/monitor-ingestion-pipeline.sh
# Select option 1: Show recent executions

# Or directly via AWS CLI
aws stepfunctions list-executions \
  --state-machine-arn $(cd terraform && terraform output -raw ingestion_state_machine_arn) \
  --max-results 10 \
  --profile DEVcloud
```

**Expected Output**: List of recent executions with status (SUCCEEDED, FAILED, RUNNING)

### 2. Process a Test File

**Upload Test File**:
```bash
aws s3 cp data/A2002070120230731_MC_SST_std_coastal_v05.nc \
  s3://$(cd terraform && terraform output -raw raw_bucket_name)/ingestion/ \
  --profile DEVcloud
```

**Monitor Execution**:
```bash
# Watch logs in real-time
./scripts/monitor-ingestion-pipeline.sh
# Select option 11: Tail logs in real-time

# Or manually
aws logs tail /ecs/zarr-conversion --follow --profile DEVcloud
```

**Verify Outputs**:
```bash
# Check Zarr file
aws s3 ls s3://$(cd terraform && terraform output -raw zarr_bucket_name)/zarr/ \
  --profile DEVcloud

# Check COG file
aws s3 ls s3://$(cd terraform && terraform output -raw cog_bucket_name)/cog/ \
  --profile DEVcloud

# Check STAC item
aws s3 cp \
  s3://$(cd terraform && terraform output -raw stac_bucket_name)/stac/A2002070120230731_MC_SST_std_coastal_v05.json \
  - --profile DEVcloud | jq .
```


### 3. Manually Trigger Pipeline

**Start Execution**:
```bash
aws stepfunctions start-execution \
  --state-machine-arn $(cd terraform && terraform output -raw ingestion_state_machine_arn) \
  --input '{
    "bucket": "your-raw-bucket",
    "key": "ingestion/your-file.nc"
  }' \
  --profile DEVcloud
```

**Get Execution ARN from output, then monitor**:
```bash
aws stepfunctions describe-execution \
  --execution-arn <execution-arn> \
  --profile DEVcloud
```

### 4. Stop a Running Execution

**Emergency Stop**:
```bash
aws stepfunctions stop-execution \
  --execution-arn <execution-arn> \
  --profile DEVcloud
```

**Note**: This will stop the Step Functions execution but may not immediately stop running ECS tasks.
To stop ECS tasks:

```bash
# List running tasks
aws ecs list-tasks \
  --cluster $(cd terraform && terraform output -raw ecs_cluster_name) \
  --profile DEVcloud

# Stop specific task
aws ecs stop-task \
  --cluster $(cd terraform && terraform output -raw ecs_cluster_name) \
  --task <task-arn> \
  --profile DEVcloud
```

### 5. View CloudWatch Dashboard

**Via AWS Console**:
1. Navigate to CloudWatch → Dashboards
2. Select `{project_name}-ingestion-pipeline`
3. View metrics for executions, tasks, and resource utilization

**Via CLI (open in browser)**:
```bash
./scripts/monitor-ingestion-pipeline.sh
# Select option 9: Open dashboard in browser
```

### 6. Check Alarm Status

**List All Alarms**:
```bash
aws cloudwatch describe-alarms \
  --alarm-name-prefix "$(cd terraform && terraform output -raw project_name)-ingestion" \
  --profile DEVcloud
```

**Check Specific Alarm**:
```bash
aws cloudwatch describe-alarms \
  --alarm-names "[YOURORG]-ingestion-high-failure-rate" \
  --profile DEVcloud
```

**Expected States**:
- `OK`: Normal operation
- `ALARM`: Threshold exceeded, investigate immediately
- `INSUFFICIENT_DATA`: Not enough data yet (normal for new deployments)


---

## Monitoring and Alerts

### CloudWatch Alarms

**6 Alarms Configured**:

1. **High Failure Rate** (`{project}-ingestion-high-failure-rate`)
   - Threshold: >2 failures in 5 minutes
   - Action: SNS notification
   - Response: Check Step Functions execution history and logs

2. **Long Execution Time** (`{project}-ingestion-long-execution`)
   - Threshold: >20 minutes
   - Action: SNS notification
   - Response: Check ECS task resource utilization

3. **Zarr Task Failure** (`{project}-zarr-task-failure`)
   - Threshold: Any failure in 5 minutes
   - Action: SNS notification
   - Response: Check `/ecs/zarr-conversion` logs

4. **COG Task Failure** (`{project}-cog-task-failure`)
   - Threshold: Any failure in 5 minutes
   - Action: SNS notification
   - Response: Check `/ecs/cog-generation` logs

5. **Zarr High Memory** (`{project}-zarr-high-memory`)
   - Threshold: >90% memory for 10 minutes
   - Action: SNS notification
   - Response: Consider increasing task memory

6. **COG High Memory** (`{project}-cog-high-memory`)
   - Threshold: >90% memory for 10 minutes
   - Action: SNS notification
   - Response: Consider increasing task memory

### Key Metrics to Monitor

**Success Rate** (Target: >95%):
```bash
./scripts/monitor-ingestion-pipeline.sh
# Select option 2: Calculate success rate
```

**Execution Time** (Target: 10-20 minutes):
```bash
./scripts/monitor-ingestion-pipeline.sh
# Select option 3: Show execution time statistics
```

**Resource Utilization** (Target: CPU 30-70%, Memory 50-80%):
```bash
./scripts/monitor-ingestion-pipeline.sh
# Select option 4: Display ECS task metrics
```

**Cost per File** (Target: ≤$0.08):
```bash
./scripts/monitor-ingestion-pipeline.sh
# Select option 7: Show cost estimation
```

### Log Locations

**ECS Tasks**:
- Zarr Conversion: `/ecs/zarr-conversion`
- COG Generation: `/ecs/cog-generation`

**Lambda Functions**:
- STAC Creator: `/aws/lambda/{project}-stac-creator`
- STAC Indexer: `/aws/lambda/{project}-stac-indexer`
- Trigger: `/aws/lambda/{project}-ingestion-trigger`

**Accessing Logs**:
```bash
# Tail logs in real-time
aws logs tail /ecs/zarr-conversion --follow --profile DEVcloud

# Filter for errors
aws logs filter-log-events \
  --log-group-name /ecs/zarr-conversion \
  --filter-pattern "ERROR" \
  --start-time $(date -u -d '1 hour ago' +%s)000 \
  --profile DEVcloud
```


---

## Troubleshooting Guide

### Issue 1: ECS Task Fails to Start

**Symptoms**:
- Step Functions shows "TaskFailed" immediately
- No logs in CloudWatch for the task
- Execution fails within seconds

**Possible Causes**:
1. Container image not found in ECR
2. Insufficient IAM permissions
3. Network configuration issues
4. Invalid task definition

**Diagnosis**:
```bash
# Check task definition
aws ecs describe-task-definition \
  --task-definition zarr-conversion \
  --profile DEVcloud

# Check if image exists in ECR
aws ecr describe-images \
  --repository-name $(cd terraform && terraform output -raw ecr_repository_name) \
  --profile DEVcloud

# Check IAM role
aws iam get-role \
  --role-name ecs-task-execution-role \
  --profile DEVcloud
```

**Solutions**:
1. **Missing Image**: Build and push Docker image
   ```bash
   ./scripts/build-and-push-docker.sh
   ```

2. **IAM Permissions**: Verify execution role has ECR pull permissions
   ```bash
   # Check role policy
   aws iam list-attached-role-policies \
     --role-name ecs-task-execution-role \
     --profile DEVcloud
   ```

3. **Network Issues**: Verify security group and subnet configuration
   ```bash
   # Check security group rules
   aws ec2 describe-security-groups \
     --group-ids $(cd terraform && terraform output -raw ecs_security_group_id) \
     --profile DEVcloud
   ```

### Issue 2: Task Runs But Fails During Processing

**Symptoms**:
- Task starts successfully
- Logs show errors during processing
- Task exits with non-zero code

**Possible Causes**:
1. Invalid NetCDF file format
2. Missing S3 permissions
3. Insufficient memory/CPU
4. Network timeout downloading from S3

**Diagnosis**:
```bash
# Check CloudWatch logs for errors
aws logs tail /ecs/zarr-conversion --since 30m --profile DEVcloud | grep ERROR

# Check task stopped reason
aws ecs describe-tasks \
  --cluster $(cd terraform && terraform output -raw ecs_cluster_name) \
  --tasks <task-arn> \
  --profile DEVcloud
```

**Solutions**:
1. **Invalid File**: Validate NetCDF file locally
   ```bash
   python -c "import xarray as xr; ds = xr.open_dataset('file.nc'); print(ds)"
   ```

2. **S3 Permissions**: Verify task role has S3 access
   ```bash
   aws iam get-role-policy \
     --role-name ecs-task-role \
     --policy-name ecs-task-policy \
     --profile DEVcloud
   ```

3. **Resource Constraints**: Increase task resources in `terraform/modules/ecs/main.tf`
   ```hcl
   cpu    = "1024"  # Increase from 512
   memory = "4096"  # Increase from 2048
   ```


### Issue 3: STAC Item Missing Bounding Box

**Symptoms**:
- STAC item created successfully
- `bbox` field is missing or contains default values [-180, -90, 180, 90]
- Warning in logs about using default bounding box

**Possible Causes**:
1. NetCDF file missing coordinate variables (lat, lon)
2. NetCDF file missing geospatial global attributes
3. Metadata file not created by zarr_converter
4. STAC creator Lambda not reading metadata correctly

**Diagnosis**:
```bash
# Check if metadata file exists
aws s3 ls s3://$(cd terraform && terraform output -raw zarr_bucket_name)/zarr/ \
  --recursive | grep metadata.json \
  --profile DEVcloud

# Download and inspect metadata
aws s3 cp \
  s3://$(cd terraform && terraform output -raw zarr_bucket_name)/zarr/filename_metadata.json \
  - --profile DEVcloud | jq .

# Check NetCDF file structure
python -c "
import xarray as xr
ds = xr.open_dataset('file.nc')
print('Coordinates:', list(ds.coords))
print('Attributes:', ds.attrs)
"
```

**Solutions**:
1. **Missing Coordinates**: Add coordinate variables to NetCDF file or use global attributes
2. **Metadata File Missing**: Check zarr_converter logs for errors
3. **Default Bbox Used**: This is expected behavior when metadata is missing - verify if acceptable

### Issue 4: High Failure Rate

**Symptoms**:
- Multiple executions failing
- Alarm triggered: `{project}-ingestion-high-failure-rate`
- Success rate <95%

**Possible Causes**:
1. Systematic issue with input files
2. Infrastructure problem (S3, ECS, network)
3. Bug in processing code
4. Resource exhaustion

**Diagnosis**:
```bash
# Get failure statistics
./scripts/monitor-ingestion-pipeline.sh
# Select option 2: Calculate success rate

# Check recent errors
./scripts/monitor-ingestion-pipeline.sh
# Select option 5: Show recent errors

# Analyze failure patterns
aws stepfunctions list-executions \
  --state-machine-arn $(cd terraform && terraform output -raw ingestion_state_machine_arn) \
  --status-filter FAILED \
  --max-results 20 \
  --profile DEVcloud
```

**Solutions**:
1. **Input File Issues**: Validate files before upload, add pre-processing validation
2. **Infrastructure**: Check AWS Service Health Dashboard
3. **Code Bug**: Review recent code changes, rollback if necessary
4. **Resources**: Scale up ECS task resources or increase retry attempts


### Issue 5: Long Execution Time

**Symptoms**:
- Executions taking >20 minutes
- Alarm triggered: `{project}-ingestion-long-execution`
- Processing slower than expected

**Possible Causes**:
1. Large input files
2. Insufficient CPU/memory allocation
3. Network bottleneck (S3 transfer)
4. Inefficient processing code

**Diagnosis**:
```bash
# Check execution time statistics
./scripts/monitor-ingestion-pipeline.sh
# Select option 3: Show execution time statistics

# Check resource utilization
./scripts/monitor-ingestion-pipeline.sh
# Select option 4: Display ECS task metrics

# Check file sizes
aws s3 ls s3://$(cd terraform && terraform output -raw raw_bucket_name)/ingestion/ \
  --human-readable --profile DEVcloud
```

**Solutions**:
1. **Large Files**: 
   - Increase task resources
   - Consider parallel processing
   - Split files if possible

2. **Low Resource Utilization**: Increase CPU/memory allocation
   ```hcl
   # In terraform/modules/ecs/main.tf
   cpu    = "1024"  # Double from 512
   memory = "4096"  # Double from 2048
   ```

3. **Network Bottleneck**: 
   - Use S3 Transfer Acceleration
   - Verify VPC endpoint configuration
   - Check NAT gateway bandwidth

4. **Code Optimization**: Profile code and optimize bottlenecks

### Issue 6: High Memory Usage

**Symptoms**:
- Alarm triggered: `{project}-zarr-high-memory` or `{project}-cog-high-memory`
- Tasks occasionally fail with OOM errors
- Memory utilization >90%

**Possible Causes**:
1. Large datasets loaded into memory
2. Memory leak in processing code
3. Insufficient memory allocation

**Diagnosis**:
```bash
# Check memory metrics
aws cloudwatch get-metric-statistics \
  --namespace ECS/ContainerInsights \
  --metric-name MemoryUtilization \
  --dimensions Name=ClusterName,Value=$(cd terraform && terraform output -raw ecs_cluster_name) \
              Name=TaskDefinitionFamily,Value=zarr-conversion \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average,Maximum \
  --profile DEVcloud
```

**Solutions**:
1. **Increase Memory**: Update task definition
   ```hcl
   memory = "4096"  # Increase from 2048
   ```

2. **Optimize Code**: Use chunked processing, avoid loading entire dataset
   ```python
   # Use dask for lazy loading
   ds = xr.open_dataset('file.nc', chunks={'time': 10})
   ```

3. **Monitor for Leaks**: Add memory profiling to code


### Issue 7: ResultSelector Transformation Fails

**Symptoms**:
- Step Functions execution fails at ConvertToZarr or GenerateCOG state
- Error message about JSONPath or States.Format
- Data not passed correctly to next state

**Possible Causes**:
1. Input filename doesn't match expected pattern
2. JSONPath expression error
3. Environment variable not set correctly

**Diagnosis**:
```bash
# Check execution history
aws stepfunctions get-execution-history \
  --execution-arn <execution-arn> \
  --profile DEVcloud | jq '.events[] | select(.type == "TaskStateExited")'

# Verify input format
aws stepfunctions describe-execution \
  --execution-arn <execution-arn> \
  --profile DEVcloud | jq '.input'
```

**Solutions**:
1. **Filename Pattern**: Ensure files follow pattern `ingestion/*.nc`
2. **JSONPath Fix**: Review Step Functions definition in `terraform/modules/ingestion/main.tf`
3. **Test Transformation**: Use Step Functions simulator to test JSONPath expressions

**Expected Transformations**:
- `ingestion/file.nc` → `zarr/file.zarr`
- `zarr/file.zarr` → `cog/file.tif`
- `zarr/file.zarr` → `stac/file.json`

---

## Rollback Procedures

### Emergency Rollback (Immediate)

**Scenario**: Critical issue discovered, need to revert immediately

**Steps**:

1. **Disable S3 Event Notifications** (stop new executions):
   ```bash
   # Create empty notification configuration
   cat > /tmp/empty-notification.json <<EOF
   {
     "LambdaFunctionConfigurations": []
   }
   EOF
   
   # Apply to bucket
   aws s3api put-bucket-notification-configuration \
     --bucket $(cd terraform && terraform output -raw raw_bucket_name) \
     --notification-configuration file:///tmp/empty-notification.json \
     --profile DEVcloud
   ```

2. **Stop Running Executions**:
   ```bash
   # List running executions
   aws stepfunctions list-executions \
     --state-machine-arn $(cd terraform && terraform output -raw ingestion_state_machine_arn) \
     --status-filter RUNNING \
     --profile DEVcloud
   
   # Stop each execution
   for arn in $(aws stepfunctions list-executions \
     --state-machine-arn $(cd terraform && terraform output -raw ingestion_state_machine_arn) \
     --status-filter RUNNING \
     --query 'executions[*].executionArn' \
     --output text \
     --profile DEVcloud); do
     aws stepfunctions stop-execution --execution-arn $arn --profile DEVcloud
   done
   ```

3. **Notify Team**: Send notification about rollback

4. **Investigate Issue**: Review logs and metrics to identify root cause


### Gradual Rollback (Controlled)

**Scenario**: Issues discovered during gradual rollout, need to reduce traffic

**Phase 1 → Phase 0 (100% → 0%)**:

1. **Update Trigger Lambda** to use old state machine (if Lambda-based fallback exists):
   ```bash
   # Get old state machine ARN (from backup)
   OLD_STATE_MACHINE_ARN="arn:aws:states:region:account:stateMachine:old-pipeline"
   
   # Update trigger Lambda environment
   aws lambda update-function-configuration \
     --function-name $(cd terraform && terraform output -raw trigger_lambda_name) \
     --environment Variables={STATE_MACHINE_ARN=$OLD_STATE_MACHINE_ARN} \
     --profile DEVcloud
   ```

2. **Monitor Old Pipeline**: Verify Lambda-based pipeline is working

3. **Document Issues**: Record what went wrong for future fixes

### Full Terraform Rollback

**Scenario**: Need to completely revert infrastructure changes

**Steps**:

1. **Checkout Previous Version**:
   ```bash
   cd terraform
   git log --oneline  # Find commit before ECS migration
   git checkout <previous-commit>
   ```

2. **Review Changes**:
   ```bash
   terraform plan -var-file=terraform.tfvars
   ```

3. **Apply Previous Configuration**:
   ```bash
   terraform apply -var-file=terraform.tfvars
   ```

4. **Verify Rollback**:
   ```bash
   # Check state machine definition
   aws stepfunctions describe-state-machine \
     --state-machine-arn $(terraform output -raw ingestion_state_machine_arn) \
     --profile DEVcloud
   
   # Test with sample file
   aws s3 cp test-file.nc s3://$(terraform output -raw raw_bucket_name)/ingestion/
   ```

### Rollback Checklist

- [ ] Stop new executions (disable S3 notifications)
- [ ] Stop running executions
- [ ] Notify team and stakeholders
- [ ] Document issue and root cause
- [ ] Revert infrastructure (Terraform or Lambda config)
- [ ] Verify old pipeline is working
- [ ] Test with sample files
- [ ] Re-enable S3 notifications
- [ ] Monitor for stability
- [ ] Plan fix for issues
- [ ] Schedule re-deployment

---

## Cost Management

### Expected Costs

**ECS-based Implementation** (per file):
- Zarr Conversion: ~$0.01 (15 min × 0.5 vCPU + 2GB)
- COG Generation: ~$0.01 (10 min × 0.5 vCPU + 2GB)
- STAC Creator Lambda: ~$0.001
- STAC Indexer Lambda: ~$0.001
- Step Functions: ~$0.001
- **Total: ~$0.02 per file**

**Lambda-based Implementation** (per file):
- Zarr Conversion: ~$2.50 (15 min × 10GB Lambda)
- COG Generation: ~$2.50 (15 min × 10GB Lambda)
- Other: ~$0.02
- **Total: ~$5.02 per file**

**Savings: 98% ($4.94 per file)**


### Monitoring Costs

**Using AWS Cost Explorer**:

1. Navigate to: AWS Console → Cost Management → Cost Explorer
2. Filter by:
   - Service: ECS, Step Functions
   - Tag: Project = {project_name}
3. Group by: Service
4. Time range: Last 30 days

**Using Monitoring Script**:
```bash
./scripts/monitor-ingestion-pipeline.sh
# Select option 7: Show cost estimation
```

**Using CLI**:
```bash
# Get ECS costs for last 30 days
aws ce get-cost-and-usage \
  --time-period Start=$(date -u -d '30 days ago' +%Y-%m-%d),End=$(date -u +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --filter file://<(echo '{
    "And": [
      {"Dimensions": {"Key": "SERVICE", "Values": ["Amazon Elastic Container Service"]}},
      {"Tags": {"Key": "Project", "Values": ["'$(cd terraform && terraform output -raw project_name)'"]}}
    ]
  }') \
  --profile DEVcloud
```

### Cost Optimization Tips

1. **Right-size Tasks**: Monitor CPU/memory utilization and adjust
   - If utilization <30%, reduce resources
   - If utilization >80%, increase resources

2. **Use Spot Instances**: For non-critical workloads (70% cost reduction)
   ```hcl
   capacity_provider_strategy {
     capacity_provider = "FARGATE_SPOT"
     weight            = 100
   }
   ```

3. **Batch Processing**: Process multiple files per task to amortize startup overhead

4. **S3 Lifecycle Policies**: Archive old data to Glacier
   ```bash
   aws s3api put-bucket-lifecycle-configuration \
     --bucket $(cd terraform && terraform output -raw zarr_bucket_name) \
     --lifecycle-configuration file://lifecycle-policy.json \
     --profile DEVcloud
   ```

5. **Monitor Execution Frequency**: Ensure no duplicate processing

### Cost Alerts

**Set Up Budget Alert**:
```bash
# Create budget for ingestion pipeline
aws budgets create-budget \
  --account-id $(aws sts get-caller-identity --query Account --output text) \
  --budget file://budget-config.json \
  --notifications-with-subscribers file://budget-notifications.json \
  --profile DEVcloud
```

**Example budget-config.json**:
```json
{
  "BudgetName": "ingestion-pipeline-monthly",
  "BudgetLimit": {
    "Amount": "50",
    "Unit": "USD"
  },
  "TimeUnit": "MONTHLY",
  "BudgetType": "COST",
  "CostFilters": {
    "TagKeyValue": ["user:Project$[YOURORG]-cloud"]
  }
}
```


---

## Decommissioning Legacy Components

### Overview

After the ECS-based pipeline has been running successfully in production for a sustained period
(recommended: 30 days), you may choose to decommission the legacy Lambda-based Zarr converter
and potentially OpenSearch if it's no longer needed.

**IMPORTANT**: Do not decommission components until you have:
- ✅ 30+ days of stable ECS pipeline operation
- ✅ Success rate >95% sustained
- ✅ Cost savings verified
- ✅ Team comfortable with new pipeline
- ✅ Rollback plan tested
- ✅ Stakeholder approval

### Lambda Functions Decommissioning

#### Components to Potentially Decommission

1. **Zarr Converter Lambda** (`{project}-zarr-converter`)
   - **Status**: Replaced by ECS task
   - **Safe to remove**: Yes, after validation period
   - **Rollback impact**: High - keep for 90 days as emergency fallback

2. **COG Generator Lambda** (if it existed)
   - **Status**: May have been replaced by ECS task
   - **Safe to remove**: Yes, after validation period
   - **Rollback impact**: High - keep for 90 days as emergency fallback

3. **STAC Creator Lambda** (`{project}-stac-creator`)
   - **Status**: Still in use
   - **Safe to remove**: NO - still required
   - **Rollback impact**: N/A

4. **STAC Indexer Lambda** (`{project}-stac-indexer`)
   - **Status**: Still in use
   - **Safe to remove**: NO - still required
   - **Rollback impact**: N/A

#### Decommissioning Process for Zarr Converter Lambda

**Phase 1: Disable (Week 1-4)**

1. **Remove from Step Functions** (already done during migration)
   - Verify Lambda is no longer invoked
   - Check CloudWatch metrics for invocations

2. **Monitor for Accidental Invocations**:
   ```bash
   # Check if Lambda is still being invoked
   aws cloudwatch get-metric-statistics \
     --namespace AWS/Lambda \
     --metric-name Invocations \
     --dimensions Name=FunctionName,Value=$(cd terraform && terraform output -raw zarr_converter_lambda_name) \
     --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
     --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
     --period 86400 \
     --statistics Sum \
     --profile DEVcloud
   ```

3. **Document Current State**:
   ```bash
   # Save Lambda configuration for reference
   aws lambda get-function \
     --function-name $(cd terraform && terraform output -raw zarr_converter_lambda_name) \
     --profile DEVcloud > lambda-zarr-converter-backup.json
   ```

**Phase 2: Archive (Week 5-12)**

1. **Reduce Concurrency** (prevent accidental use):
   ```bash
   aws lambda put-function-concurrency \
     --function-name $(cd terraform && terraform output -raw zarr_converter_lambda_name) \
     --reserved-concurrent-executions 0 \
     --profile DEVcloud
   ```

2. **Tag for Deletion**:
   ```bash
   aws lambda tag-resource \
     --resource $(aws lambda get-function \
       --function-name $(cd terraform && terraform output -raw zarr_converter_lambda_name) \
       --query 'Configuration.FunctionArn' \
       --output text \
       --profile DEVcloud) \
     --tags Status=Deprecated,DecommissionDate=$(date -u -d '90 days' +%Y-%m-%d) \
     --profile DEVcloud
   ```

3. **Reduce Log Retention**:
   ```bash
   aws logs put-retention-policy \
     --log-group-name /aws/lambda/$(cd terraform && terraform output -raw zarr_converter_lambda_name) \
     --retention-in-days 7 \
     --profile DEVcloud
   ```


**Phase 3: Delete (After 90 days)**

1. **Final Verification**:
   - Confirm no invocations in last 90 days
   - Verify ECS pipeline is stable
   - Get stakeholder approval

2. **Delete Lambda Function**:
   ```bash
   # Delete function
   aws lambda delete-function \
     --function-name $(cd terraform && terraform output -raw zarr_converter_lambda_name) \
     --profile DEVcloud
   ```

3. **Delete CloudWatch Logs** (optional, logs auto-expire):
   ```bash
   aws logs delete-log-group \
     --log-group-name /aws/lambda/$(cd terraform && terraform output -raw zarr_converter_lambda_name) \
     --profile DEVcloud
   ```

4. **Remove from Terraform**:
   ```bash
   # Comment out or remove Lambda resource from terraform/modules/ingestion/main.tf
   # Then apply
   cd terraform
   terraform plan  # Review changes
   terraform apply # Remove from state
   ```

5. **Delete Deployment Package**:
   ```bash
   # Remove Lambda zip file
   rm terraform/modules/ingestion/lambda_packages/zarr_converter.zip
   ```

6. **Update Documentation**:
   - Remove Lambda references from docs
   - Update architecture diagrams
   - Update runbooks

#### What NOT to Delete

**Keep These Lambda Functions**:
- ✅ STAC Creator Lambda - still required for metadata generation
- ✅ STAC Indexer Lambda - still required for OpenSearch indexing
- ✅ Ingestion Trigger Lambda - still required to start Step Functions

**Keep These IAM Roles** (may be shared):
- ✅ Lambda execution role (used by other Lambdas)
- ✅ Step Functions execution role
- ✅ ECS task execution role
- ✅ ECS task role

### OpenSearch Decommissioning

#### Should You Decommission OpenSearch?

**Keep OpenSearch if**:
- ✅ You use STAC API for data discovery
- ✅ You have external clients querying the catalog
- ✅ You need full-text search on metadata
- ✅ You use OpenSearch dashboards for visualization

**Consider Decommissioning if**:
- ❌ No clients are using STAC API
- ❌ All queries go directly to S3
- ❌ Cost is a concern (OpenSearch can be expensive)
- ❌ You're migrating to DynamoDB for STAC storage

#### OpenSearch Migration to DynamoDB (Alternative)

If you want to reduce costs but keep STAC functionality, consider migrating from OpenSearch
to DynamoDB:

**Benefits**:
- 90% cost reduction vs OpenSearch
- Serverless, no cluster management
- Better integration with AWS services
- Pay-per-request pricing

**Migration Path**:
1. Deploy DynamoDB table for STAC items
2. Update STAC Indexer Lambda to write to DynamoDB
3. Migrate existing STAC items from OpenSearch to DynamoDB
4. Update STAC API to query DynamoDB
5. Test thoroughly
6. Decommission OpenSearch

**See**: `docs/DYNAMODB_MIGRATION_GUIDE.md` for detailed instructions


#### OpenSearch Decommissioning Process

**CRITICAL**: Only proceed if you're certain OpenSearch is not needed.

**Phase 1: Assessment (Week 1-2)**

1. **Check Usage**:
   ```bash
   # Check OpenSearch request count
   aws cloudwatch get-metric-statistics \
     --namespace AWS/ES \
     --metric-name SearchableDocuments \
     --dimensions Name=DomainName,Value=$(cd terraform && terraform output -raw opensearch_domain_name) \
     --start-time $(date -u -d '30 days ago' +%Y-%m-%dT%H:%M:%S) \
     --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
     --period 86400 \
     --statistics Average \
     --profile DEVcloud
   
   # Check API access logs
   aws logs filter-log-events \
     --log-group-name /aws/opensearch/$(cd terraform && terraform output -raw opensearch_domain_name) \
     --filter-pattern "INDEX" \
     --start-time $(date -u -d '7 days ago' +%s)000 \
     --profile DEVcloud
   ```

2. **Identify Clients**:
   - Review application logs for OpenSearch queries
   - Check API Gateway logs for STAC API usage
   - Survey team for OpenSearch dependencies

3. **Document Decision**:
   - Create decision document with stakeholder approval
   - Document alternative solutions (DynamoDB, direct S3 access)
   - Get sign-off from all affected teams

**Phase 2: Disable Indexing (Week 3-4)**

1. **Stop STAC Indexer Lambda**:
   ```bash
   # Disable Lambda (set concurrency to 0)
   aws lambda put-function-concurrency \
     --function-name $(cd terraform && terraform output -raw stac_indexer_lambda_name) \
     --reserved-concurrent-executions 0 \
     --profile DEVcloud
   ```

2. **Monitor for Issues**:
   - Check if any services break
   - Verify STAC files are still created in S3
   - Confirm no critical dependencies

3. **Wait Period**: 2 weeks to ensure no issues

**Phase 3: Snapshot and Delete (Week 5+)**

1. **Create Final Snapshot**:
   ```bash
   # Create manual snapshot
   aws opensearch create-domain \
     --domain-name $(cd terraform && terraform output -raw opensearch_domain_name)-final-snapshot \
     --profile DEVcloud
   ```

2. **Export Data** (if needed for migration):
   ```bash
   # Export all STAC items
   python scripts/export_opensearch_data.py \
     --domain $(cd terraform && terraform output -raw opensearch_domain_endpoint) \
     --output stac-export.json
   ```

3. **Delete OpenSearch Domain**:
   ```bash
   # Via Terraform (recommended)
   cd terraform
   # Comment out opensearch module in main.tf
   terraform plan  # Review changes
   terraform apply # Delete domain
   
   # Or via CLI (not recommended)
   aws opensearch delete-domain \
     --domain-name $(cd terraform && terraform output -raw opensearch_domain_name) \
     --profile DEVcloud
   ```

4. **Clean Up Related Resources**:
   - Delete OpenSearch service-linked role (if not used elsewhere)
   - Remove OpenSearch security groups
   - Delete CloudWatch log groups
   - Remove IAM policies for OpenSearch access

5. **Update Code**:
   - Remove STAC Indexer Lambda (or update to use DynamoDB)
   - Update Step Functions to skip indexing step (or use DynamoDB)
   - Remove OpenSearch client code from applications

**Phase 4: Verification (Week 6+)**

1. **Verify Cost Savings**:
   ```bash
   # Check OpenSearch costs are gone
   aws ce get-cost-and-usage \
     --time-period Start=$(date -u -d '30 days ago' +%Y-%m-%d),End=$(date -u +%Y-%m-%d) \
     --granularity MONTHLY \
     --metrics BlendedCost \
     --filter file://<(echo '{"Dimensions": {"Key": "SERVICE", "Values": ["Amazon OpenSearch Service"]}}') \
     --profile DEVcloud
   ```

2. **Confirm No Errors**: Check application logs for OpenSearch-related errors

3. **Update Documentation**: Remove OpenSearch references from all docs


### Decommissioning Checklist

#### Lambda Functions (Zarr Converter)

**Before Decommissioning**:
- [ ] ECS pipeline stable for 30+ days
- [ ] Success rate >95%
- [ ] Zero Lambda invocations for 30 days
- [ ] Rollback plan tested
- [ ] Stakeholder approval obtained
- [ ] Documentation updated

**Decommissioning Steps**:
- [ ] Phase 1: Disable (set concurrency to 0)
- [ ] Phase 2: Archive (reduce log retention, tag for deletion)
- [ ] Phase 3: Delete (after 90 days)
- [ ] Remove from Terraform
- [ ] Delete deployment packages
- [ ] Update documentation

**Post-Decommissioning**:
- [ ] Verify no errors in applications
- [ ] Confirm cost savings
- [ ] Archive Lambda configuration for reference

#### OpenSearch (If Applicable)

**Before Decommissioning**:
- [ ] Confirm no clients using OpenSearch
- [ ] Alternative solution in place (DynamoDB or direct S3)
- [ ] Data exported/migrated
- [ ] Stakeholder approval obtained
- [ ] 30-day notice period completed

**Decommissioning Steps**:
- [ ] Phase 1: Assessment (check usage, identify clients)
- [ ] Phase 2: Disable indexing (stop STAC Indexer)
- [ ] Phase 3: Snapshot and delete domain
- [ ] Clean up related resources
- [ ] Update code to remove OpenSearch dependencies
- [ ] Phase 4: Verification (confirm no errors, verify savings)

**Post-Decommissioning**:
- [ ] Verify applications work without OpenSearch
- [ ] Confirm cost savings (typically $100-500/month)
- [ ] Update architecture diagrams
- [ ] Archive OpenSearch configuration

### Cost Impact of Decommissioning

**Lambda Zarr Converter Removal**:
- Savings: $0 (already not in use)
- Risk: Low (ECS replacement proven)

**OpenSearch Removal**:
- Savings: $100-500/month (depending on instance size)
- Risk: High (if clients depend on it)
- Alternative: DynamoDB ($5-20/month)

**Total Potential Savings**: $100-500/month from OpenSearch decommissioning

### Emergency Re-enablement

If you need to quickly re-enable a decommissioned component:

**Lambda Function**:
```bash
# Restore from backup
aws lambda create-function \
  --cli-input-json file://lambda-zarr-converter-backup.json \
  --profile DEVcloud

# Or redeploy from code
cd terraform
git checkout <commit-with-lambda>
terraform apply
```

**OpenSearch**:
```bash
# Restore from snapshot
aws opensearch create-domain \
  --domain-name $(cd terraform && terraform output -raw opensearch_domain_name) \
  --snapshot-options SnapshotOptions={AutomatedSnapshotStartHour=0} \
  --profile DEVcloud

# Restore data from export
python scripts/import_opensearch_data.py \
  --domain $(cd terraform && terraform output -raw opensearch_domain_endpoint) \
  --input stac-export.json
```

---

## Appendix

### Useful Commands Reference

**Check Pipeline Health**:
```bash
./scripts/monitor-ingestion-pipeline.sh
```

**View Recent Executions**:
```bash
aws stepfunctions list-executions \
  --state-machine-arn $(cd terraform && terraform output -raw ingestion_state_machine_arn) \
  --max-results 10 \
  --profile DEVcloud
```

**Tail Logs**:
```bash
aws logs tail /ecs/zarr-conversion --follow --profile DEVcloud
```

**Check Alarm Status**:
```bash
aws cloudwatch describe-alarms \
  --alarm-name-prefix "$(cd terraform && terraform output -raw project_name)-ingestion" \
  --profile DEVcloud
```

**Estimate Costs**:
```bash
./scripts/monitor-ingestion-pipeline.sh
# Select option 7
```

### Related Documentation

- [ECS Migration Deployment Guide](ECS_MIGRATION_DEPLOYMENT.md)
- [Ingestion Pipeline Monitoring](INGESTION_PIPELINE_MONITORING.md)
- [Task 10 Deployment Checklist](TASK_10_DEPLOYMENT_CHECKLIST.md)
- [Design Document](../.kiro/specs/ecs-zarr-conversion-migration/design.md)
- [Requirements Document](../.kiro/specs/ecs-zarr-conversion-migration/requirements.md)

### Support and Escalation

**For Issues**:
1. Check this runbook for troubleshooting steps
2. Review CloudWatch logs and metrics
3. Check AWS Service Health Dashboard
4. Contact platform team

**For Questions**:
- Consult design document for architecture details
- Review monitoring guide for metrics interpretation
- Check deployment guide for infrastructure details

---

**Document Version**: 1.0  
**Last Updated**: 2024  
**Maintained By**: Platform Team

