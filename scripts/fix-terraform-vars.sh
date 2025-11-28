#!/bin/bash

# Fix Terraform variables with actual AWS values
set -e

echo "🔧 Updating Terraform variables with actual AWS values..."

cd terraform

# Get current AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION="ap-southeast-2"

echo "AWS Account ID: $AWS_ACCOUNT_ID"

# Check if ACM certificate exists
echo -e "\n1. Checking ACM certificates..."
ACM_CERT=$(aws acm list-certificates --region $AWS_REGION --query 'CertificateSummaryList[0].CertificateArn' --output text 2>/dev/null || echo "None")

if [ "$ACM_CERT" = "None" ]; then
    echo "⚠️ No ACM certificate found. Using placeholder."
    ACM_CERT="arn:aws:acm:${AWS_REGION}:${AWS_ACCOUNT_ID}:certificate/PLACEHOLDER"
else
    echo "✅ Found ACM certificate: $ACM_CERT"
fi

# Check if Cognito user pool exists
echo -e "\n2. Checking Cognito user pools..."
COGNITO_POOL=$(aws cognito-idp list-user-pools --max-items 10 --query 'UserPools[0].Id' --output text 2>/dev/null || echo "None")

if [ "$COGNITO_POOL" = "None" ]; then
    echo "⚠️ No Cognito user pool found. Using placeholder."
    COGNITO_POOL="${AWS_REGION}_PLACEHOLDER"
else
    echo "✅ Found Cognito user pool: $COGNITO_POOL"
fi

# Update terraform.tfvars
echo -e "\n3. Updating terraform.tfvars..."
cat > terraform.tfvars << EOF
project_name         = "cloud-scientific-raster-sharing"
short_name           = "cloud-sciraster"
aws_region           = "${AWS_REGION}"
alb_certificate_arn  = ""
domain_name          = ""
cognito_user_pool_id = "${COGNITO_POOL}"
enable_postgis       = false

# Tagging variables
service_owner = "theowner"
project_title = "cloud-scientific-raster-sharing"
environment   = "dev"

# Cost Optimization Settings
tiles_desired_count      = 1
timeseries_desired_count = 1
dask_workers_min         = 1
dask_workers_max         = 2

# Use smaller OpenSearch
opensearch_instance_count = 1
opensearch_instance_type  = "t3.small.search"

# Smaller Redis
redis_node_type = "cache.t3.micro"
EOF

echo "✅ terraform.tfvars updated"

# Show what will be created/updated
echo -e "\n4. Planning Terraform changes..."
terraform init -upgrade
terraform plan

echo -e "\n✅ Ready to deploy!"
echo ""
echo "Next steps:"
echo "1. Review the plan above"
echo "2. Run: terraform apply"
echo "3. This will create the missing ECS services properly"