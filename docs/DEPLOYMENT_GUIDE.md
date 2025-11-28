# Deployment Guide

## 🎉 Deployment Guide

This guide covers deploying the Raster Time-series Access Web Service infrastructure on AWS.

## Prerequisites

### Required (One-Time Setup)

1. **AWS Account** with appropriate permissions
2. **Terraform** >= 1.5.0 installed
3. **AWS CLI** configured with credentials
4. **Docker** installed (for building images)

### Configuration File

Create `terraform/terraform.tfvars`:

```terraform
# Required
service_owner  = "Your Name"
project_title  = "cloud-scientific-raster-sharing"
environment    = "dev"

# Optional - Leave empty for HTTP-only deployment
alb_certificate_arn  = ""  # Add ACM certificate ARN for HTTPS
domain_name          = ""  # Add custom domain for CloudFront
cognito_user_pool_id = ""  # Add for authentication
cognito_client_id    = ""  # Add for authentication

# Cost optimization
tiles_desired_count      = 2
timeseries_desired_count = 2
dask_workers_min         = 2
```

## Deployment Options

### Option 1: HTTP-Only (Fully Automated) ✅ RECOMMENDED FOR DEV

**Advantages**:
- ✅ Zero manual steps after terraform.tfvars setup
- ✅ Works immediately
- ✅ CI/CD pipeline compatible
- ✅ Perfect for development/testing

**Limitations**:
- ⚠️ HTTP only (no HTTPS)
- ⚠️ No CloudFront CDN

**Steps**:
```bash
cd terraform
terraform init
terraform apply
```

### Option 2: HTTPS with Certificate (One Manual Step) 🔒 RECOMMENDED FOR PROD

**Advantages**:
- ✅ HTTPS encryption
- ✅ CloudFront CDN (optional)
- ✅ Production-ready

**Limitations**:
- ⚠️ Requires manual ACM certificate creation (one-time)

**Steps**:
1. Create ACM certificate in AWS Console (see below)
2. Update `terraform.tfvars` with certificate ARN
3. Run `terraform apply`

---

## Quick Start - HTTP-Only Deployment

### Step 1: Deploy Infrastructure

```bash
cd terraform
terraform init
terraform apply
```

**What gets created**:
- VPC with public/private subnets
- S3 buckets (raw, zarr, cog, stac)
- OpenSearch domain
- Redis cluster
- ALB with HTTP listener
- ECS cluster with services (tiles, timeseries, dask)
- Ingestion pipeline (Lambda, Step Functions, ECS tasks)
- CloudWatch monitoring

**Time**: ~15-20 minutes (OpenSearch takes longest)

### Step 2: Build and Push Docker Image

```bash
# Get ECR repository URL
ECR_REPO=$(terraform output -raw ecr_repository_url)

# Login to ECR
aws ecr get-login-password --region ap-southeast-2 | \
  docker login --username AWS --password-stdin $ECR_REPO

# Build and push
cd ../app
docker build -t $ECR_REPO:latest .
docker push $ECR_REPO:latest
```

### Step 3: Wait for ECS Services to Start

```bash
# Check service status
aws ecs describe-services \
  --cluster $(cd ../terraform && terraform output -raw ecs_cluster_name) \
  --services tiles-service timeseries-service \
  --query 'services[*].[serviceName,runningCount,desiredCount]' \
  --output table
```

Wait until `runningCount` = `desiredCount` (usually 2-3 minutes)

### Step 4: Test Your Deployment

### 1. Get Your Infrastructure Outputs

```bash
cd terraform
terraform output
```

You should see outputs including:
- `alb_dns_name` - Your Application Load Balancer URL
- `ecs_cluster_name` - ECS cluster name
- `ecr_repository_url` - Docker registry URL
- `opensearch_endpoint` - OpenSearch domain endpoint
- `s3_zarr_bucket` - Zarr data bucket
- `s3_cog_bucket` - COG data bucket

### 2. Test the Health Endpoint

```bash
# Get the ALB DNS name
ALB_DNS=$(terraform output -raw alb_dns_name)

# Test health endpoint (HTTP)
curl http://$ALB_DNS/health

# Expected response:
# {"status":"ok"}
```

### 3. Test the Metrics Endpoint

```bash
# Check Prometheus metrics
curl http://$ALB_DNS/metrics

# You should see Prometheus-format metrics like:
# raster_http_requests_total{...}
# raster_request_latency_seconds{...}
```

---

## Adding HTTPS (Optional)

### Step 1: Create ACM Certificate

