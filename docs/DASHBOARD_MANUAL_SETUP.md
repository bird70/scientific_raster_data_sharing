# CloudWatch Dashboard Manual Setup Guide

## Issue

The Terraform CloudWatch dashboard has metric formatting issues with the AWS API. The 6 CloudWatch alarms deployed successfully, but the dashboard needs to be created manually or through the AWS Console.

## Quick Solution: Use CloudWatch Metrics Explorer

Instead of a custom dashboard, use CloudWatch's built-in features:

### 1. CloudWatch Metrics Explorer

```
AWS Console → CloudWatch → Metrics → Explorer
```

Add these metrics:
- **Namespace**: `AWS/States`
  - Metric: `ExecutionsSucceeded`, `ExecutionsFailed`, `ExecutionTime`
  - Dimension: `StateMachineArn` = your state machine ARN

- **Namespace**: `ECS/ContainerInsights`
  - Metrics: `CpuUtilization`, `MemoryUtilization`, `TasksFailed`
  - Dimensions: `ClusterName` + `TaskDefinitionFamily` (zarr-conversion, cog-generation)

### 2. CloudWatch Automatic Dashboards

```
AWS Console → CloudWatch → Automatic dashboards → ECS
```

Select your cluster to see automatic ECS metrics.

### 3. Use the Monitoring Script

The interactive monitoring script provides all key metrics:

```bash
./scripts/monitor-ingestion-pipeline.sh
```

Options:
- 1: Recent executions
- 2: Success rate (24h)
- 3: Execution time (24h)
- 4: Zarr task metrics
- 5: COG task metrics
- 7: Cost estimation

## Manual Dashboard Creation (Optional)

If you want a custom dashboard, create it manually in the AWS Console:

### Step 1: Create Dashboard

```
AWS Console → CloudWatch → Dashboards → Create dashboard
Name: cloud-scientific-raster-sharing-ingestion-pipeline
```

### Step 2: Add Widgets

#### Widget 1: Step Functions Execution Status

- Type: Line graph
- Metrics:
  - `AWS/States` → `ExecutionsSucceeded` → Select your state machine
  - `AWS/States` → `ExecutionsFailed` → Select your state machine
- Statistic: Sum
- Period: 5 minutes

#### Widget 2: Step Functions Execution Time

- Type: Line graph
- Metrics:
  - `AWS/States` → `ExecutionTime` → Select your state machine
- Statistics: Average, Maximum
- Period: 5 minutes

#### Widget 3: Zarr Conversion Task Status

- Type: Line graph
- Metrics:
  - `ECS/ContainerInsights` → `TasksStarted` → Cluster + TaskDefinitionFamily=zarr-conversion
  - `ECS/ContainerInsights` → `TasksFailed` → Cluster + TaskDefinitionFamily=zarr-conversion
- Statistic: Sum
- Period: 5 minutes

#### Widget 4: Zarr Conversion Resource Utilization

- Type: Line graph
- Metrics:
  - `ECS/ContainerInsights` → `CpuUtilization` → Cluster + TaskDefinitionFamily=zarr-conversion
  - `ECS/ContainerInsights` → `MemoryUtilization` → Cluster + TaskDefinitionFamily=zarr-conversion
- Statistic: Average
- Period: 5 minutes

#### Widget 5: COG Generation Task Status

- Type: Line graph
- Metrics:
  - `ECS/ContainerInsights` → `TasksStarted` → Cluster + TaskDefinitionFamily=cog-generation
  - `ECS/ContainerInsights` → `TasksFailed` → Cluster + TaskDefinitionFamily=cog-generation
- Statistic: Sum
- Period: 5 minutes

#### Widget 6: COG Generation Resource Utilization

- Type: Line graph
- Metrics:
  - `ECS/ContainerInsights` → `CpuUtilization` → Cluster + TaskDefinitionFamily=cog-generation
  - `ECS/ContainerInsights` → `MemoryUtilization` → Cluster + TaskDefinitionFamily=cog-generation
- Statistic: Average
- Period: 5 minutes

### Step 3: Save Dashboard

Click "Save dashboard" in the top right.

## What's Working

Even without the dashboard, you have complete monitoring:

✅ **6 CloudWatch Alarms** (deployed and active):
- High failure rate detection
- Long execution time alerts
- ECS task failure notifications
- High memory usage warnings

✅ **Interactive Monitoring Script**:
- Real-time metrics
- Success rate calculation
- Cost estimation
- Log viewing

✅ **AWS Console Access**:
- CloudWatch Metrics Explorer
- Automatic ECS dashboards
- Step Functions execution history
- CloudWatch Logs

## Recommended Monitoring Workflow

1. **Daily**: Run `./scripts/monitor-ingestion-pipeline.sh` → Check options 2, 3, 4, 5
2. **Weekly**: Check AWS Console → CloudWatch → Alarms for any triggered alarms
3. **Monthly**: Run monitoring script → Option 7 for cost estimation
4. **As needed**: Use CloudWatch Metrics Explorer for deep dives

## Future Fix

The dashboard Terraform code will be fixed in a future update to use the correct metric format. For now, the alarms provide proactive monitoring, and the script provides on-demand metrics.

## Summary

**Status**: ✅ Monitoring is fully functional

- 6 alarms deployed and active
- Monitoring script provides all key metrics
- AWS Console provides detailed views
- Dashboard can be created manually if desired

The lack of an automated dashboard doesn't impact monitoring capabilities - you have everything you need to track the pipeline's performance and cost savings!
