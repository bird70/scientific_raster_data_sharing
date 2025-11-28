#!/bin/bash
# Quick fix for ECR push issue

set -e

echo "🔧 Fixing ECR push issue..."
echo ""

# Get the correct ECR repository URL
cd terraform
ECR_REPO=$(terraform output -raw ecr_repository_url)
AWS_REGION="ap-southeast-2"
cd ..

echo "✅ Correct ECR Repository: $ECR_REPO"
echo ""

# Check if the image exists locally
if docker images | grep -q "raster-app"; then
    echo "✅ Found local raster-app image"
    
    # Re-tag with correct repository
    echo "🏷️  Re-tagging image with correct repository..."
    docker tag raster-app:latest $ECR_REPO:latest
    
    # Login to ECR
    echo "🔐 Logging in to ECR..."
    aws ecr get-login-password --region $AWS_REGION | \
        docker login --username AWS --password-stdin $ECR_REPO
    
    # Push
    echo "⬆️  Pushing to ECR..."
    docker push $ECR_REPO:latest
    
    echo ""
    echo "✅ Successfully pushed! Your image is now in ECR."
else
    echo "❌ No local raster-app image found."
    echo "Run: cd app && docker build -t raster-app:latest ."
    exit 1
fi
