# Cost Estimation with Infracost

## Overview

Infracost shows cloud cost estimates for Terraform projects. It helps you understand the cost impact of infrastructure changes before deployment.

## Quick Start

### 1. Install Infracost (Local)

**macOS:**
```bash
brew install infracost
```

**Linux:**
```bash
curl -fsSL https://raw.githubusercontent.com/infracost/infracost/master/scripts/install.sh | sh
```

**Windows:**
```powershell
choco install infracost
```

### 2. Get Free API Key

```bash
infracost auth login
```

This opens a browser to create a free account and get your API key.

### 3. Run Cost Estimate

```bash
cd terraform

# Get current cost estimate
infracost breakdown --path .

# Get detailed breakdown with usage estimates
infracost breakdown --path . --usage-file infracost-usage.yml
```

## Expected Monthly Costs

Based on the current configuration (ap-southeast-2 region):

### Compute Costs (~$150-200/month)

- **ECS Fargate Tasks**: ~$120/month
  - Tiles service: 2 tasks × 1 vCPU × 2GB = ~$35/month
  - Timeseries service: 2 tasks × 2 vCPU × 4GB = ~$50/month
  - Dask scheduler: 1 task × 1 vCPU × 2GB = ~$15/month
  - Dask workers: 2 tasks × 2 vCPU × 4GB = ~$20/month (with autoscaling)

- **Lambda**: ~$5/month
  - 1000 invocations/month with minimal duration

### Data Storage (~$50-100/month)

- **S3 Storage**: ~$25-50/month
  - Raw data: 500 GB × $0.023/GB = ~$12/month
  - Zarr: 1000 GB × $0.023/GB = ~$23/month
  - COG: 500 GB × $0.023/GB = ~$12/month
  - STAC: 10 GB × $0.023/GB = ~$0.25/month

- **OpenSearch**: ~$50/month
  - 2 × t3.small.search instances
  - 40 GB EBS storage

- **ElastiCache Redis**: ~$25/month
  - 1 × cache.t3.small instance

### Networking (~$20-50/month)

- **Application Load Balancer**: ~$20/month
  - Base cost: ~$16/month
  - LCU costs: ~$4/month (low traffic)

- **Data Transfer**: ~$10-30/month
  - Depends on traffic volume
  - First 100 GB/month free

- **VPC Endpoints**: ~$7/month
  - S3 Gateway: Free
  - Interface endpoints: ~$7/month each

### Monitoring (~$10/month)

- **CloudWatch Logs**: ~$5/month
  - Log ingestion and storage

- **CloudWatch Alarms**: ~$1/month
  - $0.10 per alarm

- **Step Functions**: ~$2/month
  - State transitions

### **Total Estimated Cost: $250-400/month**

*Actual costs will vary based on:*
- Traffic volume
- Data storage growth
- Autoscaling behavior
- Data transfer patterns

## GitHub Actions Integration

### Setup

1. **Get Infracost API Key**
   - Sign up at https://www.infracost.io/
   - Get your API key from dashboard

2. **Add GitHub Secret**
   - Go to: **Settings** → **Secrets** → **Actions**
   - Add: `INFRACOST_API_KEY` = `<your-key>`

3. **Automatic Cost Comments**
   - Every PR with Terraform changes gets a cost comment
   - Shows cost diff between base and PR branch
   - Updates automatically on new commits

### Example PR Comment

```
💰 Infracost estimate: monthly cost will increase by $45 📈

  Name                                    Monthly Qty  Unit   Monthly Cost
  
  module.ecs.aws_ecs_service.new_service
  ├─ CPU                                        1,460  hours        $35.04
  └─ Memory                                     2,920  GB-hours     $31.97
  
  OVERALL TOTAL                                                    $245.00 → $290.00
  ──────────────────────────────────
  Monthly cost change for main                                      +$45.00 (+18%)
```

## Cost Optimization Tips

### Immediate Savings

1. **Reduce ECS Task Count** (Save ~$60/month)
   ```hcl
   # In terraform.tfvars or module variables
   tiles_desired_count = 1      # Instead of 2
   timeseries_desired_count = 1 # Instead of 2
   ```

