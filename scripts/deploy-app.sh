#!/bin/bash

# Deploy updated application to ECS
# This script builds, pushes, and deploys the Docker image

set -e

echo "Starting deployment process..."

# Get AWS account ID and region
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION="ap-southeast-2"

# ECR repository name (adjust if different)
ECR_REPO_NAME="cloud-sciraster-app"
ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}"

echo "ECR Repository: ${ECR_URI}"

# Login to ECR
echo "Logging into ECR..."
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Build Docker image
echo "Building Docker image..."
cd app
docker build -t raster-app .

# Tag image for ECR
echo "Tagging image for ECR..."
docker tag raster-app:latest ${ECR_URI}:latest

# Push to ECR
echo "Pushing image to ECR..."
docker push ${ECR_URI}:latest

# Update ECS services
echo "Updating ECS services..."
aws ecs update-service \
    --cluster cloud-sciraster-ecs-cluster \
    --service tiles-service \
    --force-new-deployment \
    --region ${AWS_REGION}

aws ecs update-service \
    --cluster cloud-sciraster-ecs-cluster \
    --service timeseries-service \
    --force-new-deployment \
    --region ${AWS_REGION}

echo "Deployment initiated. Services are updating..."
echo "Check deployment status with:"
echo "aws ecs describe-services --cluster cloud-sciraster-ecs-cluster --services tiles-service timeseries-service"