# OpenSearch Cost Optimization Guide

## Current Configuration Analysis

Your OpenSearch setup is **oversized for testing** and **not using Graviton** (cheaper ARM instances).

### Current Setup
- **Instance Type**: `t3.small.search` (x86, 2 vCPUs, 2GB RAM)
- **Instance Count**: 2 nodes (multi-AZ for high availability)
- **Storage**: 20GB EBS per node (40GB total)
- **Monthly Cost**: ~$50

### Why It's Oversized for Testing
- **2 nodes**: High availability not needed for dev/test
- **x86 instances**: 30-40% more expensive than Graviton
- **20GB per node**: Likely more than needed for initial testing

---

## Recommended Configurations

### 🏆 Option 1: Graviton Single Node (BEST for Testing)
**Monthly Cost**: ~$20 (60% savings)

```terraform
# In terraform.tfvars
opensearch_instance_type   = "or1.small.search"  # Graviton2 ARM
opensearch_instance_count  = 1
opensearch_ebs_volume_size = 10
```

**Pros**:
- ✅ Cheapest option (~$20/month)
- ✅ AWS Graviton2 (ARM) - 30-40% cheaper
- ✅ 1 vCPU, 8GB RAM (sufficient for testing)
- ✅ 10GB storage (expandable later)

**Cons**:
- ⚠️ Single point of failure (acceptable for dev)
- ⚠️ No multi-AZ (acceptable for dev)

**When to Use**: Development, testing, proof-of-concept

---

### Option 2: Graviton Multi-AZ (Production-Ready)
**Monthly Cost**: ~$40 (20% savings vs current)

```terraform
# In terraform.tfvars
opensearch_instance_type   = "or1.small.search"
opensearch_instance_count  = 2
opensearch_ebs_volume_size = 20
```

**Pros**:
- ✅ High availability (multi-AZ)
- ✅ Graviton2 cost savings
- ✅ Production-ready

**Cons**:
- ⚠️ Still ~$40/month

**When to Use**: Production with cost optimization

---

### Option 3: Ultra-Cheap Dev (Minimal)
**Monthly Cost**: ~$15 (70% savings)

```terraform
# In terraform.tfvars
opensearch_instance_type   = "t3.micro.search"  # 1 vCPU, 1GB RAM
opensearch_instance_count  = 1
opensearch_ebs_volume_size = 10
```

**Pros**:
- ✅ Cheapest possible (~$15/month)
- ✅ Good for small datasets

**Cons**:
- ⚠️ Limited RAM (1GB)
- ⚠️ May be slow with large queries
- ⚠️ x86 (not Graviton)

**When to Use**: Minimal testing, very small datasets

---

### Option 4: Current Setup (Production)
**Monthly Cost**: ~$50 (baseline)

```terraform
# In terraform.tfvars
opensearch_instance_type   = "t3.small.search"
opensearch_instance_count  = 2
opensearch_ebs_volume_size = 20
```

**When to Use**: Production with high availability requirements

---

## Graviton vs x86 Comparison

| Instance Type | Architecture | vCPUs | RAM | Cost/Month (single) | Cost/Month (2 nodes) |
|---------------|--------------|-------|-----|---------------------|----------------------|
| `t3.micro.search` | x86 | 1 | 1GB | ~$15 | ~$30 |
| `t3.small.search` | x86 | 2 | 2GB | ~$25 | ~$50 |
| `or1.small.search` | Graviton2 | 1 | 8GB | ~$20 | ~$40 |
| `or1.medium.search` | Graviton2 | 2 | 16GB | ~$40 | ~$80 |

**Key Insight**: `or1.small.search` (Graviton) has **4x more RAM** than `t3.small.search` at **20% lower cost**!

---

## How to Apply Changes

### Step 1: Update terraform.tfvars

Edit `terraform/terraform.tfvars`:

```terraform
# For testing (recommended)
opensearch_instance_type   = "or1.small.search"
opensearch_instance_count  = 1
opensearch_ebs_volume_size = 10

# For production
# opensearch_instance_type   = "or1.small.search"
# opensearch_instance_count  = 2
# opensearch_ebs_volume_size = 20
```

### Step 2: Apply Changes

```bash
cd terraform
terraform plan  # Review changes
terraform apply
```

**Note**: Changing instance type or count will **recreate the OpenSearch domain** (10-20 minutes downtime). Plan accordingly.

### Step 3: Verify

```bash
# Check domain status
aws opensearch describe-domain \
  --domain-name cloud-sciraster-stac \
  --query 'DomainStatus.[DomainName,Processing,ClusterConfig.InstanceType,ClusterConfig.InstanceCount]'

# Expected output:
# ["cloud-sciraster-stac", false, "or1.small.search", 1]
```

---

## Cost Breakdown by Configuration

### Current Setup (2x t3.small.search)
- **Compute**: 2 × $25 = $50/month
- **Storage**: 40GB × $0.10 = $4/month
- **Data Transfer**: ~$2/month
- **Total**: ~$56/month

