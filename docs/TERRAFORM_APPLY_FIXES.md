# Terraform Apply Error Fixes

## Current Errors and Solutions

### 1. Certificate Issues
**Error**: `Certificate 'arn:aws:acm:ap-southeast-2:123456789101:certificate/PLACEHOLDER' not found`

**Solution**: 
```bash
# Option A: Disable HTTPS temporarily
# In terraform.tfvars, comment out or set:
# alb_certificate_arn = ""

# Option B: Create a real certificate
aws acm request-certificate \
  --domain-name your-domain.com \
  --validation-method DNS \
  --region ap-southeast-2
```

### 2. CloudWatch Log Groups Already Exist
**Error**: `ResourceAlreadyExistsException: The specified log group already exists`

**Solution**:
```bash
# Import existing log groups
terraform import module.ecs.aws_cloudwatch_log_group.cog_generation /ecs/cog-generation
terraform import module.ecs.aws_cloudwatch_log_group.zarr_conversion /ecs/zarr-conversion
```

### 3. CloudFront Certificate Region Issue
**Error**: `SSL certificate doesn't exist, isn't in us-east-1 region`

**Solution**: CloudFront requires certificates in `us-east-1`:
```bash
# Create certificate in us-east-1 for CloudFront
aws acm request-certificate \
  --domain-name your-domain.com \
  --validation-method DNS \
  --region us-east-1
```

## Immediate Fix Steps

### Step 1: Disable HTTPS temporarily
```hcl
# In terraform.tfvars
alb_certificate_arn = ""
```

### Step 2: Import existing log groups
```bash
terraform import module.ecs.aws_cloudwatch_log_group.cog_generation /ecs/cog-generation
terraform import module.ecs.aws_cloudwatch_log_group.zarr_conversion /ecs/zarr-conversion
```

### Step 3: Disable CloudFront temporarily
```hcl
# In main.tf, comment out or set:
enable_cloudfront = false
```

### Step 4: Re-run terraform apply
```bash
terraform apply
```

## Long-term Certificate Setup

### For ALB (ap-southeast-2)
```bash
aws acm request-certificate \
  --domain-name cloud-sciraster.your-domain.com \
  --validation-method DNS \
  --region ap-southeast-2
```

### For CloudFront (us-east-1)
```bash
aws acm request-certificate \
  --domain-name cloud-sciraster.your-domain.com \
  --validation-method DNS \
  --region us-east-1
```

## Alternative: HTTP-only Development Setup

For development, you can run without HTTPS:

```hcl
# terraform.tfvars
alb_certificate_arn = ""
enable_cloudfront = false
```

This will:
- Use HTTP only (port 80)
- Skip CloudFront distribution
- Avoid certificate requirements
- Allow testing with ALB domain directly

## Validation Commands

```bash
# Check certificate status
aws acm list-certificates --region ap-southeast-2
aws acm list-certificates --region us-east-1

# Check log groups
aws logs describe-log-groups --log-group-name-prefix "/ecs/"

# Test ALB endpoint
curl -I http://cloud-sciraster-alb-1212121212.ap-southeast-2.elb.amazonaws.com/health
```