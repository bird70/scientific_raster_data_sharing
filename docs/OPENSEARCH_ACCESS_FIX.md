# OpenSearch Access Policy Fix

## Issue

After deploying the infrastructure, the ECS tasks were unable to access OpenSearch, resulting in:

```
AuthorizationException(403, '{"Message":"User: anonymous is not authorized to perform: es:ESHttpPost because no resource-based policy allows the es:ESHttpPost action"}')
```

## Root Cause

The OpenSearch domain was created without a resource-based access policy, which blocked all access even though the ECS task role had the correct IAM permissions.

## Solution

Add a resource-based access policy to the OpenSearch domain to allow the ECS task role:

```bash
aws opensearch update-domain-config \
    --domain-name cloud-sciraster-stac \
    --access-policies '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"AWS":"arn:aws:iam::123456789101:role/cloud-scientific-raster-sharing-ecs-task-role"},"Action":"es:*","Resource":"arn:aws:es:ap-southeast-2:123456789101:domain/cloud-sciraster-stac/*"}]}'
```

## Verification

1. **Check update status:**
   ```bash
   aws opensearch describe-domain --domain-name cloud-sciraster-stac --query 'DomainStatus.Processing'
   ```

2. **Test tiles endpoint after update completes:**
   ```bash
   ALB_DNS=$(cd terraform && terraform output -raw alb_dns_name)
   curl "http://$ALB_DNS/tiles/test-collection/10/512/512.png"
   ```

## Why This Happened

OpenSearch domains in VPC require both:
1. **IAM permissions** on the ECS task role (✅ already configured)
2. **Resource-based access policy** on the domain (❌ was missing)

The Terraform configuration created the IAM permissions but didn't set the domain access policy.

## Prevention

To prevent this in future deployments, the Terraform OpenSearch resource should include an `access_policies` block:

```hcl
resource "aws_opensearch_domain" "stac" {
  domain_name = "${var.short_name}-stac"
  
  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-ecs-task-role"
        }
        Action   = "es:*"
        Resource = "arn:aws:es:${var.aws_region}:${data.aws_caller_identity.current.account_id}:domain/${var.short_name}-stac/*"
      }
    ]
  })
  
  # ... rest of configuration
}
```

## Related Issues

This fix resolves:
- ✅ Tiles endpoint returning 500 errors
- ✅ GitHub Actions smoke tests failing
- ✅ OpenSearch authentication errors in ECS logs
- ✅ "User: anonymous" errors in application logs

## Timeline

- **Issue discovered:** ECS logs showed OpenSearch 403 errors
- **Root cause identified:** Missing domain access policy
- **Fix applied:** Added resource-based access policy
- **Resolution:** ~5 minutes for policy update to complete