#!/bin/bash
# Build frontend with dynamic API URL from Terraform

set -e

echo "Building frontend with Terraform-provided API URL..."

# Get ALB DNS name from Terraform
cd ../terraform
ALB_DNS=$(terraform output -raw alb_dns_name)

if [ -z "$ALB_DNS" ]; then
    echo "Error: Could not get ALB DNS name from Terraform"
    exit 1
fi

echo "Using API URL: http://$ALB_DNS"

# Build frontend with dynamic API URL
cd ../frontend
VITE_API_BASE_URL="http://$ALB_DNS" npm run build

echo "Frontend built successfully with API URL: http://$ALB_DNS"