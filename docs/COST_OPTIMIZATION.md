# Cost Optimization Guide

## Quick Cost Savings

### Immediate Actions (No Downtime)

#### 1. Stop Services When Not Needed (~$120/month savings)

```bash
# Stop all ECS services
./scripts/stop-services.sh

# Start them again when needed
./scripts/start-services.sh

# Check current cost status
./scripts/cost-status.sh
```

**Savings:** ~$120/month when stopped  
**What stays running:** S3, OpenSearch, Redis (data preserved)  
**Downtime:** API unavailable while stopped

#### 2. Set Up Automatic Scheduling (~$80/month savings)

```bash
# Auto-stop at 6 PM, auto-start at 8 AM on weekdays
./scripts/schedule-services.sh
```

**Savings:** ~$80/month (running 10 hours/day vs 24/7)  
**Best for:** Development/testing environments

### Terraform Configuration Changes

#### 3. Use Cost-Optimized Configuration (~$95/month savings)

```bash
cd terraform

# Apply cost-optimized settings
terraform apply -var-file=terraform.tfvars.cost-optimized

# Or make it permanent
cp terraform.tfvars.cost-optimized terraform.tfvars
terraform apply
```

**Changes:**
- ECS tasks: 2 → 1 per service (saves ~$60/mo)
- OpenSearch: 2 nodes → 1 node (saves ~$25/mo)
- Redis: t3.small → t3.micro (saves ~$10/mo)

**Trade-offs:**
- No high availability (single point of failure)
- Lower capacity (may need manual scaling for high load)

## Cost Breakdown

### Current Default Configuration: ~$175/month

| Component | Cost/Month | Can Stop? | Notes |
|-----------|------------|-----------|-------|
| **ECS Fargate** | **$120** | ✅ Yes | API services |
| - Tiles (2 tasks) | $70 | ✅ | |
| - Timeseries (2 tasks) | $100 | ✅ | |
| - Dask (3 tasks) | $40 | ✅ | |
| **DynamoDB (STAC)** | **$5-10** | ❌ No | Serverless, pay-per-use |
| **Redis** | **$25** | ❌ No* | Cache |
| **ALB** | **$20** | ❌ No | Load balancer |
| **S3** | **$30** | ❌ No | Storage |
| **Lambda + CloudWatch** | **$15** | ❌ No | Ingestion pipeline |
| **Data Transfer** | **$5** | ❌ No | Network |

*Can be stopped but requires Terraform changes

**Recent Optimization**: Migrated from OpenSearch ($100/month) to DynamoDB ($5-10/month) - **saves $90-95/month!**

### Cost-Optimized Configuration: ~$50/month

| Component | Cost/Month | Savings |
|-----------|------------|---------|
| ECS Fargate (1 task each) | $60 | -$60 |
| DynamoDB (STAC) | $5-10 | $0 (already optimized) |
| Redis (t3.micro) | $15 | -$10 |
| Other (unchanged) | $45 | $0 |
| **Total** | **$50** | **-$125** |

**Key Optimizations**: 
- ✅ Migrated from OpenSearch to DynamoDB - saves $90-95/month (90% reduction)
- ✅ Reduced ECS task count for non-production environments

### With Auto-Scheduling: ~$30/month

Running 10 hours/day, 5 days/week (weekdays 8 AM - 6 PM):

| Component | Cost/Month | Savings |
|-----------|------------|---------|
| ECS Fargate (42% uptime) | $25 | -$95 |
| DynamoDB (usage-based) | $3-5 | $0 |
| Fixed costs | $40 | $0 |
| **Total** | **$30** | **-$145** |

## Cost Optimization Strategies

### Strategy 1: Development/Testing (Lowest Cost)

**Target:** ~$30/month

```bash
# 1. Use cost-optimized config
cd terraform
terraform apply -var-file=terraform.tfvars.cost-optimized

# 2. Set up auto-scheduling
./scripts/schedule-services.sh

# 3. Stop services on weekends
# (handled automatically by scheduler)
```

**Best for:** Non-production environments, personal projects

**Includes**: DynamoDB migration savings ($90-95/month)

### Strategy 2: Production with Downtime Windows

**Target:** ~$50/month

```bash
# 1. Use cost-optimized config
cd terraform
terraform apply -var-file=terraform.tfvars.cost-optimized

# 2. Manually stop during known downtime
./scripts/stop-services.sh  # Before maintenance window
./scripts/start-services.sh # After maintenance window
```

**Best for:** Production with predictable low-traffic periods

**Includes**: DynamoDB migration savings ($90-95/month)

### Strategy 3: Full Production (High Availability)

**Target:** ~$175/month

```bash
# Use default configuration
cd terraform
terraform apply
```

**Best for:** Production with 24/7 availability requirements

**Includes**: DynamoDB migration savings ($90-95/month)

## DynamoDB Migration (COMPLETED - SAVES $90-95/MONTH!)