**AWS Console**:
1. Go to **Certificate Manager** in `ap-southeast-2` region
2. Click **Request certificate**
3. Choose **Request a public certificate**
4. Enter your domain name (e.g., `api.example.com`)
5. Choose **DNS validation**
6. Click **Request**
7. Add the CNAME record to your DNS provider
8. Wait for status to change to **Issued** (5-30 minutes)

### Step 2: Update Terraform Configuration

Edit `terraform/terraform.tfvars`:
```terraform
alb_certificate_arn = "arn:aws:acm:ap-southeast-2:123456789101:certificate/YOUR-CERT-ID"
domain_name         = "api.example.com"  # Optional, for CloudFront
```

### Step 3: Apply Changes

```bash
cd terraform
terraform apply
```

**What gets created**:
- HTTPS listener on ALB (port 443)
- CloudFront distribution (if domain_name set)
- Automatic HTTP → HTTPS redirect

**Time**: ~5 minutes (CloudFront takes 10-15 minutes if enabled)

### Step 4: Test HTTPS

```bash
ALB_DNS=$(terraform output -raw alb_dns_name)
curl https://$ALB_DNS/health
```

---

## CI/CD Pipeline Setup

### GitHub Secrets Configuration

**Required Secrets** (Settings → Secrets and variables → Actions):

```bash
# Get values from Terraform outputs
cd terraform
terraform output

# Add to GitHub Secrets:
AWS_ROLE_ARN=arn:aws:iam::123456789101:role/github-actions-role  # Create this role
ECR_REPOSITORY=cloud-scientific-raster-sharing-repo
```

**GitHub Actions Workflow** (already configured in `.github/workflows/deploy.yml`):

✅ Runs tests on every push
✅ Builds Docker image on main branch
✅ Pushes to ECR automatically
✅ ECS pulls new image and redeploys
✅ Zero-downtime rolling deployment

**Note**: The workflow checks if ECR repository exists before attempting deployment, preventing failures when infrastructure doesn't exist yet.

## Testing the Application

### Test Tiles Endpoint (Once Services Are Running)

```bash
# This will return a 404 until you have data indexed
curl -I http://$ALB_DNS/tiles/test-collection/10/512/512.png
```

### Test Timeseries Endpoint

```bash
# This will return empty results until you have data
curl "http://$ALB_DNS/api/timeseries?lon=150&lat=-33&start=2024-01-01T00:00:00Z&end=2024-01-31T23:59:59Z&variable=temp"
```

## Ingesting Data

### Upload NetCDF File to Trigger Ingestion

```bash
# Get the raw bucket name
RAW_BUCKET=$(terraform output -raw s3_raw_bucket)

# Upload a NetCDF file (triggers automatic conversion)
aws s3 cp your-data.nc s3://$RAW_BUCKET/ingestion/your-data.nc

# Monitor the Step Functions execution
aws stepfunctions list-executions \
  --state-machine-arn $(terraform output -raw ingestion_state_machine_arn) \
  --max-results 5
```

The ingestion pipeline will:
1. Detect the upload (Lambda trigger)
2. Start Step Functions workflow
3. Convert NetCDF → Zarr (with CRS detection and metadata extraction)
4. Generate COG with overviews
5. Create STAC metadata (with collections and searchable metadata)
6. Index in OpenSearch

**New Features**:
- ✅ Automatic CRS detection and coordinate transformation (supports NZTM, UTM, etc.)
- ✅ Variable metadata extraction (name, units, standard_name)
- ✅ Collection organization by variable type
- ✅ Searchable metadata (query by variable, units, institution)

See [NetCDF Metadata Enhancement Guide](NETCDF_METADATA_ENHANCEMENT.md) for details.

## Monitoring

### View CloudWatch Logs

```bash
# Tiles service logs
aws logs tail /ecs/tiles-service --follow

# Timeseries service logs
aws logs tail /ecs/timeseries-service --follow

# Lambda logs
aws logs tail /aws/lambda/raster-app-prod-ingestion-trigger --follow
```

### Check CloudWatch Alarms

```bash
# List active alarms
aws cloudwatch describe-alarms \
  --alarm-name-prefix raster-app-prod \
  --state-value ALARM
```

### View Metrics

```bash
# Get request count
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name RequestCount \
  --dimensions Name=LoadBalancer,Value=$(terraform output -raw alb_arn_suffix) \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

## Troubleshooting

### Services Not Starting

```bash
# Check task failures
aws ecs describe-tasks \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --tasks $(aws ecs list-tasks --cluster $(terraform output -raw ecs_cluster_name) --query 'taskArns[0]' --output text)
```

### OpenSearch Not Accessible

OpenSearch is in a VPC and only accessible from ECS tasks. To test:

```bash
# Get OpenSearch endpoint
OPENSEARCH_ENDPOINT=$(terraform output -raw opensearch_endpoint)

