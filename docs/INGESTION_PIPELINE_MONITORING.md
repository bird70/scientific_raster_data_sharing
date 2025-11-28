# Ingestion Pipeline Monitoring and Cost Verification Guide

## Overview

This guide provides instructions for monitoring the ECS-based ingestion pipeline and verifying cost savings compared to the Lambda-based implementation.

## CloudWatch Alarms

The following CloudWatch alarms have been configured to monitor the ingestion pipeline:

### Step Functions Alarms

1. **High Failure Rate** (`{project_name}-ingestion-high-failure-rate`)
   - **Threshold**: More than 2 failures in 5 minutes
   - **Action**: Sends SNS notification
   - **Purpose**: Detect systematic issues causing pipeline failures

2. **Long Execution Time** (`{project_name}-ingestion-long-execution`)
   - **Threshold**: Execution time exceeds 20 minutes
   - **Action**: Sends SNS notification
   - **Purpose**: Detect performance degradation or stuck executions

### ECS Task Alarms

3. **Zarr Task Failure** (`{project_name}-zarr-task-failure`)
   - **Threshold**: Any task failure in 5 minutes
   - **Action**: Sends SNS notification
   - **Purpose**: Immediate notification of Zarr conversion failures

4. **COG Task Failure** (`{project_name}-cog-task-failure`)
   - **Threshold**: Any task failure in 5 minutes
   - **Action**: Sends SNS notification
   - **Purpose**: Immediate notification of COG generation failures

5. **Zarr High Memory** (`{project_name}-zarr-high-memory`)
   - **Threshold**: Memory utilization > 90% for 10 minutes
   - **Action**: Sends SNS notification
   - **Purpose**: Detect memory pressure that could lead to OOM errors

6. **COG High Memory** (`{project_name}-cog-high-memory`)
   - **Threshold**: Memory utilization > 90% for 10 minutes
   - **Action**: Sends SNS notification
   - **Purpose**: Detect memory pressure that could lead to OOM errors

## CloudWatch Dashboard

A comprehensive dashboard has been created: `{project_name}-ingestion-pipeline`

### Dashboard Widgets

1. **Step Functions - Execution Status**
   - Shows succeeded, failed, timed out, and aborted executions
   - 5-minute granularity

2. **Step Functions - Execution Time**
   - Shows average, max, and min execution times
   - Helps identify performance trends

3. **Zarr Conversion - Task Status**
   - Shows running, started, stopped, and failed tasks
   - Monitors task lifecycle

4. **Zarr Conversion - Resource Utilization**
   - Shows CPU (vCPU) and Memory (MB) utilization
   - Helps optimize resource allocation

5. **Zarr Conversion - Utilization Percentage**
   - Shows CPU and Memory as percentage of allocated resources
   - Identifies over/under-provisioning

6. **COG Generation - Task Status**
   - Shows running, started, stopped, and failed tasks
   - Monitors task lifecycle

7. **COG Generation - Resource Utilization**
   - Shows CPU (vCPU) and Memory (MB) utilization
   - Helps optimize resource allocation

8. **COG Generation - Utilization Percentage**
   - Shows CPU and Memory as percentage of allocated resources
   - Identifies over/under-provisioning

9. **Step Functions - Success Rate**
   - Shows percentage of successful executions
   - Key reliability metric

10. **Total Execution Time**
    - Shows cumulative execution time per hour
    - Used for cost estimation

## Accessing Monitoring Resources

### AWS Console

1. **CloudWatch Alarms**:
   ```
   AWS Console → CloudWatch → Alarms → All alarms
   Filter by: {project_name}-ingestion
   ```

2. **CloudWatch Dashboard**:
   ```
   AWS Console → CloudWatch → Dashboards
   Select: {project_name}-ingestion-pipeline
   ```

3. **CloudWatch Logs**:
   ```
   AWS Console → CloudWatch → Log groups
   - /ecs/zarr-conversion
   - /ecs/cog-generation
   - /aws/lambda/{project_name}-stac-creator
   - /aws/lambda/{project_name}-stac-indexer
   ```

4. **Step Functions Executions**:
   ```
   AWS Console → Step Functions → State machines
   Select: {project_name}-ingestion-pipeline
   Click: Executions tab
   ```

### AWS CLI

1. **List Recent Executions**:
   ```bash
   aws stepfunctions list-executions \
     --state-machine-arn $(terraform output -raw ingestion_state_machine_arn) \
     --max-results 10
   ```

2. **Get Execution Details**:
   ```bash
   aws stepfunctions describe-execution \
     --execution-arn <execution-arn>
   ```