### ✅ Migrated from OpenSearch to DynamoDB

**Before**: OpenSearch (2x t3.small.search) = $100/month  
**After**: DynamoDB (on-demand) = $5-10/month  
**Savings**: $90-95/month (90-95% reduction!)

**Benefits:**
- ✅ 90-95% cost reduction
- ✅ Serverless (no cluster management)
- ✅ Automatic scaling
- ✅ Better reliability (99.99% SLA)
- ✅ Simplified operations

**Status**: Migration completed November 28, 2024

**See**: `docs/DYNAMODB_MIGRATION_COST_REPORT.md` for detailed cost analysis

---

## Advanced Cost Optimizations

### 1. S3 Lifecycle Policies (Save ~50% on old data)

Add to `terraform/modules/data/main.tf`:

```hcl
resource "aws_s3_bucket_lifecycle_configuration" "zarr" {
  bucket = aws_s3_bucket.zarr.id

  rule {
    id     = "archive-old-data"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "STANDARD_IA"  # Infrequent Access
    }

    transition {
      days          = 180
      storage_class = "GLACIER"  # Long-term archive
    }
  }
}
```

### 2. Reserved Instances (Save ~30%)

For long-term deployments (1-3 years):

```bash
# OpenSearch Reserved Instances
aws opensearch purchase-reserved-instance-offering \
  --reserved-instance-offering-id <offering-id> \
  --instance-count 1

# ElastiCache Reserved Instances
aws elasticache purchase-reserved-cache-nodes-offering \
  --reserved-cache-nodes-offering-id <offering-id> \
  --cache-node-count 1
```

### 3. Fargate Spot (Save ~70% on Dask workers)

Modify `terraform/modules/ecs/main.tf`:

```hcl
resource "aws_ecs_service" "dask_workers" {
  # ... existing config ...
  
  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 100
    base              = 0
  }
}
```

**Note:** Spot instances can be interrupted, but acceptable for batch processing

### 4. CloudFront Caching (Reduce origin costs by 80%)

Once you have an SSL certificate:

```bash
# Update terraform.tfvars with real certificate ARN
# CloudFront will cache tiles at edge locations
# Reduces ALB and ECS costs significantly
```

## Monitoring Costs

### AWS Cost Explorer

```bash
# View costs by service
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=SERVICE
```

### Set Up Budget Alerts

```bash
# Create a $200/month budget with alerts
aws budgets create-budget \
  --account-id $(aws sts get-caller-identity --query Account --output text) \
  --budget file://budget.json \
  --notifications-with-subscribers file://notifications.json
```

**budget.json:**
```json
{
  "BudgetName": "raster-platform-monthly",
  "BudgetLimit": {
    "Amount": "200",
    "Unit": "USD"
  },
  "TimeUnit": "MONTHLY",
  "BudgetType": "COST",
  "CostFilters": {
    "TagKeyValue": ["user:project_title$raster-timeseries-platform"]
  }
}
```

### Daily Cost Check

```bash
# Add to your daily routine
./scripts/cost-status.sh
```

## Cost Optimization Checklist

- [ ] Applied cost-optimized Terraform configuration
- [ ] Set up automatic service scheduling
- [ ] Configured S3 lifecycle policies
- [ ] Set up AWS budget alerts
- [ ] Reviewed and tagged all resources
- [ ] Considered reserved instances for long-term
- [ ] Enabled CloudFront caching (if using HTTPS)
- [ ] Configured Fargate Spot for Dask workers
- [ ] Regularly review AWS Cost Explorer
- [ ] Stop services when not actively developing

## Scripts Reference

| Script | Purpose | Savings |
|--------|---------|---------|
| `./scripts/stop-services.sh` | Stop all ECS services | ~$120/mo |
| `./scripts/start-services.sh` | Start all ECS services | - |
| `./scripts/schedule-services.sh` | Auto stop/start schedule | ~$80/mo |
| `./scripts/cost-status.sh` | Show current costs | - |

## FAQ

**Q: Will I lose data if I stop services?**  
A: No. S3, OpenSearch, and Redis keep all data. Only compute stops.

**Q: How long does it take to start services?**  
A: 2-3 minutes for ECS tasks to start and become healthy.

**Q: Can I stop OpenSearch and Redis?**  
A: Not easily. They require Terraform changes and data migration. Better to use smaller instances.

**Q: What if I forget to start services?**  
A: Use the auto-scheduler or set calendar reminders.

**Q: How accurate are these cost estimates?**  
A: Within 10-20%. Actual costs vary with traffic and data transfer.

## Resources

- **Cost Status**: `./scripts/cost-status.sh`
- **Infracost**: `cd terraform && infracost breakdown --path .`
- **AWS Cost Explorer**: https://console.aws.amazon.com/cost-management/
- **AWS Pricing Calculator**: https://calculator.aws/
