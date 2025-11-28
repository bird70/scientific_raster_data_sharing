#!/bin/bash

# Fix Missing ECS Resources
set -e

echo "🔧 Creating missing ECS resources..."

AWS_REGION="ap-southeast-2"
CLUSTER_NAME="cloud-sciraster-ecs-cluster"

# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Check if cluster exists, create if missing
echo "1. Checking ECS cluster..."
if ! aws ecs describe-clusters --clusters $CLUSTER_NAME --query 'clusters[0].clusterName' --output text 2>/dev/null | grep -q $CLUSTER_NAME; then
    echo "Creating ECS cluster: $CLUSTER_NAME"
    aws ecs create-cluster --cluster-name $CLUSTER_NAME
else
    echo "✅ ECS cluster exists"
fi

# Create zarr-conversion task definition if missing
echo -e "\n2. Creating zarr-conversion task definition..."
cat > zarr-conversion-task-def.json << EOF
{
    "family": "zarr-conversion",
    "networkMode": "awsvpc",
    "requiresCompatibilities": ["FARGATE"],
    "cpu": "1024",
    "memory": "2048",
    "executionRoleArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/ecsTaskExecutionRole",
    "taskRoleArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/cloud-sciraster-task-role",
    "containerDefinitions": [
        {
            "name": "zarr-conversion",
            "image": "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/cloud-scientific-raster-sharing-repo:latest",
            "essential": true,
            "logConfiguration": {
                "logDriver": "awslogs",
                "options": {
                    "awslogs-group": "/ecs/zarr-conversion",
                    "awslogs-region": "${AWS_REGION}",
                    "awslogs-stream-prefix": "ecs"
                }
            },
            "environment": [
                {"name": "AWS_DEFAULT_REGION", "value": "${AWS_REGION}"},
                {"name": "TASK_TYPE", "value": "zarr-conversion"}
            ]
        }
    ]
}
EOF

aws ecs register-task-definition --cli-input-json file://zarr-conversion-task-def.json
echo "✅ zarr-conversion task definition created"

# Create CloudWatch log groups if missing
echo -e "\n3. Creating CloudWatch log groups..."
for service in tiles-service timeseries-service zarr-conversion; do
    if ! aws logs describe-log-groups --log-group-name-prefix "/ecs/$service" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "/ecs/$service"; then
        echo "Creating log group: /ecs/$service"
        aws logs create-log-group --log-group-name "/ecs/$service"
    else
        echo "✅ Log group /ecs/$service exists"
    fi
done

# Check if services exist and are healthy
echo -e "\n4. Checking ECS services..."
for service in tiles-service timeseries-service; do
    if aws ecs describe-services --cluster $CLUSTER_NAME --services $service --query 'services[0].serviceName' --output text 2>/dev/null | grep -q $service; then
        echo "✅ Service $service exists"
        
        # Check service health
        RUNNING_COUNT=$(aws ecs describe-services --cluster $CLUSTER_NAME --services $service --query 'services[0].runningCount' --output text)
        DESIRED_COUNT=$(aws ecs describe-services --cluster $CLUSTER_NAME --services $service --query 'services[0].desiredCount' --output text)
        
        echo "  Running: $RUNNING_COUNT, Desired: $DESIRED_COUNT"
        
        if [ "$RUNNING_COUNT" != "$DESIRED_COUNT" ]; then
            echo "  ⚠️ Service $service is not healthy - forcing new deployment"
            aws ecs update-service --cluster $CLUSTER_NAME --service $service --force-new-deployment
        fi
    else
        echo "❌ Service $service missing - check terraform configuration"
    fi
done

# Clean up temp files
rm -f zarr-conversion-task-def.json

echo -e "\n✅ Resource creation complete!"
echo ""
echo "Next steps:"
echo "1. Wait for services to stabilize: aws ecs wait services-stable --cluster $CLUSTER_NAME --services tiles-service timeseries-service"
echo "2. Test endpoints manually"
echo "3. Re-run GitHub Actions workflow"