2. **Use Smaller OpenSearch** (Save ~$25/month)
   ```hcl
   instance_count = 1  # Instead of 2 (no HA)
   ```

3. **Stop Services When Not Needed**
   ```bash
   # Scale to zero
   aws ecs update-service --cluster <cluster> --service tiles-service --desired-count 0
   
   # Scale back up
   aws ecs update-service --cluster <cluster> --service tiles-service --desired-count 2
   ```

### Long-term Savings

1. **Reserved Instances** (Save ~30%)
   - Commit to 1-year OpenSearch reserved instances
   - Commit to 1-year ElastiCache reserved instances

2. **S3 Lifecycle Policies** (Save ~50% on old data)
   ```hcl
   lifecycle_rule {
     enabled = true
     transition {
       days          = 90
       storage_class = "STANDARD_IA"  # Cheaper for infrequent access
     }
   }
   ```

3. **CloudFront Caching** (Reduce ALB/ECS costs)
   - Cache tiles at edge locations
   - Reduce origin requests by 80-90%

4. **Spot Instances for Dask Workers**
   - Use Fargate Spot for Dask workers
   - Save ~70% on compute costs
   - Acceptable for batch processing

## Advanced Usage

### Compare Environments

```bash
# Compare dev vs prod costs
infracost breakdown --path terraform --terraform-var-file dev.tfvars > dev-cost.txt
infracost breakdown --path terraform --terraform-var-file prod.tfvars > prod-cost.txt
```

### Generate Reports

```bash
# HTML report
infracost breakdown --path terraform --format html > cost-report.html

# JSON for automation
infracost breakdown --path terraform --format json > cost-report.json
```

### Cost Policies

Create a policy to fail CI if costs increase too much:

```yaml
# .github/workflows/infracost.yml
- name: Check cost increase
  run: |
    COST_INCREASE=$(infracost diff --path terraform --format json | jq '.diffTotalMonthlyCost')
    if (( $(echo "$COST_INCREASE > 100" | bc -l) )); then
      echo "Cost increase of \$$COST_INCREASE exceeds threshold!"
      exit 1
    fi
```

## Updating Usage Estimates

Edit `terraform/infracost-usage.yml` to reflect your actual usage:

```yaml
resource_usage:
  module.ecs.aws_ecs_service.tiles:
    monthly_cpu_hours: 2920  # Adjust based on actual task count
    monthly_memory_gb_hours: 5840
```

Run Infracost again to see updated estimates:

```bash
infracost breakdown --path terraform --usage-file infracost-usage.yml
```

## Cost Monitoring

### AWS Cost Explorer

1. Go to: **AWS Console** → **Cost Management** → **Cost Explorer**
2. Filter by tags: `project_title = raster-timeseries-platform`
3. Group by: Service
4. View: Monthly costs

### Set Up Budget Alerts

```bash
# Create a budget alert
aws budgets create-budget \
  --account-id $(aws sts get-caller-identity --query Account --output text) \
  --budget file://budget.json
```

**budget.json:**
```json
{
  "BudgetName": "raster-platform-monthly",
  "BudgetLimit": {
    "Amount": "400",
    "Unit": "USD"
  },
  "TimeUnit": "MONTHLY",
  "BudgetType": "COST"
}
```

## Resources

- **Infracost Docs**: https://www.infracost.io/docs/
- **AWS Pricing Calculator**: https://calculator.aws/
- **AWS Cost Explorer**: https://console.aws.amazon.com/cost-management/
- **Usage File Reference**: https://www.infracost.io/docs/features/usage_based_resources/

## FAQ

**Q: Why are estimates different from actual costs?**
A: Estimates are based on usage assumptions. Actual costs depend on real traffic, data transfer, and autoscaling behavior.

**Q: Does Infracost cost money?**
A: Free tier includes unlimited cost estimates. Paid plans add features like SSO and policy enforcement.

**Q: Can I use this without GitHub Actions?**
A: Yes! Run `infracost breakdown` locally anytime.

**Q: How accurate are the estimates?**
A: Typically within 10-20% of actual costs when usage estimates are accurate.
