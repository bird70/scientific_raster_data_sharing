#!/bin/bash

# Script to extract GitHub Secrets values from Terraform outputs
# Run this from the project root directory

set -e

echo "=========================================="
echo "GitHub Secrets Configuration Values"
echo "=========================================="
echo ""
echo "Copy these values to your GitHub repository secrets:"
echo "Settings > Secrets and variables > Actions > New repository secret"
echo ""
echo "=========================================="
echo ""

cd terraform

echo "📦 ECR_REPOSITORY:"
ECR_REPO=$(terraform output -json | jq -r '.ecr_repository_url.value' | cut -d'/' -f2)
echo "   $ECR_REPO"
echo ""

echo "🖥️  ECS_CLUSTER:"
ECS_CLUSTER=$(terraform output -json | jq -r '.ecs_cluster_name.value')
echo "   $ECS_CLUSTER"
echo ""

echo "🎯 ECS_SERVICE_TILES:"
echo "   tiles-service"
echo ""

echo "📊 ECS_SERVICE_TIMESERIES:"
echo "   timeseries-service"
echo ""

echo "📋 ECS_TASK_DEFINITION_TILES:"
echo "   tiles-service"
echo ""

echo "📋 ECS_TASK_DEFINITION_TIMESERIES:"
echo "   timeseries-service"
echo ""

echo "🌐 ALB_URL:"
ALB_DNS=$(terraform output -json | jq -r '.alb_dns_name.value')
echo "   http://$ALB_DNS"
echo ""

echo "=========================================="
echo "AWS Credentials (from your AWS account):"
echo "=========================================="
echo ""
echo "🔑 AWS_ACCESS_KEY_ID:"
echo "   <Get from AWS IAM Console>"
echo ""
echo "🔐 AWS_SECRET_ACCESS_KEY:"
echo "   <Get from AWS IAM Console>"
echo ""

echo "=========================================="
echo "Optional:"
echo "=========================================="
echo ""
echo "📈 CODECOV_TOKEN (optional):"
echo "   <Get from codecov.io if you want coverage reports>"
echo ""

echo "=========================================="
echo "Quick Copy Format:"
echo "=========================================="
echo ""
echo "ECR_REPOSITORY=$ECR_REPO"
echo "ECS_CLUSTER=$ECS_CLUSTER"
echo "ECS_SERVICE_TILES=tiles-service"
echo "ECS_SERVICE_TIMESERIES=timeseries-service"
echo "ECS_TASK_DEFINITION_TILES=tiles-service"
echo "ECS_TASK_DEFINITION_TIMESERIES=timeseries-service"
echo "ALB_URL=http://$ALB_DNS"
echo "AWS_ACCESS_KEY_ID=<your-access-key>"
echo "AWS_SECRET_ACCESS_KEY=<your-secret-key>"
echo ""

echo "=========================================="
echo "Next Steps:"
echo "=========================================="
echo ""
echo "1. Go to: https://github.com/YOUR_USERNAME/YOUR_REPO/settings/secrets/actions"
echo "2. Click 'New repository secret' for each value above"
echo "3. Copy the exact values (no extra spaces)"
echo "4. See docs/GITHUB_SECRETS_SETUP.md for detailed instructions"
echo ""
