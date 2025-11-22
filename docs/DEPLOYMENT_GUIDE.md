# Deployment Guide

## 🎉 Infrastructure Successfully Deployed!

Your Raster Time-series Access Web Service infrastructure is now live on AWS.

## Quick Start - Testing Your Deployment

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

## Next Steps

### A. Build and Push Docker Image

Your application code is ready, but you need to build and push the Docker image to ECR:

```bash
# 1. Get ECR repository URL
ECR_REPO=$(terraform output -raw ecr_repository_url)

# 2. Login to ECR
aws ecr get-login-password --region ap-southeast-2 | \
  docker login --username AWS --password-stdin $ECR_REPO

# 3. Build the Docker image
cd app
docker build -t raster-app .

# 4. Tag the image
docker tag raster-app:latest $ECR_REPO:latest

# 5. Push to ECR
docker push $ECR_REPO:latest
```

### B. Start ECS Services

Once the image is pushed, ECS will automatically pull and run it:

```bash
# Check ECS service status
aws ecs describe-services \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --services tiles-service timeseries-service \
  --query 'services[*].[serviceName,status,runningCount,desiredCount]' \
  --output table
```

Wait a few minutes for tasks to start, then test again:

```bash
curl http://$ALB_DNS/health
```

### C. Set Up GitHub Secrets for CI/CD

To enable automated deployments, add these secrets to your GitHub repository:

1. Go to: **Settings** → **Secrets and variables** → **Actions**
2. Add these secrets:

```
AWS_ACCESS_KEY_ID=<your-aws-access-key>
AWS_SECRET_ACCESS_KEY=<your-aws-secret-key>
ECR_REPOSITORY=<from terraform output ecr_repository_url, just the repo name>
ECS_CLUSTER=<from terraform output ecs_cluster_name>
ECS_SERVICE_TILES=tiles-service
ECS_SERVICE_TIMESERIES=timeseries-service
ECS_TASK_DEFINITION_TILES=tiles-service
ECS_TASK_DEFINITION_TIMESERIES=timeseries-service
ALB_URL=http://<alb_dns_name>
```

After adding secrets, every push to `main` will:
- Run tests
- Build Docker image
- Push to ECR
- Deploy to ECS
- Run smoke tests

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
3. Convert NetCDF → Zarr
4. Generate COG with overviews
5. Create STAC metadata
6. Index in OpenSearch

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

## What's Next?

1. ✅ Infrastructure deployed
2. ⏳ Build and push Docker image
3. ⏳ Wait for ECS services to start
4. ⏳ Upload test data
5. ⏳ Configure GitHub secrets for CI/CD
6. ⏳ Set up HTTPS (optional)
7. ⏳ Configure custom domain (optional)

Congratulations on your deployment! 🚀
