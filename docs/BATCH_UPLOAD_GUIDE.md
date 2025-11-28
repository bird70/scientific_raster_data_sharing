# Batch Upload Guide for NetCDF Files

## Overview

This guide explains how to upload large batches of NetCDF files to the ingestion pipeline efficiently and safely. The system is designed to handle concurrent processing of multiple files through AWS Step Functions, ECS Fargate tasks, and Lambda functions.

## System Capacity

### Concurrency Limits

| Component | Default Limit | Your Usage (250 files) | Status |
|-----------|---------------|------------------------|--------|
| **Step Functions** | 1,000 concurrent executions | 250 executions | ✅ Safe |
| **ECS Fargate Tasks** | 1,000 concurrent tasks | 250 tasks | ✅ Safe |
| **Lambda Functions** | 1,000 concurrent executions | 250 executions | ✅ Safe |
| **S3 PUT Requests** | 3,500 requests/second/prefix | <1 req/sec | ✅ Safe |

### Resource Requirements per File

**Zarr Conversion (ECS Task):**
- CPU: 0.5 vCPU
- Memory: 2 GB
- Duration: ~30-60 seconds (30MB file)

**COG Generation (ECS Task):**
- CPU: 2 vCPU
- Memory: 4 GB
- Duration: ~60-120 seconds

**Total for 250 files:**
- Peak CPU: 125 vCPUs (Zarr) + 500 vCPUs (COG) = 625 vCPUs
- Peak Memory: 500 GB (Zarr) + 1000 GB (COG) = 1.5 TB
- **Well within AWS Fargate limits** ✅

## Upload Strategies

### Strategy 1: Upload All at Once (Recommended)

**Best for:** 250-1000 files, fastest processing

**Advantages:**
- Fastest overall completion time (10-20 minutes)
- Simplest approach
- System handles queuing automatically
- Built-in retry logic

**Command:**
```powershell
# PowerShell
aws s3 sync ./local-netcdf-folder/ s3://your-raw-bucket/ingestion/ --profile DEVcloud

# Or use the batch upload script
./scripts/batch-upload-netcdf.ps1 -LocalFolder "C:\path\to\netcdf\files"
```

**Expected Behavior:**
1. All 250 files upload to S3 (1-5 minutes depending on bandwidth)
2. S3 triggers Lambda for each file immediately
3. Step Functions executions start (250 concurrent)
4. ECS tasks spin up in waves (30-60 seconds startup time)
5. Processing completes in parallel
6. Total time: **10-20 minutes**

### Strategy 2: Controlled Batching

**Best for:** >1000 files, cost monitoring, gradual processing

**Advantages:**
- Easier to monitor progress
- Can pause/resume if issues arise
- Spreads CloudWatch log writes over time
- Better for cost tracking

**Command:**
```powershell
# Upload in batches of 50 files with 2-minute delays
./scripts/batch-upload-netcdf.ps1 -LocalFolder "C:\path\to\files" -BatchSize 50 -DelayBetweenBatches 120
```

**Expected Behavior:**
1. Uploads 50 files
2. Waits 2 minutes
3. Uploads next 50 files
4. Repeats until complete
5. Total time: **30-40 minutes** (for 250 files)

### Strategy 3: Parallel Upload with Rate Limiting

**Best for:** Fast upload with some control

**Command:**
```powershell
# Upload 10 files at a time in parallel
$files = Get-ChildItem ./local-netcdf-folder/*.nc

$files | ForEach-Object -Parallel {
    aws s3 cp $_.FullName s3://your-raw-bucket/ingestion/$($_.Name) --profile DEVcloud
} -ThrottleLimit 10
```

## Cost Estimation

### Per File Costs (30MB average file)

| Component | Cost per File |
|-----------|---------------|
| Zarr Conversion (ECS) | $0.01 |
| COG Generation (ECS) | $0.02 |
| Step Functions | $0.0001 |
| Lambda (STAC) | $0.001 |
| **Total per file** | **~$0.03** |

### Batch Costs

| Batch Size | Estimated Cost |
|------------|----------------|
| 100 files | $3.00 |
| 250 files | $7.50 |
| 500 files | $15.00 |
| 1,000 files | $30.00 |

**Note:** Plus S3 storage costs (minimal for first month with free tier)

## Using the Batch Upload Script

### Basic Usage

