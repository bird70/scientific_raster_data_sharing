#!/bin/bash

# Deploy with HTTP-only (no HTTPS certificate required)
set -e

echo "🔧 Deploying with HTTP-only configuration..."

cd terraform

# Update terraform.tfvars for HTTP-only
echo "1. Configuring for HTTP-only..."
cat > terraform.tfvars << EOF
project_name         = "cloud-scientific-raster-sharing"
short_name           = "cloud-sciraster"
aws_region           = "ap-southeast-2"
alb_certificate_arn  = ""
domain_name          = ""
cognito_user_pool_id = "ap-southeast-2_PLACEHOLDER"
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

echo "✅ Configured for HTTP-only deployment"

# Plan and apply
echo -e "\n2. Planning deployment..."
terraform init -upgrade
terraform plan

echo -e "\n3. Ready to apply!"
echo "This will create HTTP-only infrastructure (no HTTPS certificate needed)"
echo ""
echo "Run: terraform apply"
echo ""
echo "After deployment, test with:"
echo "curl http://cloud-sciraster-alb-1214303046.ap-southeast-2.elb.amazonaws.com/health"