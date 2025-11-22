# Quick Start Guide

## ✅ Your Infrastructure is Deployed!

## Immediate Next Steps

### 1. Get Your ALB URL (2 minutes)

```bash
cd terraform
ALB_DNS=$(terraform output -raw alb_dns_name)
echo "Your API URL: http://$ALB_DNS"
```

### 2. Test Health Endpoint

```bash
curl http://$ALB_DNS/health
```

**Expected:** `{"status":"ok"}` ✅

**If you get an error:** ECS services haven't started yet (need Docker image)

### 3. Build & Deploy Docker Image (5 minutes)

```bash
# Get ECR URL
ECR_REPO=$(terraform output -raw ecr_repository_url)

# Login to ECR
aws ecr get-login-password --region ap-southeast-2 | \
  docker login --username AWS --password-stdin $ECR_REPO

# Build and push
cd app
docker build -t raster-app .
docker tag raster-app:latest $ECR_REPO:latest
docker push $ECR_REPO:latest
```

### 4. Wait for ECS Services (3-5 minutes)

```bash
# Check service status
watch -n 10 'aws ecs describe-services \
  --cluster $(cd terraform && terraform output -raw ecs_cluster_name) \
  --services tiles-service timeseries-service \
  --query "services[*].[serviceName,runningCount,desiredCount]" \
  --output table'
```

Wait until `runningCount` matches `desiredCount` (should be 2/2 for each)

### 5. Test Again

```bash
curl http://$ALB_DNS/health
curl http://$ALB_DNS/metrics
```

## GitHub CI/CD Setup (5 minutes)

Add these secrets to your GitHub repo (**Settings** → **Secrets** → **Actions**):

```bash
# Get values from Terraform
cd terraform

echo "AWS_ACCESS_KEY_ID: <your-aws-key>"
echo "AWS_SECRET_ACCESS_KEY: <your-aws-secret>"
echo "ECR_REPOSITORY: $(terraform output -raw ecr_repository_url | cut -d'/' -f2)"
echo "ECS_CLUSTER: $(terraform output -raw ecs_cluster_name)"
echo "ECS_SERVICE_TILES: tiles-service"
echo "ECS_SERVICE_TIMESERIES: timeseries-service"
echo "ECS_TASK_DEFINITION_TILES: tiles-service"
echo "ECS_TASK_DEFINITION_TIMESERIES: timeseries-service"
echo "ALB_URL: http://$(terraform output -raw alb_dns_name)"
```

## Test Data Ingestion (Optional)

```bash
# Upload a NetCDF file to trigger ingestion
RAW_BUCKET=$(cd terraform && terraform output -raw s3_raw_bucket)
aws s3 cp your-data.nc s3://$RAW_BUCKET/ingestion/test-data.nc

# Monitor Step Functions
aws stepfunctions list-executions \
  --state-machine-arn $(cd terraform && terraform output -raw ingestion_state_machine_arn)
```

## Useful Commands

```bash
# View logs
aws logs tail /ecs/tiles-service --follow

# Check ECS tasks
aws ecs list-tasks --cluster $(cd terraform && terraform output -raw ecs_cluster_name)

# Get all outputs
cd terraform && terraform output
```

## Troubleshooting

**Health endpoint returns error?**
- ECS services may not be running yet
- Check: `aws ecs describe-services --cluster <cluster-name> --services tiles-service`

**Docker push fails?**
- Ensure you're logged into ECR: `aws ecr get-login-password ...`
- Check ECR repository exists: `aws ecr describe-repositories`

**Services won't start?**
- Check CloudWatch logs: `aws logs tail /ecs/tiles-service`
- Verify Docker image exists in ECR

## What You Have Now

✅ VPC with public/private subnets  
✅ Application Load Balancer (HTTP)  
✅ ECS Fargate cluster  
✅ OpenSearch for STAC catalog  
✅ Redis for caching  
✅ S3 buckets for data  
✅ Ingestion pipeline (Lambda + Step Functions)  
✅ Dask cluster for distributed processing  
✅ CloudWatch monitoring & alarms  
✅ GitHub Actions CI/CD pipeline  

## What's Not Yet Configured

⏸️ HTTPS/SSL (requires ACM certificate)  
⏸️ CloudFront CDN (requires certificate)  
⏸️ Custom domain  
⏸️ Cognito authentication  
⏸️ WAF protection  

See `docs/DEPLOYMENT_GUIDE.md` for full details!