```powershell
# Upload all files at once
./scripts/batch-upload-netcdf.ps1 -LocalFolder "C:\data\netcdf"
```

### Advanced Usage

```powershell
# Upload in batches of 50 with 2-minute delays
./scripts/batch-upload-netcdf.ps1 `
    -LocalFolder "C:\data\netcdf" `
    -BatchSize 50 `
    -DelayBetweenBatches 120
```

### Script Features

- ✅ Validates files before upload
- ✅ Shows progress for each file
- ✅ Counts successes and failures
- ✅ Reports upload duration
- ✅ Checks Step Functions status after upload
- ✅ Provides monitoring commands

## Monitoring Batch Uploads

### Real-Time Monitoring

**Monitor Step Functions Executions:**
```powershell
# Count running executions
aws stepfunctions list-executions `
    --state-machine-arn YOUR_STATE_MACHINE_ARN `
    --status-filter RUNNING `
    --profile DEVcloud `
    --query 'executions | length(@)'

# List recent executions
aws stepfunctions list-executions `
    --state-machine-arn YOUR_STATE_MACHINE_ARN `
    --max-results 20 `
    --profile DEVcloud `
    --query 'executions[*].[name,status,startDate]' `
    --output table
```

**Monitor ECS Tasks:**
```powershell
# Count running tasks
aws ecs list-tasks `
    --cluster cloud-scientific-raster-sharing-ecs-cluster `
    --profile DEVcloud `
    --query 'taskArns | length(@)'

# Get task details
aws ecs describe-tasks `
    --cluster cloud-scientific-raster-sharing-ecs-cluster `
    --tasks $(aws ecs list-tasks --cluster cloud-scientific-raster-sharing-ecs-cluster --profile DEVcloud --query 'taskArns[0]' --output text) `
    --profile DEVcloud
```

**Check for Failures:**
```powershell
# List failed executions
aws stepfunctions list-executions `
    --state-machine-arn YOUR_STATE_MACHINE_ARN `
    --status-filter FAILED `
    --profile DEVcloud `
    --query 'executions[*].[name,stopDate]' `
    --output table
```

### Using the Monitoring Script

```powershell
# Continuous monitoring
./scripts/monitor-ingestion-pipeline.ps1

# Or use the bash version
./scripts/monitor-ingestion-pipeline.sh
```

### CloudWatch Metrics

Monitor these metrics in CloudWatch:

**Step Functions:**
- `ExecutionsStarted` - Total executions triggered
- `ExecutionsSucceeded` - Successful completions
- `ExecutionsFailed` - Failed executions
- `ExecutionTime` - Processing duration

**ECS:**
- `CPUUtilization` - Task CPU usage
- `MemoryUtilization` - Task memory usage
- `RunningTasksCount` - Active tasks

**DynamoDB (STAC Index):**
- `ConsumedWriteCapacityUnits` - Write throughput
- `ThrottledRequests` - Rate limiting events

## Potential Issues & Solutions

### Issue 1: DynamoDB Throttling

**Symptom:**
```
ProvisionedThroughputExceededException: The level of configured provisioned throughput for the table was exceeded
```

**Cause:** Too many concurrent STAC indexing operations

**Solution:**
```powershell
# Check current capacity mode
aws dynamodb describe-table `
    --table-name cloud-scientific-raster-sharing-stac-items `
    --profile DEVcloud `
    --query 'Table.BillingModeSummary'

# If using provisioned mode, switch to on-demand (auto-scales)
aws dynamodb update-table `
    --table-name cloud-scientific-raster-sharing-stac-items `
    --billing-mode PAY_PER_REQUEST `
    --profile DEVcloud
```

### Issue 2: ECS Task Limit Reached

**Symptom:** Tasks stuck in PENDING state, not starting

**Cause:** Hit Fargate service quota

**Solution:**
```powershell
# Check current quota
aws service-quotas get-service-quota `
    --service-code fargate `
    --quota-code L-3032A538 `
    --profile DEVcloud

# Request increase if needed (usually 1000 is sufficient)
aws service-quotas request-service-quota-increase `
    --service-code fargate `
    --quota-code L-3032A538 `
    --desired-value 2000 `
    --profile DEVcloud
```

### Issue 3: S3 Rate Limiting

**Symptom:**
```
503 SlowDown: Please reduce your request rate
```

