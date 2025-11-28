# Documentation Index

Welcome! This directory contains comprehensive documentation for the Scientific Raster Data Sharing Platform on AWS.

## 🚀 Quick Start (New Users Start Here)

1. **[DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)** - Complete deployment instructions from scratch
   - Prerequisites and setup
   - HTTP-only deployment (fully automated)
   - Adding HTTPS (optional)
   - Testing and verification

2. **[COST_OPTIMIZATION.md](COST_OPTIMIZATION.md)** - Reduce your AWS bill by 50-70%
   - Immediate cost savings
   - Graviton (ARM) instances
   - Auto-scheduling services
   - Cost monitoring

## 🎉 What's New: ECS-Based Ingestion Pipeline

**Major Update**: The ingestion pipeline has been migrated from Lambda to ECS Fargate, delivering:
- ✅ **99% cost reduction** ($5.02 → $0.037 per file)
- ✅ **No timeout limitations** (Lambda 15min → ECS unlimited)
- ✅ **Improved reliability** for large file processing
- ✅ **Annual savings**: ~$5,980 (based on 100 files/month)

**Key Documents**:
- **[ECS_ZARR_MIGRATION_RUNBOOK.md](ECS_ZARR_MIGRATION_RUNBOOK.md)** - Operations guide
- **[ECS_MIGRATION_COST_ANALYSIS.md](ECS_MIGRATION_COST_ANALYSIS.md)** - Cost analysis
- **[RESULTSELECTOR_DATA_FLOW_PATTERN.md](RESULTSELECTOR_DATA_FLOW_PATTERN.md)** - Technical innovation

**Quick Start**:
```bash
# Monitor pipeline
./scripts/monitor-ingestion-pipeline.sh

# Upload test file
aws s3 cp data/test.nc s3://your-bucket/ingestion/
```

## 📚 Core Documentation

### Infrastructure & Deployment

| Document | Purpose | When to Read |
|----------|---------|--------------|
| **[DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)** | Step-by-step deployment | First deployment |
| **[INFRASTRUCTURE_AS_CODE.md](INFRASTRUCTURE_AS_CODE.md)** | IaC verification checklist | Verify 100% IaC compliance |
| **[AUTOMATION_ISSUES_AND_FIXES.md](AUTOMATION_ISSUES_AND_FIXES.md)** | Root cause analysis of automation blockers | Troubleshooting deployment |
| **[TERRAFORM_DESTROY_ISSUES.md](TERRAFORM_DESTROY_ISSUES.md)** | Cleanup troubleshooting | Before running `terraform destroy` |

### Cost Management

| Document | Purpose | When to Read |
|----------|---------|--------------|
| **[COST_OPTIMIZATION.md](COST_OPTIMIZATION.md)** | Overall cost reduction strategies | After first deployment |
| **[ECS_MIGRATION_COST_ANALYSIS.md](ECS_MIGRATION_COST_ANALYSIS.md)** | **ECS migration cost analysis (99% savings)** | **Understanding ingestion cost savings** |
| **[OPENSEARCH_COST_OPTIMIZATION.md](OPENSEARCH_COST_OPTIMIZATION.md)** | OpenSearch-specific savings (60%) | Optimizing OpenSearch costs |

### Features & Operations

| Document | Purpose | When to Read |
|----------|---------|--------------|
| **[INGESTION_PIPELINE.md](INGESTION_PIPELINE.md)** | Data ingestion workflow (ECS-based) | Before uploading data |
| **[ECS_ZARR_MIGRATION_RUNBOOK.md](ECS_ZARR_MIGRATION_RUNBOOK.md)** | **Operations guide for ECS ingestion pipeline** | **Day-to-day pipeline operations** |
| **[INGESTION_PIPELINE_MONITORING.md](INGESTION_PIPELINE_MONITORING.md)** | Monitoring and cost verification | Monitoring pipeline health |
| **[ECS_MIGRATION_DEPLOYMENT.md](ECS_MIGRATION_DEPLOYMENT.md)** | ECS migration deployment guide | Deploying ECS pipeline |
| **[API_ROUTES_CHANGELOG.md](API_ROUTES_CHANGELOG.md)** | API endpoints and changes | Integrating with API |
| **[runbook.md](runbook.md)** | General operational procedures | Day-to-day operations |
| **[deployment_notes.md](deployment_notes.md)** | Historical deployment notes | Reference only |

