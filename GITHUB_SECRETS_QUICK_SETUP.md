# GitHub Secrets Quick Setup

## 🚀 Quick Start

Run this command to get all the values you need:

```bash
./scripts/get-github-secrets.sh
```

## 📋 Secrets to Add

Go to: **Settings > Secrets and variables > Actions > New repository secret**

Add these 9 secrets (copy values from the script output above):

| Secret Name | Value | Where to Get |
|------------|-------|--------------|
| `ECR_REPOSITORY` | `raster-app-prod-repo` | From script output |
| `ECS_CLUSTER` | `raster-app-prod-ecs-cluster` | From script output |
| `ECS_SERVICE_TILES` | `tiles-service` | From script output |
| `ECS_SERVICE_TIMESERIES` | `timeseries-service` | From script output |
| `ECS_TASK_DEFINITION_TILES` | `tiles-service` | From script output |
| `ECS_TASK_DEFINITION_TIMESERIES` | `timeseries-service` | From script output |
| `ALB_URL` | `http://raster-app-prod-alb-...` | From script output |
| `AWS_ACCESS_KEY_ID` | Your AWS access key | AWS IAM Console |
| `AWS_SECRET_ACCESS_KEY` | Your AWS secret key | AWS IAM Console |

## ✅ Verification

After adding all secrets:

1. Go to **Actions** tab
2. Click on the latest workflow run
3. Check if "Deploy to ECS" step succeeds
4. If it fails with "Cluster not found", double-check the secret values

## 🔧 Troubleshooting

**"Cluster not found" error?**
- Check `ECS_CLUSTER` secret matches exactly: `raster-app-prod-ecs-cluster`
- No extra spaces or typos

**"Service not found" error?**
- Check service names are exactly: `tiles-service` and `timeseries-service`

**"Access Denied" error?**
- Verify AWS credentials have ECS and ECR permissions
- See `docs/GITHUB_SECRETS_SETUP.md` for required IAM policy

## 📚 Detailed Documentation

For complete setup instructions and troubleshooting:
- `docs/GITHUB_SECRETS_SETUP.md` - Detailed setup guide
- `docs/GITHUB_ACTIONS_SETUP.md` - CI/CD pipeline guide
- `scripts/get-github-secrets.sh` - Script to get values