# It should NOT be accessible from your local machine (this is correct!)
curl https://$OPENSEARCH_ENDPOINT/_cluster/health
# Expected: Connection timeout (this is secure!)
```

### Check ECS Task Logs

```bash
# Get recent log events
aws logs tail /ecs/tiles-service --since 10m
```

## Architecture Overview

```
Internet → CloudFront (optional) → ALB → ECS Services
                                          ↓
                                    ┌─────┴─────┐
                                    │           │
                                OpenSearch    Redis
                                    │           │
                                    └─────┬─────┘
                                          ↓
                                    S3 (Zarr/COG)
```

## Cost Optimization

Current setup runs:
- 2 tiles service tasks (t3.small equivalent)
- 2 timeseries service tasks (t3.medium equivalent)
- 2 Dask workers (t3.medium equivalent)
- 1 Dask scheduler (t3.small equivalent)
- OpenSearch 2-node cluster (t3.small.search)
- Redis single node (cache.t3.small)

To reduce costs:
1. Scale down ECS services: `desired_count = 1`
2. Use smaller OpenSearch: `instance_count = 1`
3. Stop services when not in use

## Security Notes

✅ **What's Secure:**
- All services in private subnets
- OpenSearch only accessible via VPC
- Redis only accessible via VPC
- Security groups restrict access
- IAM roles follow least privilege

⚠️ **What's Not Yet Configured:**
- HTTPS (requires ACM certificate)
- CloudFront CDN (requires certificate)
- WAF (optional)
- Cognito authentication (optional)

To add HTTPS:
1. Create ACM certificate in AWS Console
2. Update `alb_certificate_arn` in `terraform.tfvars`
3. Run `terraform apply`

## Cleanup

To destroy all infrastructure:

```bash
cd terraform
terraform destroy
```

**Warning:** This will delete all data in S3 buckets, OpenSearch, and Redis!

## Support

- **Terraform Issues**: Check `terraform/TERRAFORM_FIXES.md`
- **Application Logs**: CloudWatch Logs
- **Infrastructure**: AWS Console → ECS/OpenSearch/S3
- **CI/CD**: GitHub Actions workflow logs

## Ingestion Pipeline

### Overview
The platform includes an automated data ingestion pipeline that converts NetCDF files to Zarr and COG formats.

**Full Documentation**: See `INGESTION_PIPELINE.md`

### Quick Start

```bash
# Upload NetCDF file to trigger ingestion
RAW_BUCKET=$(terraform output -raw s3_raw_bucket)
aws s3 cp your-data.nc s3://$RAW_BUCKET/ingestion/your-data.nc

# Monitor Step Functions execution
aws stepfunctions list-executions \
  --state-machine-arn $(terraform output -raw ingestion_state_machine_arn) \
  --max-results 5

# View conversion logs
aws logs tail /ecs/zarr-conversion --follow
aws logs tail /ecs/cog-generation --follow
```

### Pipeline Components

1. **S3 Upload** → Lambda trigger detects new files
2. **Step Functions** → Orchestrates conversion workflow
3. **Zarr Conversion** → ECS task converts NetCDF to Zarr
4. **COG Generation** → ECS task creates Cloud Optimized GeoTIFFs
5. **STAC Indexing** → Metadata indexed in OpenSearch

### Infrastructure as Code

All ingestion components are fully managed by Terraform:
- ECS task definitions: `terraform/modules/ecs/main.tf`
- Step Functions state machine: `terraform/modules/ingestion/main.tf`
- IAM permissions: `terraform/modules/iam/main.tf`

No manual AWS CLI commands required - `terraform apply` creates everything.

---

## Deployment Checklist

### Initial Deployment
- [ ] Create `terraform/terraform.tfvars` with required variables
- [ ] Run `terraform init`
- [ ] Run `terraform apply` (15-20 minutes)
- [ ] Build and push Docker image to ECR
- [ ] Wait for ECS services to start (2-3 minutes)
- [ ] Test health endpoint: `curl http://<alb-dns>/health`
- [ ] Configure GitHub secrets for CI/CD

### Optional Enhancements
- [ ] Create ACM certificate for HTTPS
- [ ] Update terraform.tfvars with certificate ARN
- [ ] Run `terraform apply` to enable HTTPS
- [ ] Configure custom domain in Route53
- [ ] Enable CloudFront CDN
- [ ] Set up Cognito for authentication
- [ ] Configure WAF rules