### CI/CD & Security

| Document | Purpose | When to Read |
|----------|---------|--------------|
| **[GITHUB_ACTIONS_SETUP.md](GITHUB_ACTIONS_SETUP.md)** | CI/CD pipeline configuration | Setting up automation |
| **[GITHUB_SECRETS_SETUP.md](GITHUB_SECRETS_SETUP.md)** | GitHub secrets configuration | Configuring CI/CD |
| **[SECURITY_SCANNING.md](SECURITY_SCANNING.md)** | Checkov security policies | Security compliance |
| **[GIT_WORKFLOW.md](GIT_WORKFLOW.md)** | Git workflow and troubleshooting | Git issues |

### Requirements & Compliance

| Document | Purpose | When to Read |
|----------|---------|--------------|
| **[REQUIREMENTS_EARS.md](REQUIREMENTS_EARS.md)** | EARS-compliant requirements | Understanding requirements |

---

## 🎯 Common Scenarios

### "I want to deploy this for the first time"
1. Read: [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)
2. Follow: HTTP-only deployment section
3. Then: [COST_OPTIMIZATION.md](COST_OPTIMIZATION.md) to reduce costs

### "My deployment is failing"
1. Check: [AUTOMATION_ISSUES_AND_FIXES.md](AUTOMATION_ISSUES_AND_FIXES.md)
2. Review: [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) troubleshooting section
3. Verify: [INFRASTRUCTURE_AS_CODE.md](INFRASTRUCTURE_AS_CODE.md) checklist

### "I want to reduce costs"
1. Start: [COST_OPTIMIZATION.md](COST_OPTIMIZATION.md) - Quick wins
2. Deep dive: [OPENSEARCH_COST_OPTIMIZATION.md](OPENSEARCH_COST_OPTIMIZATION.md) - 60% savings
3. Apply: Cost-optimized terraform.tfvars settings

### "I want to upload data"
1. Read: [INGESTION_PIPELINE.md](INGESTION_PIPELINE.md)
2. Upload: NetCDF file to S3 raw bucket
3. Monitor: Use `./scripts/monitor-ingestion-pipeline.sh` or see [ECS_ZARR_MIGRATION_RUNBOOK.md](ECS_ZARR_MIGRATION_RUNBOOK.md)

### "I want to set up CI/CD"
1. Read: [GITHUB_ACTIONS_SETUP.md](GITHUB_ACTIONS_SETUP.md)
2. Configure: [GITHUB_SECRETS_SETUP.md](GITHUB_SECRETS_SETUP.md)
3. Push: Code to main branch

### "I want to destroy infrastructure"
1. Read: [TERRAFORM_DESTROY_ISSUES.md](TERRAFORM_DESTROY_ISSUES.md) first!
2. Run: Cleanup scripts for S3 buckets
3. Execute: `terraform destroy`

### "I want to add HTTPS"
1. Create: ACM certificate in AWS Console
2. Update: terraform.tfvars with certificate ARN
3. Apply: `terraform apply`

### "I want to manage the ingestion pipeline"
1. Monitor: `./scripts/monitor-ingestion-pipeline.sh`
2. Operations: [ECS_ZARR_MIGRATION_RUNBOOK.md](ECS_ZARR_MIGRATION_RUNBOOK.md)
3. Troubleshoot: See runbook troubleshooting section
4. Costs: [ECS_MIGRATION_COST_ANALYSIS.md](ECS_MIGRATION_COST_ANALYSIS.md)

### "I want to understand the ECS migration"
1. Architecture: [INGESTION_PIPELINE.md](INGESTION_PIPELINE.md)
2. Technical details: [RESULTSELECTOR_DATA_FLOW_PATTERN.md](RESULTSELECTOR_DATA_FLOW_PATTERN.md)
3. Cost savings: [ECS_MIGRATION_COST_ANALYSIS.md](ECS_MIGRATION_COST_ANALYSIS.md) - 99% reduction
4. Deployment: [ECS_MIGRATION_DEPLOYMENT.md](ECS_MIGRATION_DEPLOYMENT.md)

---

## 📊 Documentation by Role

