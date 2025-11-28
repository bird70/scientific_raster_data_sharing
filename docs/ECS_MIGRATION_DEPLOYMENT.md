# ECS Zarr Conversion Migration - Deployment Guide

This guide covers the deployment and testing of the ECS-based Zarr conversion migration.

## Overview

The migration moves the NetCDF to Zarr conversion from AWS Lambda to ECS Fargate, providing:
- **No timeout limits** (Lambda has 15-minute max)
- **98% cost reduction** ($5.02 → $0.08 per file)
- **Improved reliability** for large file processing

## Prerequisites

1. **AWS CLI** configured with profile `DEVcloud`
2. **Terraform** installed (v1.0+)
3. **Python 3.11+** with pytest installed
4. **AWS Permissions** for:
   - ECS (task definitions, clusters)
   - Step Functions (state machines)
   - S3 (bucket access)
   - CloudWatch Logs
   - IAM (roles and policies)

## Deployment Steps

### Option 1: Automated Deployment (Recommended)

#### On Linux/Mac:
```bash
chmod +x scripts/deploy-and-test-ecs-migration.sh
./scripts/deploy-and-test-ecs-migration.sh
```

#### On Windows:
```powershell
.\scripts\deploy-and-test-ecs-migration.ps1
```

The script will:
1. Run `terraform plan` and show changes
2. Prompt for confirmation
3. Apply Terraform changes
4. Optionally run integration tests
5. Display monitoring commands

### Option 2: Manual Deployment

#### Step 1: Review Terraform Changes

```bash
export AWS_PROFILE=DEVcloud
cd terraform
terraform plan -var-file=terraform.tfvars
```

Review the changes carefully. Key resources being modified:
- Step Functions state machine (ConvertToZarr and GenerateCOG states)
- ECS task definitions (resource allocation)
- IAM roles and policies
- CloudWatch log groups

#### Step 2: Apply Changes

```bash
terraform apply -var-file=terraform.tfvars
```

#### Step 3: Verify Deployment

```bash
# Get deployed resources
terraform output

# Verify ECS task definitions
aws ecs describe-task-definition \
  --task-definition zarr-conversion \
  --profile DEVcloud

# Verify Step Functions state machine
aws stepfunctions describe-state-machine \
  --state-machine-arn $(terraform output -raw state_machine_arn) \
  --profile DEVcloud
```

## Testing

### Integration Test

The integration test validates the complete end-to-end pipeline:

```bash
cd app

# Set environment variables
export AWS_PROFILE=DEVcloud
export RUN_INTEGRATION_TESTS=true
export RAW_BUCKET=$(cd ../terraform && terraform output -raw raw_bucket_name)
export ZARR_BUCKET=$(cd ../terraform && terraform output -raw zarr_bucket_name)
export COG_BUCKET=$(cd ../terraform && terraform output -raw cog_bucket_name)
export STAC_BUCKET=$(cd ../terraform && terraform output -raw stac_bucket_name)
export STATE_MACHINE_ARN=$(cd ../terraform && terraform output -raw state_machine_arn)

# Run integration test
pytest tests/integration/test_ingestion_pipeline.py::test_end_to_end_pipeline -v -s
```

The test will:
1. Upload a test NetCDF file to S3
2. Wait for Step Functions execution to complete (max 30 minutes)
3. Verify execution status is SUCCEEDED
4. Verify all output files exist (Zarr, COG, STAC)
5. Verify STAC item contains bounding box
6. Verify STAC item contains both assets

### Manual Testing

#### Upload Test File

```bash
aws s3 cp data/A2002070120230731_MC_SST_std_coastal_v05.nc \
  s3://$(cd terraform && terraform output -raw raw_bucket_name)/ingestion/ \
  --profile DEVcloud
```

#### Monitor Step Functions Execution

1. Open AWS Console: https://console.aws.amazon.com/states/home?region=ap-southeast-2
2. Find your state machine
3. View recent executions
4. Click on an execution to see the visual workflow

Or use CLI:
```bash
aws stepfunctions list-executions \
  --state-machine-arn $(cd terraform && terraform output -raw state_machine_arn) \
  --profile DEVcloud
```

#### Check CloudWatch Logs

```bash
# Zarr conversion logs
aws logs tail /ecs/zarr-conversion --follow --profile DEVcloud

# COG generation logs
aws logs tail /ecs/cog-generation --follow --profile DEVcloud
```

#### Verify Output Files

```bash
# List Zarr files
aws s3 ls s3://$(cd terraform && terraform output -raw zarr_bucket_name)/zarr/ \
  --profile DEVcloud

# List COG files
aws s3 ls s3://$(cd terraform && terraform output -raw cog_bucket_name)/cog/ \
  --profile DEVcloud

# List STAC items
aws s3 ls s3://$(cd terraform && terraform output -raw stac_bucket_name)/stac/ \
  --profile DEVcloud
```

#### Download and Inspect STAC Item

```bash
aws s3 cp \
  s3://$(cd terraform && terraform output -raw stac_bucket_name)/stac/A2002070120230731_MC_SST_std_coastal_v05.json \
  - \
  --profile DEVcloud | jq .
```

Verify:
- `bbox` field exists with 4 elements [west, south, east, north]
- `assets.zarr.href` points to correct S3 URI
- `assets.cog.href` points to correct S3 URI
- `geometry` is a valid polygon

## Monitoring

### CloudWatch Metrics

Key metrics to monitor:

1. **Step Functions**:
   - `ExecutionsFailed`: Should be <5%
   - `ExecutionTime`: Should be 15-25 minutes
   - `ExecutionsStarted`: Number of pipeline runs