### Production Readiness
- [ ] Review IAM permissions (least privilege)
- [ ] Enable S3 bucket versioning
- [ ] Configure backup retention policies
- [ ] Set up CloudWatch alarms
- [ ] Configure log aggregation
- [ ] Document runbook procedures
- [ ] Test disaster recovery

---

## Troubleshooting

### Issue: ECS Services Not Starting

**Symptom**: `runningCount` = 0, `desiredCount` = 2

**Solution**:
```bash
# Check task failures
aws ecs list-tasks --cluster <cluster-name> --desired-status STOPPED
aws ecs describe-tasks --cluster <cluster-name> --tasks <task-arn>

# Common causes:
# 1. Docker image not pushed to ECR
# 2. Task role missing permissions
# 3. Security group blocking traffic
```

### Issue: Health Endpoint Returns 503

**Symptom**: `curl http://<alb-dns>/health` returns 503

**Solution**:
```bash
# Check target group health
aws elbv2 describe-target-health \
  --target-group-arn <tiles-tg-arn>

# Common causes:
# 1. Tasks not registered with target group
# 2. Health check failing
# 3. Security group blocking ALB → ECS traffic
```

### Issue: Terraform Apply Fails with Certificate Error

**Symptom**: `Error: Invalid certificate ARN`

**Solution**:
```terraform
# In terraform.tfvars, set to empty string for HTTP-only:
alb_certificate_arn = ""

# Or use valid certificate ARN:
alb_certificate_arn = "arn:aws:acm:ap-southeast-2:123456789101:certificate/REAL-ID"
```

### Issue: CloudWatch Log Groups Already Exist

**Symptom**: `Error: CloudWatch log group already exists`

**Solution**:
```bash
# Import existing log groups
terraform import module.ecs.aws_cloudwatch_log_group.zarr_conversion /ecs/zarr-conversion
terraform import module.ecs.aws_cloudwatch_log_group.cog_generation /ecs/cog-generation
```

---

## Architecture Summary

```
Internet
  |
  v
[ALB] ← HTTP/HTTPS
  |
  ├─→ [ECS: tiles-service] ← Serves tile requests
  │     ↓
  │   [S3: COG bucket] ← Cloud Optimized GeoTIFFs
  │
  ├─→ [ECS: timeseries-service] ← Serves timeseries queries
  │     ↓
  │   [S3: Zarr bucket] ← Zarr arrays
  │     ↓
  │   [Dask cluster] ← Parallel processing
  │
  └─→ [OpenSearch] ← STAC metadata index
       [Redis] ← Caching layer

Ingestion Pipeline:
  S3 upload → Lambda → Step Functions → ECS tasks → Zarr/COG → OpenSearch
```

---

## Cost Optimization

**Current Monthly Cost** (ap-southeast-2, dev environment):
- ECS Fargate: ~$150 (4 services, 2 tasks each)
- OpenSearch: ~$50 (2x t3.small.search)
- Redis: ~$25 (cache.t3.small)
- ALB: ~$20
- S3: ~$5 (100GB storage)
- Data transfer: ~$10
- **Total: ~$260/month**

**Cost Reduction Options**:
1. Scale down to 1 task per service: Save ~$75/month
2. Use 1-node OpenSearch: Save ~$25/month
3. Stop services when not in use: Save ~$150/month
4. Use S3 Intelligent-Tiering: Save ~$2/month

**Production Scaling** (estimated):
- 10 tasks per service: ~$750/month
- 3-node OpenSearch (m5.large): ~$400/month
- Redis cluster (cache.m5.large): ~$150/month
- CloudFront: ~$50/month (1TB transfer)
- **Total: ~$1,400/month**

---

## Next Steps

Congratulations on your deployment! 🚀

**Immediate**:
1. Test the health endpoint
2. Upload sample data to test ingestion pipeline
3. Configure GitHub Actions for CI/CD

**Short-term**:
1. Create ACM certificate for HTTPS
2. Set up custom domain
3. Configure monitoring alerts

**Long-term**:
1. Implement authentication (Cognito)
2. Add WAF rules for security
3. Set up multi-region deployment
4. Implement backup and disaster recovery

**Documentation**:
- `INGESTION_PIPELINE.md` - Data ingestion workflow
- `INFRASTRUCTURE_AS_CODE.md` - IaC verification
- `AUTOMATION_ISSUES_AND_FIXES.md` - Troubleshooting automation
- `COST_OPTIMIZATION.md` - Cost management strategies
