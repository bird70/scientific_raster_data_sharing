#!/bin/bash
# Build and push Docker image to ECR

set -e

echo "🐳 Building and pushing Docker image to ECR..."
echo ""

# Get ECR repository URL from Terraform
cd terraform
ECR_REPO=$(terraform output -raw ecr_repository_url)
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "ap-southeast-2")
cd ..

if [ -z "$ECR_REPO" ]; then
    echo "❌ Error: Could not get ECR repository URL from Terraform"
    echo "Make sure you've run 'terraform apply' successfully"
    exit 1
fi

echo "📦 ECR Repository: $ECR_REPO"
echo "🌏 AWS Region: $AWS_REGION"
echo ""

# Login to ECR
echo "🔐 Logging in to ECR..."
aws ecr get-login-password --region $AWS_REGION | \
    docker login --username AWS --password-stdin $ECR_REPO

echo ""
echo "🏗️  Building Docker image..."
cd app
docker build -t raster-app:latest .

echo ""
echo "🏷️  Tagging image..."
docker tag raster-app:latest $ECR_REPO:latest

echo ""
echo "⬆️  Pushing to ECR..."
docker push $ECR_REPO:latest

echo ""
echo "✅ Successfully pushed image to ECR!"
echo ""
echo "🚀 ECS will automatically pull and deploy the new image."
echo ""
echo "Monitor deployment:"
echo "  aws ecs describe-services --cluster \$(cd ../terraform && terraform output -raw ecs_cluster_name) --services tiles-service timeseries-service"
echo ""
echo "Check logs:"
echo "  aws logs tail /ecs/tiles-service --follow"
