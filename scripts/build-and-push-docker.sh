#!/bin/bash

# Build and Push Docker Image to ECR
# This script builds the Docker image with updated code and pushes it to ECR

set -e

# Configuration
export AWS_PROFILE=DEVcloud
export AWS_REGION=ap-southeast-2
ECR_REGISTRY="123456789101.dkr.ecr.ap-southeast-2.amazonaws.com"
IMAGE_NAME="cloud-scientific-raster-sharing-repo"
IMAGE_TAG="latest"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Docker Image Build and Push${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}Error: Docker is not running${NC}"
    echo "Please start Docker Desktop and try again"
    exit 1
fi

echo -e "${GREEN}✓ Docker is running${NC}"
echo ""

# Step 1: Login to ECR
echo -e "${YELLOW}Step 1: Logging in to ECR...${NC}"
aws ecr get-login-password --region $AWS_REGION --profile $AWS_PROFILE | \
    docker login --username AWS --password-stdin $ECR_REGISTRY

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully logged in to ECR${NC}"
else
    echo -e "${RED}✗ Failed to login to ECR${NC}"
    exit 1
fi
echo ""

# Step 2: Build Docker image
echo -e "${YELLOW}Step 2: Building Docker image...${NC}"
echo "This may take several minutes..."
echo ""

docker build -t $IMAGE_NAME:$IMAGE_TAG -f app/Dockerfile .

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ Successfully built Docker image${NC}"
else
    echo -e "${RED}✗ Failed to build Docker image${NC}"
    exit 1
fi
echo ""

# Step 3: Tag image
echo -e "${YELLOW}Step 3: Tagging image...${NC}"
docker tag $IMAGE_NAME:$IMAGE_TAG $ECR_REGISTRY/$IMAGE_NAME:$IMAGE_TAG

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully tagged image${NC}"
else
    echo -e "${RED}✗ Failed to tag image${NC}"
    exit 1
fi
echo ""

# Step 4: Push to ECR
echo -e "${YELLOW}Step 4: Pushing image to ECR...${NC}"
echo "This may take several minutes..."
echo ""

docker push $ECR_REGISTRY/$IMAGE_NAME:$IMAGE_TAG

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ Successfully pushed image to ECR${NC}"
else
    echo -e "${RED}✗ Failed to push image to ECR${NC}"
    exit 1
fi
echo ""

# Step 5: Get new image digest
echo -e "${YELLOW}Step 5: Verifying new image...${NC}"
NEW_DIGEST=$(aws ecr describe-images \
    --repository-name $IMAGE_NAME \
    --image-ids imageTag=$IMAGE_TAG \
    --region $AWS_REGION \
    --profile $AWS_PROFILE \
    --query 'imageDetails[0].imageDigest' \
    --output text)

echo "New image digest: $NEW_DIGEST"
echo ""

# Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Build and Push Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Image: $ECR_REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
echo "Digest: $NEW_DIGEST"
echo ""
echo "Next steps:"
echo "1. Wait 1-2 minutes for ECS to recognize the new image"
echo "2. Retry the pipeline by uploading a test file:"
echo "   aws s3 cp data/A2002070120230731_MC_SST_std_coastal_v05.nc \\"
echo "     s3://cloud-scientific-raster-sharing-raw-2e6c448c/ingestion/ \\"
echo "     --profile $AWS_PROFILE"
echo ""