3. **Get CloudWatch Metrics**:
   ```bash
   # Step Functions success rate
   aws cloudwatch get-metric-statistics \
     --namespace AWS/States \
     --metric-name ExecutionsSucceeded \
     --dimensions Name=StateMachineArn,Value=$(terraform output -raw ingestion_state_machine_arn) \
     --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
     --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
     --period 300 \
     --statistics Sum
   ```

4. **Get ECS Task Metrics**:
   ```bash
   # Zarr conversion CPU utilization
   aws cloudwatch get-metric-statistics \
     --namespace ECS/ContainerInsights \
     --metric-name CpuUtilization \
     --dimensions Name=ClusterName,Value=$(terraform output -raw ecs_cluster_name) Name=TaskDefinitionFamily,Value=zarr-conversion \
     --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
     --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
     --period 300 \
     --statistics Average,Maximum
   ```

## Cost Verification

### Expected Costs

**Lambda-based implementation** (per file):
- Lambda execution: ~15 minutes × $0.0000166667/GB-second × 10GB = $5.02

**ECS-based implementation** (per file):
- Zarr conversion: ~15 minutes × $0.04048/hour (0.5 vCPU + 2GB) = $0.01012
- COG generation: ~10 minutes × $0.04048/hour (0.5 vCPU + 2GB) = $0.00675
- **Total: ~$0.017 per file**

**Cost savings: 98%** ($5.02 → $0.017)

### Verifying Costs with AWS Cost Explorer

1. **Access Cost Explorer**:
   ```
   AWS Console → Cost Management → Cost Explorer
   ```

2. **Filter by Service**:
   - Select "ECS" service
   - Select "Step Functions" service
   - Date range: Last 30 days

3. **Group by Tag**:
   - Group by: Tag
   - Tag key: `Project` or `Name`
   - Filter to your project name

4. **Compare Time Periods**:
   - Compare costs before and after ECS migration
   - Look for reduction in Lambda costs
   - Verify ECS costs are within expected range

### Cost Calculation Script

Create a script to calculate actual costs from CloudWatch metrics:

```bash
#!/bin/bash
# calculate_ingestion_costs.sh

PROJECT_NAME="your-project-name"
REGION="us-east-1"
START_TIME=$(date -u -d '30 days ago' +%Y-%m-%dT%H:%M:%S)
END_TIME=$(date -u +%Y-%m-%dT%H:%M:%S)

# Get total execution time from Step Functions
TOTAL_EXEC_TIME=$(aws cloudwatch get-metric-statistics \
  --namespace AWS/States \
  --metric-name ExecutionTime \
  --dimensions Name=StateMachineArn,Value=$(terraform output -raw ingestion_state_machine_arn) \
  --start-time "$START_TIME" \
  --end-time "$END_TIME" \
  --period 86400 \
  --statistics Sum \
  --region "$REGION" \
  --query 'Datapoints[*].Sum' \
  --output text | awk '{s+=$1} END {print s}')

# Convert milliseconds to hours
TOTAL_HOURS=$(echo "scale=4; $TOTAL_EXEC_TIME / 3600000" | bc)

# Calculate cost (ECS Fargate pricing: $0.04048/hour for 0.5 vCPU + 2GB)
COST_PER_HOUR=0.04048
TOTAL_COST=$(echo "scale=2; $TOTAL_HOURS * $COST_PER_HOUR" | bc)

echo "Total execution time: $TOTAL_HOURS hours"
echo "Estimated ECS cost: \$$TOTAL_COST"
echo ""
echo "Note: This is an estimate. Check AWS Cost Explorer for actual costs."
```

### Monitoring Cost Trends

1. **Set up Cost Anomaly Detection**:
   ```
   AWS Console → Cost Management → Cost Anomaly Detection
   Create monitor for ECS service
   ```

2. **Create Budget Alert**:
   ```
   AWS Console → Cost Management → Budgets
   Create budget for ingestion pipeline
   Set threshold: $50/month (adjust based on volume)
   ```

3. **Tag Resources for Cost Tracking**:
   - All resources are tagged with `Project` and `Environment`
   - Use these tags in Cost Explorer for detailed breakdowns

## Performance Monitoring

### Key Metrics to Track

1. **Execution Time**:
   - **Target**: 10-20 minutes per file
   - **Metric**: `AWS/States` → `ExecutionTime`
   - **Action if exceeded**: Check ECS task logs for bottlenecks

2. **Success Rate**:
   - **Target**: >95%
   - **Metric**: `ExecutionsSucceeded / (ExecutionsSucceeded + ExecutionsFailed)`
   - **Action if below**: Investigate failure patterns in logs

