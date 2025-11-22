# Terraform Fixes Applied

## Issues Fixed

### 1. OpenSearch Version
**Error**: `Unsupported Version: OpenSearch_2.8`
**Fix**: Changed to `OpenSearch_2.9` in `modules/data/main.tf`

### 2. Redis Encryption
**Error**: `Encryption feature is not supported for engine REDIS`
**Fix**: Removed `transit_encryption_enabled` from ElastiCache cluster in `modules/data/main.tf`

### 3. Lambda Environment Variables
**Error**: `AWS_REGION is a reserved key`
**Fix**: Removed `AWS_REGION` from Lambda environment variables in `modules/ingestion/main.tf` (it's automatically available)

### 4. VPC Endpoint for OpenSearch
**Error**: `Service 'com.amazonaws.ap-southeast-2.es' does not exist`
**Fix**: Changed service name from `es` to `aos` in `modules/network/main.tf`

### 5. SSL Certificate (ALB & CloudFront)
**Error**: Certificate not found / invalid
**Fix**: 
- Made HTTPS listener conditional in `modules/ecs/main.tf`
- Added HTTP listener (port 80) as default
- Made CloudFront module conditional in `main.tf`
- Both only create if valid certificate ARN is provided

## How to Deploy

### Option 1: Without SSL Certificate (HTTP only)
1. Keep the placeholder certificate ARN in `terraform.tfvars`
2. Run `terraform apply`
3. Access via HTTP: `http://<alb-dns-name>`

### Option 2: With SSL Certificate (HTTPS)
1. Create an ACM certificate in AWS Console (ap-southeast-2 region)
2. Update `alb_certificate_arn` in `terraform.tfvars` with real ARN
3. Run `terraform apply`
4. Access via HTTPS: `https://<alb-dns-name>` or CloudFront domain

## Next Steps

After successful `terraform apply`:

1. Get outputs:
   ```bash
   terraform output
   ```

2. Note these values for GitHub secrets:
   - `alb_dns_name` → Use for ALB_URL secret
   - ECS cluster name → ECS_CLUSTER secret
   - Service names → ECS_SERVICE_* secrets

3. Create ECR repository:
   ```bash
   aws ecr create-repository --repository-name raster-app-prod-repo --region ap-southeast-2
   ```

4. Add GitHub secrets with actual values

## Testing

Test the HTTP endpoint:
```bash
ALB_DNS=$(terraform output -raw alb_dns_name)
curl http://$ALB_DNS/health
```
