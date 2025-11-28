#!/bin/bash
set -e

ACCOUNT_ID=123456789101
REGION=ap-southeast-2
REPO_NAME=cloud-scientific-raster-sharing-repo

# Login to ECR
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

# Build and push Lambda image
cd ../app/lambda
docker buildx build --platform linux/amd64 --provenance=false --load \
  -t $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:lambda .
docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:lambda

# Get image digest
IMAGE_DIGEST=$(aws ecr describe-images --repository-name $REPO_NAME --image-ids imageTag=lambda --query 'imageDetails[0].imageDigest' --output text)

echo "Image pushed with digest: $IMAGE_DIGEST"

# Update terraform.tfvars with new digest
cd ../../terraform
if grep -q "lambda_image_digest" terraform.tfvars 2>/dev/null; then
  sed -i "s|lambda_image_digest.*|lambda_image_digest = \"$IMAGE_DIGEST\"|" terraform.tfvars
else
  echo "lambda_image_digest = \"$IMAGE_DIGEST\"" >> terraform.tfvars
fi

# Update Lambda function
terraform apply -target=module.lambda_ingestion.aws_lambda_function.zarr_converter -auto-approve

echo "Lambda function updated successfully"
