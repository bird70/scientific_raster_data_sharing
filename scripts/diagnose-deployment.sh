#!/bin/bash

# Deployment Diagnostics Script
set -e

echo "🔍 Diagnosing deployment issues..."
echo "=================================="

# Check AWS credentials
echo "1. AWS Credentials:"
aws sts get-caller-identity || { echo "❌ AWS credentials not configured"; exit 1; }

# Check ECS cluster
echo -e "\n2. ECS Cluster Status:"
aws ecs describe-clusters --clusters cloud-sciraster-ecs-cluster --query 'clusters[0].{Name:clusterName,Status:status,ActiveServices:activeServicesCount,RunningTasks:runningTasksCount}' --output table 2>/dev/null || echo "❌ ECS cluster not found"

# Check ECS services
echo -e "\n3. ECS Services:"
aws ecs list-services --cluster cloud-sciraster-ecs-cluster --output table 2>/dev/null || echo "❌ No services found"

# Check task definitions
echo -e "\n4. Task Definitions:"
echo "Tiles service task definition:"
aws ecs describe-task-definition --task-definition tiles-service 2>/dev/null | jq -r '.taskDefinition.{Family:family,Revision:revision,Status:status}' || echo "❌ tiles-service task definition missing"

echo "Timeseries service task definition:"
aws ecs describe-task-definition --task-definition timeseries-service 2>/dev/null | jq -r '.taskDefinition.{Family:family,Revision:revision,Status:status}' || echo "❌ timeseries-service task definition missing"

echo "Zarr conversion task definition:"
aws ecs describe-task-definition --task-definition zarr-conversion 2>/dev/null | jq -r '.taskDefinition.{Family:family,Revision:revision,Status:status}' || echo "❌ zarr-conversion task definition missing"

# Check ECR repositories
echo -e "\n5. ECR Repositories:"
aws ecr describe-repositories --query 'repositories[].{Name:repositoryName,URI:repositoryUri}' --output table 2>/dev/null || echo "❌ No ECR repositories found"

# Check ALB
echo -e "\n6. Application Load Balancer:"
aws elbv2 describe-load-balancers --names "cloud-sciraster-alb" --query 'LoadBalancers[0].{Name:LoadBalancerName,DNS:DNSName,State:State.Code}' --output table 2>/dev/null || echo "❌ ALB not found"

# Check target groups
echo -e "\n7. Target Groups:"
aws elbv2 describe-target-groups --query 'TargetGroups[?contains(LoadBalancerArns[0], `cloud-sciraster`)].{Name:TargetGroupName,Port:Port,Protocol:Protocol,HealthyTargets:HealthCheckPath}' --output table 2>/dev/null || echo "❌ No target groups found"

# Check security groups
echo -e "\n8. Security Groups:"
aws ec2 describe-security-groups --filters "Name=group-name,Values=*cloud-sciraster*" --query 'SecurityGroups[].{Name:GroupName,ID:GroupId,VPC:VpcId}' --output table 2>/dev/null || echo "❌ No security groups found"

# Check subnets
echo -e "\n9. VPC and Subnets:"
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=*cloud-sciraster*" --query 'Vpcs[].{Name:Tags[?Key==`Name`].Value|[0],VpcId:VpcId,State:State}' --output table 2>/dev/null || echo "❌ No VPC found"

echo -e "\n=================================="
echo "🏁 Diagnosis complete!"
echo ""
echo "Next steps:"
echo "1. If infrastructure is missing, run: terraform apply"
echo "2. If services are missing, check terraform/modules/ecs/"
echo "3. If task definitions are missing, they should be created by terraform"
echo "4. Check GitHub secrets match actual AWS resource names"