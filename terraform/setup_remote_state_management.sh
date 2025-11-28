#!/bin/bash
# Set these variables as needed
BUCKET_NAME="cloud-scientific-raster-sharing-terraform-state-bucket"
DYNAMODB_TABLE="terraform-lock-table"
AWS_REGION="ap-southeast-2"

# Create S3 bucket
aws s3api create-bucket --bucket $BUCKET_NAME --region $AWS_REGION --create-bucket-configuration LocationConstraint=$AWS_REGION

# Enable versioning (recommended)
aws s3api put-bucket-versioning --bucket $BUCKET_NAME --versioning-configuration Status=Enabled

# there is a recent deprecation warning related to the use of DynamoDB for state locking in Terraform. 
# As of Terraform 1.6 and later, the dynamodb_table argument in the S3 backend is deprecated in favor of a new table block. 
# The new syntax improves configuration clarity and future extensibility.

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name $DYNAMODB_TABLE \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region $AWS_REGION

echo "S3 bucket and DynamoDB table created."