### DevOps Engineer
**Priority Reading:**
1. [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)
2. [ECS_ZARR_MIGRATION_RUNBOOK.md](ECS_ZARR_MIGRATION_RUNBOOK.md) - **Pipeline operations**
3. [INFRASTRUCTURE_AS_CODE.md](INFRASTRUCTURE_AS_CODE.md)
4. [GITHUB_ACTIONS_SETUP.md](GITHUB_ACTIONS_SETUP.md)
5. [COST_OPTIMIZATION.md](COST_OPTIMIZATION.md)

### Developer
**Priority Reading:**
1. [API_ROUTES_CHANGELOG.md](API_ROUTES_CHANGELOG.md)
2. [INGESTION_PIPELINE.md](INGESTION_PIPELINE.md)
3. [RESULTSELECTOR_DATA_FLOW_PATTERN.md](RESULTSELECTOR_DATA_FLOW_PATTERN.md) - Technical deep-dive
4. [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) - Testing section

### Project Manager
**Priority Reading:**
1. [COST_OPTIMIZATION.md](COST_OPTIMIZATION.md)
2. [REQUIREMENTS_EARS.md](REQUIREMENTS_EARS.md)
3. [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) - Overview

### Security Engineer
**Priority Reading:**
1. [SECURITY_SCANNING.md](SECURITY_SCANNING.md)
2. [INFRASTRUCTURE_AS_CODE.md](INFRASTRUCTURE_AS_CODE.md)
3. [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) - Security section

---

## 🔧 Quick Reference

### Cost Optimization Quick Wins
```terraform
# In terraform.tfvars
opensearch_instance_type   = "or1.small.search"  # Graviton, 60% cheaper
opensearch_instance_count  = 1                    # Single node for dev
redis_node_type            = "cache.t4g.micro"   # Graviton, 50% cheaper
tiles_desired_count        = 1                    # Scale down for dev
timeseries_desired_count   = 1                    # Scale down for dev
```
**Savings**: $265/month → $120/month (55% reduction)

### Deployment Commands
```bash
# Initial deployment
cd terraform
terraform init
terraform apply

# Build and push Docker image
cd ../app
docker build -t <ecr-repo>:latest .
docker push <ecr-repo>:latest

# Test deployment
curl http://<alb-dns>/health
```

### Cost Monitoring
```bash
# Check current costs
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2026-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost
```

### Troubleshooting
```bash
# Check ECS service status
aws ecs describe-services \
  --cluster <cluster-name> \
  --services tiles-service timeseries-service

# View logs
aws logs tail /ecs/tiles-service --follow

# Check OpenSearch health
aws opensearch describe-domain --domain-name <domain-name>
```

---

## 📈 Cost Estimates

| Configuration | Monthly Cost | Use Case |
|---------------|--------------|----------|
| **Default** | $265 | Production, high availability |
| **Cost-Optimized** | $120 | Development, testing |
| **With Scheduling** | $60 | Part-time development |
| **Minimal** | $45 | Proof-of-concept only |

See [COST_OPTIMIZATION.md](COST_OPTIMIZATION.md) for detailed breakdown.

---

## 🏗️ Architecture Overview

```
Internet → ALB → ECS Services (tiles, timeseries)
                    ↓
              ┌─────┴─────┐
              │           │
         OpenSearch    Redis
              │           │
              └─────┬─────┘
                    ↓
              S3 (Zarr/COG)

Ingestion (ECS-based, 99% cost savings):
S3 Upload → Lambda Trigger → Step Functions
                                ↓
                           ECS: Zarr Conversion (0.5 vCPU, 2GB)
                                ↓ (ResultSelector data flow)
                           ECS: COG Generation (0.5 vCPU, 2GB)
                                ↓
                           Lambda: STAC Creation
                                ↓
                           Lambda: STAC Indexing → OpenSearch
```

**Key Innovation**: Uses ResultSelector pattern for data flow between ECS tasks (no S3 intermediate storage needed)

---

## 🆘 Getting Help