3. **CPU Utilization**:
   - **Target**: 30-70% average
   - **Metric**: `ECS/ContainerInsights` → `CpuUtilization`
   - **Action if too low**: Consider reducing CPU allocation
   - **Action if too high**: Consider increasing CPU allocation

4. **Memory Utilization**:
   - **Target**: 50-80% average
   - **Metric**: `ECS/ContainerInsights` → `MemoryUtilization`
   - **Action if too low**: Consider reducing memory allocation
   - **Action if >90%**: Increase memory to prevent OOM errors

### Checking Logs for Errors

1. **Zarr Conversion Logs**:
   ```bash
   aws logs tail /ecs/zarr-conversion --follow --format short
   ```

2. **COG Generation Logs**:
   ```bash
   aws logs tail /ecs/cog-generation --follow --format short
   ```

3. **Filter for Errors**:
   ```bash
   aws logs filter-log-events \
     --log-group-name /ecs/zarr-conversion \
     --filter-pattern "ERROR" \
     --start-time $(date -u -d '1 hour ago' +%s)000
   ```

## Gradual Rollout Strategy

### Phase 1: 10% Traffic (Week 1)

1. **Deploy infrastructure**:
   ```bash
   cd terraform
   terraform apply
   ```

2. **Monitor for 1 week**:
   - Check dashboard daily
   - Review all alarm notifications
   - Verify success rate >95%
   - Confirm execution time 10-20 minutes

3. **Validation checklist**:
   - [ ] No critical alarms triggered
   - [ ] Success rate >95%
   - [ ] Average execution time within expected range
   - [ ] No memory/CPU issues
   - [ ] Cost tracking shows expected savings

### Phase 2: 50% Traffic (Week 2)

1. **Increase traffic** (if Phase 1 successful):
   - Process 50% of files through ECS pipeline
   - Keep 50% on Lambda as backup

2. **Monitor for 1 week**:
   - Same monitoring as Phase 1
   - Compare costs between Lambda and ECS

3. **Validation checklist**:
   - [ ] Performance consistent with Phase 1
   - [ ] No increase in failure rate
   - [ ] Cost savings confirmed
   - [ ] No operational issues

### Phase 3: 100% Traffic (Week 3+)

1. **Full migration** (if Phase 2 successful):
   - Route all traffic to ECS pipeline
   - Keep Lambda code as emergency fallback

2. **Ongoing monitoring**:
   - Review dashboard weekly
   - Check Cost Explorer monthly
   - Optimize resource allocation based on metrics

3. **Validation checklist**:
   - [ ] All files processing successfully
   - [ ] Cost savings realized (98% reduction)
   - [ ] No operational issues
   - [ ] Team comfortable with new pipeline

## Troubleshooting

### High Failure Rate

1. **Check Step Functions execution history**:
   - Identify which state is failing
   - Review error messages

2. **Check ECS task logs**:
   - Look for exceptions or errors
   - Verify input parameters are correct

3. **Common issues**:
   - Invalid NetCDF format → Add validation
   - S3 permissions → Check IAM roles
   - Memory exhaustion → Increase task memory
   - Network issues → Check VPC/security groups

### Long Execution Time

1. **Check resource utilization**:
   - If CPU/Memory <50%, increase allocation
   - If CPU/Memory >90%, task is resource-constrained

2. **Check file size**:
   - Larger files take longer
   - Consider separate task definitions for large files

3. **Check network performance**:
   - S3 download/upload speeds
   - VPC endpoint configuration

### High Costs

1. **Check execution frequency**:
   - Are tasks running more often than expected?
   - Are there stuck/long-running tasks?

2. **Optimize resource allocation**:
   - Reduce CPU/memory if utilization is low
   - Use spot instances for non-critical workloads

3. **Review retry logic**:
   - Excessive retries increase costs
   - Adjust retry configuration if needed

## Rollback Procedure

If issues arise during rollout:

1. **Immediate rollback**:
   ```bash
   # Disable S3 event notification to ECS pipeline
   aws s3api put-bucket-notification-configuration \
     --bucket your-raw-bucket \
     --notification-configuration file://lambda-notification.json
   ```

2. **Re-enable Lambda pipeline**:
   - Update Step Functions to use Lambda for Zarr conversion
   - Monitor for stability

3. **Investigate issues**:
   - Review logs and metrics
   - Identify root cause
   - Fix issues before re-attempting migration

## Summary

This monitoring setup provides comprehensive visibility into the ECS-based ingestion pipeline, enabling:

- **Proactive issue detection** through CloudWatch alarms
- **Performance optimization** through detailed metrics
- **Cost verification** through execution time tracking
- **Operational confidence** through gradual rollout

Regular review of these metrics ensures the pipeline operates efficiently and cost-effectively.