**Cause:** Too many requests to same S3 prefix

**Solution:**
```powershell
# Use different prefixes for different batches
aws s3 cp file1.nc s3://bucket/ingestion/batch1/file1.nc
aws s3 cp file2.nc s3://bucket/ingestion/batch2/file2.nc

# S3 automatically scales to 3,500 PUT/s per prefix
# Multiple prefixes = higher total throughput
```

### Issue 4: Step Functions Execution Limit

**Symptom:** New executions not starting

**Cause:** Hit account-level Step Functions quota (1,000 concurrent)

**Solution:**
```powershell
# Check current quota
aws service-quotas get-service-quota `
    --service-code states `
    --quota-code L-11F7E6B1 `
    --profile DEVcloud

# Request increase
aws service-quotas request-service-quota-increase `
    --service-code states `
    --quota-code L-11F7E6B1 `
    --desired-value 2000 `
    --profile DEVcloud
```

### Issue 5: Lambda Concurrent Execution Limit

**Symptom:** Lambda functions throttled

**Cause:** Hit account-level Lambda concurrency limit (1,000)

**Solution:**
```powershell
# Check current limit
aws lambda get-account-settings `
    --profile DEVcloud `
    --query 'AccountLimit.ConcurrentExecutions'

# Request increase through AWS Support Console
# Or use reserved concurrency for specific functions
aws lambda put-function-concurrency `
    --function-name cloud-scientific-raster-sharing-stac-creator `
    --reserved-concurrent-executions 500 `
    --profile DEVcloud
```

## Best Practices

### Before Upload

1. **Validate Files Locally**
   ```powershell
   # Check file count
   (Get-ChildItem ./netcdf-folder/*.nc).Count
   
   # Check total size
   (Get-ChildItem ./netcdf-folder/*.nc | Measure-Object -Property Length -Sum).Sum / 1GB
   ```

2. **Check System Status**
   ```powershell
   # Verify ECS cluster is running
   aws ecs describe-clusters `
       --clusters cloud-scientific-raster-sharing-ecs-cluster `
       --profile DEVcloud
   
   # Check for existing failed executions
   aws stepfunctions list-executions `
       --state-machine-arn YOUR_ARN `
       --status-filter FAILED `
       --max-results 10 `
       --profile DEVcloud
   ```

3. **Estimate Costs**
   - File count × $0.03 = estimated cost
   - 250 files = ~$7.50
   - 1,000 files = ~$30.00

### During Upload

1. **Monitor Progress**
   - Use `./scripts/monitor-ingestion-pipeline.ps1`
   - Check CloudWatch dashboard
   - Watch for error notifications

2. **Check for Failures**
   ```powershell
   # Every 5 minutes, check for failures
   aws stepfunctions list-executions `
       --state-machine-arn YOUR_ARN `
       --status-filter FAILED `
       --profile DEVcloud
   ```

3. **Monitor Costs**
   ```powershell
   # Check current month costs
   aws ce get-cost-and-usage `
       --time-period Start=2024-11-01,End=2024-11-30 `
       --granularity DAILY `
       --metrics BlendedCost `
       --profile DEVcloud
   ```

### After Upload

1. **Verify Completion**
   ```powershell
   # Count successful executions
   aws stepfunctions list-executions `
       --state-machine-arn YOUR_ARN `
       --status-filter SUCCEEDED `
       --max-results 1000 `
       --profile DEVcloud `
       --query 'executions | length(@)'
   ```

2. **Check Output Buckets**
   ```powershell
   # Verify Zarr files created
   aws s3 ls s3://your-zarr-bucket/zarr/ --profile DEVcloud | wc -l
   
   # Verify COG files created
   aws s3 ls s3://your-cog-bucket/cog/ --profile DEVcloud | wc -l
   ```