### Common Issues
- **ECS services not starting**: Check [AUTOMATION_ISSUES_AND_FIXES.md](AUTOMATION_ISSUES_AND_FIXES.md)
- **Ingestion pipeline issues**: Check [ECS_ZARR_MIGRATION_RUNBOOK.md](ECS_ZARR_MIGRATION_RUNBOOK.md) troubleshooting section
- **Terraform destroy failing**: Check [TERRAFORM_DESTROY_ISSUES.md](TERRAFORM_DESTROY_ISSUES.md)
- **High costs**: Check [COST_OPTIMIZATION.md](COST_OPTIMIZATION.md) and [ECS_MIGRATION_COST_ANALYSIS.md](ECS_MIGRATION_COST_ANALYSIS.md)
- **CI/CD failing**: Check [GITHUB_ACTIONS_SETUP.md](GITHUB_ACTIONS_SETUP.md)

### Support Resources
- **CloudWatch Logs**: `/ecs/tiles-service`, `/ecs/timeseries-service`, `/ecs/zarr-conversion`, `/ecs/cog-generation`
- **CloudWatch Dashboard**: `{project_name}-ingestion-pipeline`
- **Monitoring Script**: `./scripts/monitor-ingestion-pipeline.sh`
- **AWS Console**: ECS, OpenSearch, S3, CloudWatch, Step Functions
- **Terraform State**: `terraform/terraform.tfstate`

---

## 📝 Document Status

| Document | Last Updated | Status |
|----------|--------------|--------|
| DEPLOYMENT_GUIDE.md | 2025-11 | ✅ Current |
| COST_OPTIMIZATION.md | 2025-11 | ✅ Current |
| **ECS_ZARR_MIGRATION_RUNBOOK.md** | **2025** | **✅ Current** |
| **ECS_MIGRATION_COST_ANALYSIS.md** | **2025** | **✅ Current** |
| **RESULTSELECTOR_DATA_FLOW_PATTERN.md** | **2025** | **✅ Current** |
| **INGESTION_PIPELINE_MONITORING.md** | **2025** | **✅ Current** |
| **ECS_MIGRATION_DEPLOYMENT.md** | **2025** | **✅ Current** |
| OPENSEARCH_COST_OPTIMIZATION.md | 2025-11 | ✅ Current |
| AUTOMATION_ISSUES_AND_FIXES.md | 2025-11 | ✅ Current |
| INFRASTRUCTURE_AS_CODE.md | 2025-11 | ✅ Current |
| INGESTION_PIPELINE.md | 2025-11 | ✅ Current |
| TERRAFORM_DESTROY_ISSUES.md | 2025-11 | ✅ Current |
| GITHUB_ACTIONS_SETUP.md | 2025-11 | ✅ Current |
| SECURITY_SCANNING.md | 2025-11 | ✅ Current |

---

## 🎓 Learning Path

### Beginner
1. [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) - Understand the basics
2. [COST_OPTIMIZATION.md](COST_OPTIMIZATION.md) - Learn cost management
3. [INGESTION_PIPELINE.md](INGESTION_PIPELINE.md) - Upload your first dataset

### Intermediate
1. [INFRASTRUCTURE_AS_CODE.md](INFRASTRUCTURE_AS_CODE.md) - Understand IaC principles
2. [GITHUB_ACTIONS_SETUP.md](GITHUB_ACTIONS_SETUP.md) - Set up automation
3. [API_ROUTES_CHANGELOG.md](API_ROUTES_CHANGELOG.md) - Integrate with API

### Advanced
1. [AUTOMATION_ISSUES_AND_FIXES.md](AUTOMATION_ISSUES_AND_FIXES.md) - Deep troubleshooting
2. [SECURITY_SCANNING.md](SECURITY_SCANNING.md) - Security hardening
3. [OPENSEARCH_COST_OPTIMIZATION.md](OPENSEARCH_COST_OPTIMIZATION.md) - Advanced optimization

---

## 🔄 Updates & Maintenance

This documentation is actively maintained. Key updates:
- **2025**: **Added ECS-based ingestion pipeline documentation (99% cost savings)**
- **2025**: **Added ResultSelector data flow pattern technical guide**
- **2025**: **Added comprehensive ingestion pipeline operations runbook**
- **2025-11**: Added Graviton (ARM) cost optimization guides
- **2025-11**: Fixed automation issues (HTTP-first deployment)
- **2025-11**: Added comprehensive troubleshooting guides
- **2025-11**: Created this documentation index

---

## 📞 Contact

- **Project Owner**: 
- **Repository**: [GitHub Repository URL]
- **AWS Account**: 
- **Region**: 

---

**Last Updated**: December 2025 
**Version**: 1.0  
**Status**: Proof-of-Concept Ready
