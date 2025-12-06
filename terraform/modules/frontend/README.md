# Frontend Module

This Terraform module creates the infrastructure for hosting the React frontend as a static website.

## Resources Created

- **S3 Bucket**: Stores the frontend static files (HTML, JS, CSS, assets)
- **S3 Bucket Policy**: Allows CloudFront to access the bucket via Origin Access Identity
- **CloudFront Origin Access Identity (OAI)**: Secures S3 bucket access
- **S3 Versioning**: Enables rollback capability
- **S3 Lifecycle Policy**: Cleans up old versions after 30 days
- **S3 Public Access Block**: Prevents public access (CloudFront only)

## Usage

```hcl
module "frontend" {
  source       = "./modules/frontend"
  project_name = "my-project"
  environment  = "dev"
  tags         = {
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| project_name | Name prefix for frontend resources | string | n/a | yes |
| environment | Environment name (dev, staging, prod) | string | "dev" | no |
| tags | Tags to apply to all resources | map(string) | {} | no |

## Outputs

| Name | Description |
|------|-------------|
| bucket_name | Name of the S3 bucket |
| bucket_arn | ARN of the S3 bucket |
| bucket_regional_domain_name | Regional domain name for CloudFront origin |
| cloudfront_oai_iam_arn | IAM ARN of the CloudFront OAI |
| cloudfront_oai_path | CloudFront OAI path for origin configuration |
| website_endpoint | S3 website endpoint |

## Deployment

After applying this module, deploy the frontend with:

```bash
# Build the frontend
cd frontend
npm run build

# Sync to S3
aws s3 sync dist/ s3://$(terraform output -raw frontend_bucket_name)/ --delete

# Invalidate CloudFront cache
aws cloudfront create-invalidation \
  --distribution-id $(terraform output -raw cloudfront_distribution_id) \
  --paths "/*"
```

## Security

- S3 bucket is private (no public access)
- CloudFront accesses S3 via Origin Access Identity
- All traffic is HTTPS only
- Versioning enabled for rollback
- Old versions automatically deleted after 30 days

## Cost Optimization

- S3 Standard storage class (optimize later with Intelligent-Tiering if needed)
- Lifecycle policy removes old versions
- CloudFront caching reduces S3 requests