3. **Verify STAC Indexing**
   ```powershell
   # Check DynamoDB item count
   aws dynamodb describe-table `
       --table-name cloud-scientific-raster-sharing-stac-items `
       --profile DEVcloud `
       --query 'Table.ItemCount'
   ```

4. **Test API Access**
   ```bash
   # Query collections
   curl "http://your-alb-dns/api/collections"
   
   # Search for specific variable
   curl "http://your-alb-dns/api/search?variable=SST"
   ```

## Performance Optimization

### For Small Files (<10MB)

- Upload all at once
- No batching needed
- Processing time: ~5-10 minutes per 100 files

### For Medium Files (10-100MB)

- Upload all at once (up to 500 files)
- Consider batching for >500 files
- Processing time: ~10-20 minutes per 100 files

### For Large Files (>100MB)

- Use batches of 50-100 files
- Monitor ECS task memory usage
- May need to increase task memory
- Processing time: ~30-60 minutes per 100 files

### Parallel Upload Optimization

```powershell
# Optimize based on your bandwidth
# For fast connections (>100 Mbps): ThrottleLimit 20
# For medium connections (10-100 Mbps): ThrottleLimit 10
# For slow connections (<10 Mbps): ThrottleLimit 5

$files | ForEach-Object -Parallel {
    aws s3 cp $_.FullName s3://bucket/ingestion/$($_.Name)
} -ThrottleLimit 10
```

## Troubleshooting Commands

### Get Execution Details
```powershell
# Get specific execution
aws stepfunctions describe-execution `
    --execution-arn YOUR_EXECUTION_ARN `
    --profile DEVcloud

# Get execution history
aws stepfunctions get-execution-history `
    --execution-arn YOUR_EXECUTION_ARN `
    --profile DEVcloud
```

### Check CloudWatch Logs
```powershell
# Zarr conversion logs
aws logs tail /ecs/zarr-conversion --since 1h --follow --profile DEVcloud

# STAC creator logs
aws logs tail /aws/lambda/cloud-scientific-raster-sharing-stac-creator --since 1h --profile DEVcloud
```

### Retry Failed Executions
```powershell
# Get failed execution input
$failedInput = aws stepfunctions describe-execution `
    --execution-arn FAILED_EXECUTION_ARN `
    --profile DEVcloud `
    --query 'input' `
    --output text

# Retry with same input
aws stepfunctions start-execution `
    --state-machine-arn YOUR_STATE_MACHINE_ARN `
    --input $failedInput `
    --profile DEVcloud
```

## Recommendations by Batch Size

| Batch Size | Strategy | Expected Time | Estimated Cost |
|------------|----------|---------------|----------------|
| 1-100 files | Upload all at once | 5-10 minutes | $3-5 |
| 100-500 files | Upload all at once | 10-20 minutes | $5-15 |
| 500-1000 files | Upload all at once or batch by 100 | 20-40 minutes | $15-30 |
| 1000+ files | Batch by 100-200 | 1-2 hours | $30+ |

## Quick Reference

### Upload Commands
```powershell
# Simple upload (all at once)
./scripts/batch-upload-netcdf.ps1 -LocalFolder "C:\data\netcdf"

# Batched upload
./scripts/batch-upload-netcdf.ps1 -LocalFolder "C:\data\netcdf" -BatchSize 50

# AWS CLI sync
aws s3 sync ./local-folder/ s3://bucket/ingestion/ --profile DEVcloud
```

### Monitoring Commands
```powershell
# Monitor pipeline
./scripts/monitor-ingestion-pipeline.ps1

# Check running tasks
aws ecs list-tasks --cluster CLUSTER_NAME --profile DEVcloud

# Check executions
aws stepfunctions list-executions --state-machine-arn ARN --profile DEVcloud
```

### Verification Commands
```powershell
# Count output files
aws s3 ls s3://zarr-bucket/zarr/ --profile DEVcloud | wc -l

# Check STAC items
aws dynamodb scan --table-name stac-table --select COUNT --profile DEVcloud

# Test API
curl "http://alb-dns/api/collections"
```

## Summary

**For 250 files, we recommend:**
- ✅ Upload all at once using the batch upload script
- ✅ Monitor with the monitoring script
- ✅ Expected completion: 10-20 minutes
- ✅ Expected cost: ~$7.50
- ✅ System can handle this load easily

The ingestion pipeline is designed for concurrent processing and will handle batch uploads efficiently!

---

**Related Documentation:**
- [Ingestion Pipeline](INGESTION_PIPELINE.md)
- [Ingestion Pipeline Monitoring](INGESTION_PIPELINE_MONITORING.md)
- [ECS Zarr Migration Runbook](ECS_ZARR_MIGRATION_RUNBOOK.md)
- [Monitoring Quick Reference](MONITORING_QUICK_REFERENCE.md)
