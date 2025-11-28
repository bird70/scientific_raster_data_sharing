# GitHub Secrets Setup Guide

## Required Secrets for CI/CD Pipeline

Your GitHub Actions workflow needs these secrets to deploy to AWS. Follow the steps below to configure them.

## How to Add Secrets

1. Go to your GitHub repository
2. Click **Settings** (top menu)
3. Click **Secrets and variables** > **Actions** (left sidebar)
4. Click **"New repository secret"** for each secret below

## Secrets to Configure

### 1. AWS Authentication (Choose One)

**Option A: OIDC (Recommended for GitHub Enterprise)**

**AWS_ROLE_ARN**
- Description: IAM role ARN for OIDC authentication
- Value: `arn:aws:iam::ACCOUNT_ID:role/GitHubActions-cloud-Role`
- How to get: See `docs/GITHUB_OIDC_SETUP.md` for complete setup
- Benefits: No long-lived credentials, automatic rotation, better security

**Option B: Access Keys (Legacy)**

**AWS_ACCESS_KEY_ID**
- Description: AWS access key for deployment
- Value: Your AWS access key ID
- How to get: From AWS IAM console or your AWS credentials file

**AWS_SECRET_ACCESS_KEY**
- Description: AWS secret key for deployment
- Value: Your AWS secret access key
- How to get: From AWS IAM console (shown only once when created)

### 2. ECR Configuration

**ECR_REPOSITORY**
- Description: ECR repository name (without registry URL)
- Value: `raster-app-prod-repo`
- How to get: Run `terraform output ecr_repository_url` and use only the part after the `/`

### 3. ECS Configuration

**ECS_CLUSTER**
- Description: ECS cluster name
- Value: `raster-app-prod-ecs-cluster`
- How to get: Run `terraform output ecs_cluster_name`

**ECS_SERVICE_TILES**
- Description: Tiles service name
- Value: `tiles-service`
- How to get: This is the service name defined in your Terraform

**ECS_SERVICE_TIMESERIES**
- Description: Timeseries service name
- Value: `timeseries-service`
- How to get: This is the service name defined in your Terraform

**ECS_TASK_DEFINITION_TILES**
- Description: Tiles task definition family name
- Value: `tiles-service`
- How to get: This is the task definition family name (same as service name)

**ECS_TASK_DEFINITION_TIMESERIES**
- Description: Timeseries task definition family name
- Value: `timeseries-service`
- How to get: This is the task definition family name (same as service name)

### 4. Application URL

**ALB_URL**
- Description: Application Load Balancer URL for smoke tests
- Value: `http://cloud-sciraster-alb-1212121212.ap-southeast-2.elb.amazonaws.com`
- How to get: Run `terraform output alb_dns_name` and prepend `http://`
- Note: Use HTTP (not HTTPS) for testing without SSL certificates

**S3_RAW_BUCKET**
- Description: S3 raw data bucket name for enhanced testing
- Value: `cloud-scientific-raster-sharing-raw-2e6c448c`
- How to get: Run `terraform output s3_raw_bucket`

**STEP_FUNCTIONS_ARN**
- Description: Step Functions state machine ARN for enhanced testing
- Value: `arn:aws:states:ap-southeast-2:123456789101:stateMachine:cloud-scientific-raster-sharing-ingestion-pipeline`
- How to get: Run `terraform output ingestion_state_machine_arn`

**OPENSEARCH_ENDPOINT**
- Description: OpenSearch domain endpoint for enhanced testing
- Value: `vpc-cloud-sciraster-stac-aaaabbbbbcccccddddd1231231.ap-southeast-2.es.amazonaws.com`
- How to get: Run `terraform output opensearch_endpoint`

### 5. Optional Secrets

**CODECOV_TOKEN** (Optional)
- Description: Codecov token for coverage reporting
- Value: Your Codecov token
- How to get: From codecov.io after setting up your repository
- Note: If not set, coverage upload will be skipped

## Quick Setup Script

You can use this script to get all the values from Terraform:

```bash
cd terraform

echo "=== GitHub Secrets Configuration ==="
echo ""
echo "ECR_REPOSITORY:"
terraform output -json | jq -r '.ecr_repository_url.value' | cut -d'/' -f2
echo ""
echo "ECS_CLUSTER:"
terraform output -json | jq -r '.ecs_cluster_name.value'
echo ""
echo "ECS_SERVICE_TILES:"
echo "tiles-service"
echo ""
echo "ECS_SERVICE_TIMESERIES:"
echo "timeseries-service"
echo ""
echo "ECS_TASK_DEFINITION_TILES:"
echo "tiles-service"
echo ""
echo "ECS_TASK_DEFINITION_TIMESERIES:"
echo "timeseries-service"
echo ""
echo "ALB_URL:"
echo "http://$(terraform output -json | jq -r '.alb_dns_name.value')"
echo ""
echo "S3_RAW_BUCKET:"
terraform output -json | jq -r '.s3_raw_bucket.value // "cloud-scientific-raster-sharing-raw-2e6c448c"'
echo ""
echo "STEP_FUNCTIONS_ARN:"
terraform output -json | jq -r '.ingestion_state_machine_arn.value // "arn:aws:states:ap-southeast-2:123456789101:stateMachine:cloud-scientific-raster-sharing-ingestion-pipeline"'
echo ""
echo "OPENSEARCH_ENDPOINT:"
terraform output -json | jq -r '.opensearch_endpoint.value // "vpc-cloud-sciraster-stac-aaaabbbbbcccccddddd1231231.ap-southeast-2.es.amazonaws.com"'
echo ""
echo "=== AWS Credentials ==="
echo "AWS_ACCESS_KEY_ID: <from your AWS credentials>"
echo "AWS_SECRET_ACCESS_KEY: <from your AWS credentials>"
```

