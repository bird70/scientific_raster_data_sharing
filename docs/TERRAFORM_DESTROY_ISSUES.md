# Terraform Destroy Issues & Solutions

## Issue 1: ECR Repository Not Empty

**Error**:
```
Error: ECR Repository (cloud-scientific-raster-sharing-repo) not empty, 
consider using force_delete: The repository still contains images
```

**Cause**: ECR repository has Docker images that must be deleted first.

**Solution 1 - Manual Cleanup (Quick)**:
```bash
# Delete all images from ECR
aws ecr batch-delete-image \
  --repository-name cloud-scientific-raster-sharing-repo \
  --image-ids "$(aws ecr list-images --repository-name cloud-scientific-raster-sharing-repo --query 'imageIds[*]' --output json)" \
  --region ap-southeast-2

# Then retry destroy
terraform destroy
```

**Solution 2 - Enable Force Delete (Permanent Fix)**:
Add to `terraform/modules/ecs/main.tf`:
```hcl
resource "aws_ecr_repository" "repo" {
  name                 = "${var.project_name}-repo"
  image_tag_mutability = "MUTABLE"
  force_delete         = true  # Add this line
  
  # ... rest of config
}
```

## Issue 2: Step Functions Deletion Timeout

**Error**:
```
Error: waiting for Step Functions State Machine delete: timeout while waiting 
for resource to be gone (last state: 'DELETING', timeout: 5m0s)
```

**Cause**: Step Functions has running executions that must complete/stop first.

**Solution 1 - Stop Running Executions**:
```bash
# List running executions
aws stepfunctions list-executions \
  --state-machine-arn "arn:aws:states:ap-southeast-2:123456789101:stateMachine:cloud-scientific-raster-sharing-ingestion-pipeline" \
  --status-filter RUNNING \
  --region ap-southeast-2

# Stop each running execution
aws stepfunctions stop-execution \
  --execution-arn <execution-arn-from-above> \
  --region ap-southeast-2

# Then retry destroy
terraform destroy
```

**Solution 2 - Wait and Retry**:
```bash
# Wait for executions to complete (if they're finishing soon)
sleep 60

# Retry destroy
terraform destroy
```

## Complete Cleanup Script

Save as `scripts/cleanup-before-destroy.sh`:
```bash
#!/bin/bash
set -e

REGION="ap-southeast-2"
REPO_NAME="cloud-scientific-raster-sharing-repo"
STATE_MACHINE_ARN="arn:aws:states:ap-southeast-2:123456789101:stateMachine:cloud-scientific-raster-sharing-ingestion-pipeline"

echo "=== Cleaning up resources before terraform destroy ==="

# 1. Delete ECR images
echo "Deleting ECR images..."
IMAGE_IDS=$(aws ecr list-images --repository-name $REPO_NAME --region $REGION --query 'imageIds[*]' --output json 2>/dev/null || echo "[]")
if [ "$IMAGE_IDS" != "[]" ]; then
  aws ecr batch-delete-image \
    --repository-name $REPO_NAME \
    --image-ids "$IMAGE_IDS" \
    --region $REGION
  echo "✓ ECR images deleted"
else
  echo "✓ No ECR images to delete"
fi

# 2. Stop Step Functions executions
echo "Stopping Step Functions executions..."
EXECUTIONS=$(aws stepfunctions list-executions \
  --state-machine-arn $STATE_MACHINE_ARN \
  --status-filter RUNNING \
  --region $REGION \
  --query 'executions[*].executionArn' \
  --output text 2>/dev/null || echo "")

if [ -n "$EXECUTIONS" ]; then
  for exec_arn in $EXECUTIONS; do
    aws stepfunctions stop-execution \
      --execution-arn $exec_arn \
      --region $REGION
    echo "✓ Stopped execution: $exec_arn"
  done
else
  echo "✓ No running executions to stop"
fi

echo "=== Cleanup complete! Now run: terraform destroy ==="
```

Make executable:
```bash
chmod +x scripts/cleanup-before-destroy.sh
```

## Quick Fix Commands

Run these now to fix your current situation:

```bash
# Fix ECR issue
aws ecr batch-delete-image \
  --repository-name cloud-scientific-raster-sharing-repo \
  --image-ids "$(aws ecr list-images --repository-name cloud-scientific-raster-sharing-repo --query 'imageIds[*]' --output json)" \
  --region ap-southeast-2

# Fix Step Functions issue (list executions first)
aws stepfunctions list-executions \
  --state-machine-arn "arn:aws:states:ap-southeast-2:123456789101:stateMachine:cloud-scientific-raster-sharing-ingestion-pipeline" \
  --status-filter RUNNING \
  --region ap-southeast-2

# If any running, stop them (replace <execution-arn>)
# aws stepfunctions stop-execution --execution-arn <execution-arn> --region ap-southeast-2

# Retry destroy
cd terraform
terraform destroy
```

## Permanent Fixes for Future

### 1. Update ECR Resource
File: `terraform/modules/ecs/main.tf`
```hcl
resource "aws_ecr_repository" "repo" {
  name                 = "${var.project_name}-repo"
  image_tag_mutability = "MUTABLE"
  force_delete         = true  # Allows deletion even with images
  
  image_scanning_configuration {
    scan_on_push = true
  }
  
  tags = var.tags
}
```

### 2. Add Lifecycle Rules to ECR
```hcl
resource "aws_ecr_lifecycle_policy" "repo" {
  repository = aws_ecr_repository.repo.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 5 images"
      selection = {
        tagStatus     = "any"
        countType     = "imageCountMoreThan"
        countNumber   = 5
      }
      action = {
        type = "expire"
      }
    }]
  })
}
```

## Prevention Strategy

Before running `terraform destroy`:
1. Stop all ECS services (prevents new tasks)
2. Stop Step Functions executions
3. Delete ECR images (or enable force_delete)
4. Wait for resources to stabilize
5. Run terraform destroy

## Alternative: Targeted Destroy

If full destroy keeps failing, destroy in stages:
```bash
# Destroy in reverse dependency order
terraform destroy -target=module.ingestion
terraform destroy -target=module.ecs
terraform destroy -target=module.data
terraform destroy -target=module.network
terraform destroy -target=module.iam
```
