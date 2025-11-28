#!/bin/bash

# Proper Terraform-based deployment
set -e

echo "🏗️ Deploying infrastructure with Terraform..."

cd terraform

# Initialize Terraform
echo "1. Initializing Terraform..."
terraform init

# Plan the deployment
echo -e "\n2. Planning deployment..."
terraform plan -out=tfplan

# Apply the plan
echo -e "\n3. Applying Terraform plan..."
terraform apply tfplan

# Get outputs
echo -e "\n4. Getting deployment outputs..."
echo "ALB DNS Name:"
terraform output alb_dns_name 2>/dev/null || echo "Not available"

echo "ECS Cluster:"
terraform output ecs_cluster_name 2>/dev/null || echo "Not available"

echo "ECR Repository:"
terraform output ecr_repository_url 2>/dev/null || echo "Not available"

# Check ECS services
echo -e "\n5. Checking ECS services..."
CLUSTER_NAME=$(terraform output -raw ecs_cluster_name 2>/dev/null || echo "cloud-sciraster-ecs-cluster")

aws ecs describe-services --cluster $CLUSTER_NAME --services tiles-service timeseries-service --query 'services[].{Name:serviceName,Status:status,Running:runningCount,Desired:desiredCount}' --output table 2>/dev/null || echo "Services not found"

echo -e "\n✅ Terraform deployment complete!"
echo ""
echo "Next steps:"
echo "1. Wait for services to start: aws ecs wait services-stable --cluster $CLUSTER_NAME --services tiles-service timeseries-service"
echo "2. Test endpoints with the ALB URL above"
echo "3. Update GitHub secrets with correct resource names"