## Verification Checklist

After adding all secrets, verify:

- [ ] All 12 secrets are added (11 required + 1 optional)
- [ ] No typos in secret names (they're case-sensitive)
- [ ] No extra spaces in secret values
- [ ] AWS credentials have correct permissions
- [ ] ECS cluster name matches exactly
- [ ] Service names match exactly

## Testing the Configuration

1. Make a small change to your code
2. Commit and push to `main` branch
3. Go to **Actions** tab in GitHub
4. Watch the workflow run
5. Check each step for errors

## Common Issues

### "Cluster not found" Error

**Problem:** ECS cluster name doesn't match
**Solution:** 
- Run `terraform output ecs_cluster_name`
- Update `ECS_CLUSTER` secret with exact value
- Make sure there are no extra spaces

### "Service not found" Error

**Problem:** Service name doesn't match
**Solution:**
- Check service names in AWS ECS console
- Update `ECS_SERVICE_TILES` and `ECS_SERVICE_TIMESERIES` secrets
- Default values should be `tiles-service` and `timeseries-service`

### "Task definition not found" Error

**Problem:** Task definition family name doesn't match
**Solution:**
- Check task definition families in AWS ECS console
- Update `ECS_TASK_DEFINITION_TILES` and `ECS_TASK_DEFINITION_TIMESERIES` secrets
- Default values should be `tiles-service` and `timeseries-service`

### "Access Denied" Error

**Problem:** AWS credentials don't have sufficient permissions
**Solution:**
- Verify IAM user has these permissions:
  - `ecr:GetAuthorizationToken`
  - `ecr:BatchCheckLayerAvailability`
  - `ecr:GetDownloadUrlForLayer`
  - `ecr:BatchGetImage`
  - `ecr:PutImage`
  - `ecs:DescribeTaskDefinition`
  - `ecs:RegisterTaskDefinition`
  - `ecs:UpdateService`
  - `ecs:DescribeServices`
- Consider using a policy like `AmazonECS_FullAccess` and `AmazonEC2ContainerRegistryPowerUser`

### "Repository not found" Error

**Problem:** ECR repository name is incorrect
**Solution:**
- Run `terraform output ecr_repository_url`
- Extract only the repository name (part after `/`)
- Update `ECR_REPOSITORY` secret

## Security Best Practices

1. **Use IAM User with Limited Permissions**
   - Create a dedicated IAM user for CI/CD
   - Grant only necessary permissions
   - Rotate credentials regularly

2. **Never Commit Secrets**
   - Never put secrets in code or configuration files
   - Use `.gitignore` to exclude sensitive files
   - Use GitHub Secrets for all sensitive data

3. **Rotate Credentials Regularly**
   - Change AWS access keys every 90 days
   - Update GitHub secrets when credentials change

4. **Monitor Secret Usage**
   - Check GitHub Actions logs for unauthorized access
   - Review AWS CloudTrail for API calls

## IAM Policy for CI/CD User

Here's a minimal IAM policy for the CI/CD user:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecs:DescribeTaskDefinition",
        "ecs:RegisterTaskDefinition",
        "ecs:UpdateService",
        "ecs:DescribeServices"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "iam:PassRole"
      ],
      "Resource": [
        "arn:aws:iam::*:role/raster-app-prod-ecs-execution-role",
        "arn:aws:iam::*:role/raster-app-prod-ecs-task-role"
      ]
    }
  ]
}
```

## Next Steps

After configuring all secrets:

1. ✅ Verify all secrets are added correctly
2. ✅ Test the workflow by pushing a change
3. ✅ Monitor the deployment in GitHub Actions
4. ✅ Check ECS services are updated successfully
5. ✅ Run smoke tests to verify deployment

## Related Documentation

- `docs/GITHUB_OIDC_SETUP.md` - OIDC authentication setup (recommended)
- `docs/OPENSEARCH_ACCESS_FIX.md` - Fix OpenSearch access issues
- `docs/GITHUB_ACTIONS_SETUP.md` - Complete CI/CD setup guide
- `docs/DEPLOYMENT_GUIDE.md` - Manual deployment instructions
- `docs/GITHUB_ACTIONS_FIX.md` - Troubleshooting guide
