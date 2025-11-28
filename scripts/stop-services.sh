#!/bin/bash
# Stop all ECS services to save costs when not in use
# This stops compute costs but keeps data (S3, OpenSearch, Redis)

set -e

echo "🛑 Stopping ECS services to save costs..."
echo ""

# Get cluster name from Terraform
cd terraform
CLUSTER_NAME=$(terraform output -raw ecs_cluster_name 2>/dev/null)
cd ..

if [ -z "$CLUSTER_NAME" ]; then
    echo "❌ Error: Could not get ECS cluster name from Terraform"
    exit 1
fi

echo "📊 Cluster: $CLUSTER_NAME"
echo ""

# List of services to stop
SERVICES=(
    "tiles-service"
    "timeseries-service"
    "dask-scheduler"
    "dask-workers"
)

echo "Stopping services..."
for SERVICE in "${SERVICES[@]}"; do
    echo "  ⏸️  Stopping $SERVICE..."
    aws ecs update-service \
        --cluster $CLUSTER_NAME \
        --service $SERVICE \
        --desired-count 0 \
        --output text \
        --query 'service.[serviceName,desiredCount]' 2>/dev/null || echo "    ⚠️  Service $SERVICE not found or already stopped"
done

echo ""
echo "✅ All services stopped!"
echo ""
echo "💰 Cost Savings:"
echo "  - ECS Fargate: ~$120/month saved"
echo "  - Still running: OpenSearch (~$50/mo), Redis (~$25/mo), S3 (storage only)"
echo ""
echo "📊 Current status:"
aws ecs describe-services \
    --cluster $CLUSTER_NAME \
    --services tiles-service timeseries-service dask-scheduler dask-workers \
    --query 'services[*].[serviceName,runningCount,desiredCount]' \
    --output table 2>/dev/null || echo "Could not fetch service status"

echo ""
echo "To restart services, run: ./scripts/start-services.sh"