### Recommended Dev (1x or1.small.search)
- **Compute**: 1 × $20 = $20/month
- **Storage**: 10GB × $0.10 = $1/month
- **Data Transfer**: ~$1/month
- **Total**: ~$22/month
- **Savings**: $34/month (61%)

### Recommended Prod (2x or1.small.search)
- **Compute**: 2 × $20 = $40/month
- **Storage**: 20GB × $0.10 = $2/month
- **Data Transfer**: ~$2/month
- **Total**: ~$44/month
- **Savings**: $12/month (21%)

---

## Additional Cost Optimization Tips

### 1. Stop OpenSearch When Not in Use
OpenSearch charges by the hour. For dev/test:

```bash
# Stop domain (not supported via console, but can reduce to 0 nodes)
# Better: Use CloudFormation/Terraform to destroy and recreate
terraform destroy -target=module.data.aws_opensearch_domain.stac
```

**Savings**: 100% when stopped (but requires data re-indexing)

### 2. Use Reserved Instances (Production)
For production workloads running 24/7:
- 1-year commitment: 30% discount
- 3-year commitment: 50% discount

### 3. Optimize Storage
- Start with 10GB, expand as needed
- Use lifecycle policies to delete old data
- Monitor storage usage: CloudWatch metric `FreeStorageSpace`

### 4. Right-Size Based on Usage
Monitor these CloudWatch metrics:
- `CPUUtilization`: Should be < 70% average
- `JVMMemoryPressure`: Should be < 80%
- `SearchRate`: Queries per second
- `IndexingRate`: Documents indexed per second

If consistently low, downsize to `t3.micro.search` or `or1.micro.search`.

---

## Migration Path

### Phase 1: Current State (Testing)
```terraform
opensearch_instance_type   = "t3.small.search"
opensearch_instance_count  = 2
```
**Cost**: $50/month

### Phase 2: Optimize for Testing (Immediate)
```terraform
opensearch_instance_type   = "or1.small.search"
opensearch_instance_count  = 1
opensearch_ebs_volume_size = 10
```
**Cost**: $20/month | **Savings**: $30/month

### Phase 3: Scale for Production (When Ready)
```terraform
opensearch_instance_type   = "or1.medium.search"
opensearch_instance_count  = 3  # Multi-AZ with dedicated master
opensearch_ebs_volume_size = 50
```
**Cost**: $120/month | **Performance**: High availability, fast queries

---

## Graviton Compatibility

### ✅ Fully Compatible
- OpenSearch 1.0+
- All OpenSearch plugins
- Your application (ECS tasks are architecture-agnostic)
- AWS SDK calls

### ⚠️ Considerations
- First-time setup may take slightly longer (ARM image pull)
- Performance is equivalent or better than x86 for most workloads

### 🚀 Performance Benefits
- Better price/performance ratio
- Lower power consumption
- Same or better query performance

---

## Monitoring Costs

### CloudWatch Metrics
```bash
# Get OpenSearch costs
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --filter file://filter.json

# filter.json:
{
  "Dimensions": {
    "Key": "SERVICE",
    "Values": ["Amazon OpenSearch Service"]
  }
}
```

### Cost Allocation Tags
Already configured in Terraform:
- `service_owner`: Track by team
- `environment`: Separate dev/prod costs
- `project_title`: Track by project

---

## Recommendations Summary

| Environment | Instance Type | Count | Storage | Monthly Cost | Use Case |
|-------------|---------------|-------|---------|--------------|----------|
| **Dev/Test** | `or1.small.search` | 1 | 10GB | ~$20 | Testing, POC |
| **Staging** | `or1.small.search` | 2 | 20GB | ~$40 | Pre-production |
| **Production** | `or1.medium.search` | 3 | 50GB | ~$120 | High availability |

**Immediate Action**: Switch to `or1.small.search` with 1 node for testing → Save $30/month (60%)

---

## FAQ

**Q: Will switching to Graviton affect my application?**
A: No. Your ECS tasks connect to OpenSearch via HTTPS API, which is architecture-agnostic.

**Q: Can I switch back to x86 later?**
A: Yes. Change `instance_type` in terraform.tfvars and run `terraform apply`.

**Q: Will I lose data when changing instance type?**
A: Yes, the domain is recreated. Export data first or accept data loss for dev/test.

**Q: How long does the change take?**
A: 10-20 minutes for domain recreation.

**Q: Can I test Graviton without committing?**
A: Yes. Create a separate test domain with Graviton, compare performance, then migrate.

---

## Next Steps

1. **Immediate**: Update `terraform.tfvars` with `or1.small.search` and `instance_count = 1`
2. **Run**: `terraform apply` to recreate OpenSearch domain
3. **Monitor**: Check CloudWatch metrics for 1 week
4. **Adjust**: Scale up if needed, or stay at optimized config

**Expected Savings**: $30/month (60% reduction) for dev/test environment
