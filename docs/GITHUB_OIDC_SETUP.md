# GitHub Actions OIDC Setup for AWS

## Overview

This guide explains how to set up OpenID Connect (OIDC) authentication between GitHub Actions and AWS, eliminating the need for long-lived AWS access keys.

## Prerequisites

- AWS CLI configured with admin permissions
- GitHub repository with Actions enabled
- Existing GitHub OIDC provider in AWS (check with `aws iam list-open-id-connect-providers`)

## Step 1: Create GitHub Actions IAM Role

### Create Trust Policy
```bash
cat > trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
                },
                "StringLike": {
                    "token.actions.githubusercontent.com:sub": "repo:YOUR_ORG/YOUR_REPO:*"
                }
            }
        }
    ]
}
EOF
```

### Create the Role
```bash
aws iam create-role \
    --role-name GitHubActions-cloud-Role \
    --assume-role-policy-document file://trust-policy.json \
    --description "GitHub Actions role for data platform deployment"
```

### Attach Required Policies
```bash
aws iam attach-role-policy \
    --role-name GitHubActions-cloud-Role \
    --policy-arn arn:aws:iam::aws:policy/AmazonECS_FullAccess

aws iam attach-role-policy \
    --role-name GitHubActions-cloud-Role \
    --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser
```

## Step 2: Configure GitHub Secrets

Add this secret to your GitHub repository:

| Secret Name | Value |
|-------------|-------|
| `AWS_ROLE_ARN` | `arn:aws:iam::YOUR_ACCOUNT_ID:role/GitHubActions-cloud-Role` |

## Step 3: Update GitHub Actions Workflow

### Add Permissions
```yaml
jobs:
  deploy:
    permissions:
      id-token: write
      contents: read
```

### Update AWS Credentials Step
```yaml
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
    role-session-name: GitHubActions-${{ github.run_id }}
    aws-region: ${{ env.AWS_REGION }}
```

## Step 4: Remove Old Secrets

Delete these secrets from GitHub (no longer needed):
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

## Verification

1. Push a change to trigger the workflow
2. Check the "Configure AWS credentials" step shows "Assuming role with OIDC"
3. Verify subsequent AWS API calls succeed

## Troubleshooting

### "No OpenID Connect provider found"
```bash
# Check if OIDC provider exists
aws iam list-open-id-connect-providers

# If missing, create it (usually done by AWS admin)
aws iam create-open-id-connect-provider \
    --url https://token.actions.githubusercontent.com \
    --client-id-list sts.amazonaws.com \
    --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

### "Not authorized to perform sts:AssumeRoleWithWebIdentity"
- Check the trust policy repository name matches exactly
- Verify the OIDC provider ARN is correct
- Ensure the role exists and is assumable

### "Access Denied" on AWS API calls
- Check attached policies have required permissions
- Verify the role has ECS and ECR permissions

## Security Benefits

- ✅ No long-lived credentials stored in GitHub
- ✅ Automatic credential rotation
- ✅ Fine-grained permissions per repository
- ✅ Audit trail through AWS CloudTrail
- ✅ Works with GitHub Enterprise SSO

## Cleanup

```bash
# Remove trust policy file
rm trust-policy.json

# To delete role (if needed)
aws iam detach-role-policy --role-name GitHubActions-cloud-Role --policy-arn arn:aws:iam::aws:policy/AmazonECS_FullAccess
aws iam detach-role-policy --role-name GitHubActions-cloud-Role --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser
aws iam delete-role --role-name GitHubActions-cloud-Role
```