2. **ECS Tasks**:
   - `CPUUtilization`: Should average 30-50%
   - `MemoryUtilization`: Should stay under 80%
   - `TaskCount`: Number of running tasks

### CloudWatch Alarms

The deployment includes alarms for:
- High failure rate (>5 failures in 5 minutes)
- Long execution time (>30 minutes)

Alarms send notifications to the configured SNS topic.

### Cost Monitoring

Use AWS Cost Explorer to track costs:

```bash
# View ECS Fargate costs
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --filter file://cost-filter.json \
  --profile DEVcloud
```

Expected costs:
- **Per file**: ~$0.08 (vs $5.02 with Lambda)
- **Per 100 files/month**: ~$8 (vs $502)
- **Annual savings**: ~$5,928

## Troubleshooting

### ECS Task Fails to Start

**Symptoms**: Step Functions shows "TaskFailed" immediately

**Possible Causes**:
1. Container image not found in ECR
2. Insufficient IAM permissions
3. Network configuration issues

**Solutions**:
```bash
# Check ECS task definition
aws ecs describe-task-definition \
  --task-definition zarr-conversion \
  --profile DEVcloud

# Check IAM role permissions
aws iam get-role-policy \
  --role-name ecs-task-role \
  --policy-name ecs-task-policy \
  --profile DEVcloud

# Check security group rules
aws ec2 describe-security-groups \
  --group-ids $(cd terraform && terraform output -raw ecs_security_group_id) \
  --profile DEVcloud
```

### ECS Task Times Out

**Symptoms**: Task runs for 30+ minutes without completing

**Possible Causes**:
1. Large NetCDF file (>100MB)
2. Network issues downloading from S3
3. Insufficient memory/CPU

**Solutions**:
```bash
# Check CloudWatch logs for errors
aws logs tail /ecs/zarr-conversion --since 30m --profile DEVcloud

# Increase task resources (edit terraform/modules/ecs/main.tf)
# Change cpu = "512" to cpu = "1024"
# Change memory = "2048" to memory = "4096"
```

### STAC Item Missing Bounding Box

**Symptoms**: STAC item created but bbox field is missing or invalid

**Possible Causes**:
1. NetCDF file missing coordinate variables
2. Metadata file not created by zarr_converter
3. STAC creator Lambda not reading metadata

**Solutions**:
```bash
# Check if metadata file exists
aws s3 ls s3://$(cd terraform && terraform output -raw zarr_bucket_name)/zarr/ \
  --recursive | grep metadata.json \
  --profile DEVcloud

# Download and inspect metadata
aws s3 cp \
  s3://$(cd terraform && terraform output -raw zarr_bucket_name)/zarr/filename_metadata.json \
  - \
  --profile DEVcloud | jq .

# Check STAC creator Lambda logs
aws logs tail /aws/lambda/stac-creator --since 30m --profile DEVcloud
```

### Integration Test Fails

**Symptoms**: pytest test fails with timeout or assertion error

**Possible Causes**:
1. Missing environment variables
2. Insufficient AWS permissions
3. Test file not found

**Solutions**:
```bash
# Verify environment variables
echo "RAW_BUCKET: $RAW_BUCKET"
echo "ZARR_BUCKET: $ZARR_BUCKET"
echo "COG_BUCKET: $COG_BUCKET"
echo "STATE_MACHINE_ARN: $STATE_MACHINE_ARN"

# Verify test file exists
ls -lh data/A2002070120230731_MC_SST_std_coastal_v05.nc

# Run with verbose output
pytest tests/integration/test_ingestion_pipeline.py::test_end_to_end_pipeline -v -s --log-cli-level=DEBUG
```

## Rollback

If issues are discovered after deployment:

### Quick Rollback (Use Previous State Machine)

```bash
# Update trigger Lambda to use old state machine ARN
aws lambda update-function-configuration \
  --function-name ingestion-trigger \
  --environment Variables={STATE_MACHINE_ARN=<old-arn>} \
  --profile DEVcloud
```

### Full Rollback (Revert Terraform)

```bash
cd terraform

# Checkout previous version
git checkout HEAD~1

# Apply previous configuration
terraform apply -var-file=terraform.tfvars
```

## Next Steps

After successful deployment:

1. **Monitor for 24 hours**: Watch CloudWatch metrics and logs
2. **Process test files**: Upload 5-10 test files and verify outputs
3. **Gradual rollout**: If using traffic splitting, increase to 100%
4. **Update documentation**: Document any issues or learnings
5. **Clean up old resources**: Remove Lambda-based Zarr converter (if fully migrated)

## Support

For issues or questions:
- Check CloudWatch Logs for detailed error messages
- Review Step Functions execution history
- Consult the design document: `.kiro/specs/ecs-zarr-conversion-migration/design.md`
- Contact the platform team

## References

- [ECS Zarr Migration Runbook](ECS_ZARR_MIGRATION_RUNBOOK.md) - **Operations guide for day-to-day management**
- [ResultSelector Data Flow Pattern](RESULTSELECTOR_DATA_FLOW_PATTERN.md) - Technical deep-dive on data flow
- [Ingestion Pipeline Monitoring](INGESTION_PIPELINE_MONITORING.md) - Monitoring and cost verification
- [Design Document](../.kiro/specs/ecs-zarr-conversion-migration/design.md)
- [Requirements Document](../.kiro/specs/ecs-zarr-conversion-migration/requirements.md)
- [Task List](../.kiro/specs/ecs-zarr-conversion-migration/tasks.md)
- [AWS ECS Documentation](https://docs.aws.amazon.com/ecs/)
- [AWS Step Functions Documentation](https://docs.aws.amazon.com/step-functions/)
