# GitHub Actions Setup Guide

## Overview

This project uses GitHub Actions for CI/CD. The pipeline includes testing, building, security scanning, documentation generation, and deployment.

## Required Secrets

Configure these secrets in your GitHub repository settings (`Settings > Secrets and variables > Actions`).

**Quick Setup:**
1. Run `./scripts/get-github-secrets.sh` to get all values
2. See `docs/GITHUB_SECRETS_SETUP.md` for detailed instructions
3. See `GITHUB_SECRETS_QUICK_SETUP.md` for a quick reference

### Required Secrets (9 total)

- `AWS_ACCESS_KEY_ID` - AWS access key for deployment
- `AWS_SECRET_ACCESS_KEY` - AWS secret key for deployment
- `ECR_REPOSITORY` - ECR repository name (e.g., `raster-app-prod-repo`)
- `ECS_CLUSTER` - ECS cluster name (e.g., `raster-app-prod-ecs-cluster`)
- `ECS_SERVICE_TILES` - Tiles service name (e.g., `tiles-service`)
- `ECS_SERVICE_TIMESERIES` - Timeseries service name (e.g., `timeseries-service`)
- `ECS_TASK_DEFINITION_TILES` - Tiles task definition family (e.g., `tiles-service`)
- `ECS_TASK_DEFINITION_TIMESERIES` - Timeseries task definition family (e.g., `timeseries-service`)
- `ALB_URL` - Application Load Balancer URL for smoke tests (e.g., `http://your-alb-url.amazonaws.com`)

### Optional Secrets

- `CODECOV_TOKEN` - Codecov token for coverage reporting (optional)

## Repository Permissions

### Workflow Permissions

The workflow needs write permissions to commit documentation changes. Configure this in:

**Settings > Actions > General > Workflow permissions**

Choose one of:
1. **Read and write permissions** (Recommended)
2. **Read repository contents and packages permissions** + manually grant write access

### Alternative: Use Personal Access Token

If you prefer not to use the default `GITHUB_TOKEN`, you can create a Personal Access Token (PAT):

1. Go to **Settings > Developer settings > Personal access tokens > Tokens (classic)**
2. Generate new token with `repo` scope
3. Add it as a secret named `PAT_TOKEN`
4. Update the workflow to use it:

```yaml
- name: Checkout code
  uses: actions/checkout@v4
  with:
    token: ${{ secrets.PAT_TOKEN }}
```

## Workflow Jobs

### 1. Test Job
- Runs Python tests with pytest
- Generates coverage report
- Uploads to Codecov (optional)

### 2. Build Job
- Builds Docker image
- Pushes to Amazon ECR
- Only runs on `main` branch

### 3. Terraform Documentation and Security Job
- Generates Terraform module documentation
- Runs Checkov security scan
- Only blocks on CRITICAL severity issues
- Commits documentation changes (if permissions allow)

### 4. Deploy Job
- Updates ECS task definitions
- Deploys to ECS services
- Waits for deployment stabilization
- Only runs on `main` branch

### 5. Smoke Tests Job
- Tests health endpoint
- Tests tiles endpoint
- Tests timeseries endpoint
- Tests metrics endpoint
- Only runs on `main` branch

## Troubleshooting

### Permission Denied on Git Push

**Error:**
```
remote: Permission to user/repo.git denied to github-actions[bot].
fatal: unable to access 'https://github.com/user/repo/': The requested URL returned error: 403
```

**Solutions:**

1. **Enable workflow write permissions** (Recommended):
   - Go to **Settings > Actions > General**
   - Under "Workflow permissions", select "Read and write permissions"
   - Click "Save"

2. **Use a Personal Access Token**:
   - Create a PAT with `repo` scope
   - Add as secret `PAT_TOKEN`
   - Update checkout step to use it

3. **Disable documentation auto-commit**:
   - Remove or comment out the "Commit and push documentation changes" step
   - Generate documentation manually when needed

### Checkov Blocking Deployment

If Checkov is blocking deployment on non-critical issues:

1. Check the severity in the workflow output
2. Review `terraform/.checkov.yml` to skip specific checks
3. See `docs/SECURITY_SCANNING.md` for details

### ECS Deployment Failures

If ECS deployment fails:

1. Check that all secrets are configured correctly
2. Verify ECR repository exists and image was pushed
3. Check ECS service and task definition names match secrets
4. Review CloudWatch logs for the ECS tasks

### Smoke Tests Failing

If smoke tests fail:

1. Verify `ALB_URL` secret is set correctly
2. Check that the ALB is publicly accessible
3. Ensure ECS services are running and healthy
4. Review application logs in CloudWatch

## Workflow Customization

### Skip Documentation Commits

To disable automatic documentation commits, add this condition:

```yaml
- name: Commit and push documentation changes
  if: false  # Disabled
```

### Change Security Scan Threshold

To block on HIGH severity issues (not just CRITICAL):

Edit the "Check for critical security issues" step:

```bash
TOTAL_CRITICAL=$(($CRITICAL_COUNT + $HIGH_COUNT))
if [ "$TOTAL_CRITICAL" -gt 0 ]; then
  exit 1
fi
```

### Add Additional Smoke Tests

Add new steps to the `smoke-tests` job:

```yaml
- name: Test new endpoint
  run: |
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" ${{ secrets.ALB_URL }}/new-endpoint)
    if [ "$RESPONSE" != "200" ]; then
      echo "❌ Test failed"
      exit 1
    fi
    echo "✅ Test passed"
```

## Best Practices

1. **Use branch protection rules** - Require status checks to pass before merging
2. **Review security scan results** - Even if they don't block deployment
3. **Monitor deployment logs** - Check CloudWatch for issues
4. **Test locally first** - Run tests and builds locally before pushing
5. **Keep secrets secure** - Never commit secrets to the repository
6. **Use environment-specific secrets** - Consider separate secrets for staging/production

## Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [AWS ECS Deployment](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/deployment-types.html)
- [Checkov Security Scanning](https://www.checkov.io/)
- [Terraform Documentation](https://www.terraform.io/docs/)
