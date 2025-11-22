#!/bin/bash
# Start all ECS services

set -e

echo "🚀 Starting ECS services..."
echo ""

# Get cluster name and desired counts from Terraform
cd terraform
CLUSTER_NAME=$(terraform output -raw ecs_cluster_name 2>/dev/null)

# Try to get desired counts from tfvars, default to 1 for cost optimization
TILES_COUNT=$(grep "tiles_desired_count" terraform.tfvars 2>/dev/null | awk '{print $3}' || echo "1")
TS_COUNT=$(grep "timeseries_desired_count" terraform.tfvars 2>/dev/null | awk '{print $3}' || echo "1")
DASK_WORKERS_MIN=$(grep "dask_workers_min" terraform.tfvars 2>/dev/null | awk '{print $3}' || echo "1")

cd ..

if [ -z "$CLUSTER_NAME" ]; then
    echo "❌ Error: Could not get ECS cluster name from Terraform"
    exit 1
fi

echo "📊 Cluster: $CLUSTER_NAME"
echo "📈 Starting with cost-optimized counts (1 task per service)"
echo ""

# Start services with appropriate counts
echo "Starting services..."

echo "  ▶️  Starting tiles-service (count: ${TILES_COUNT})..."
aws ecs update-service \
    --cluster $CLUSTER_NAME \
    --service tiles-service \
    --desired-count ${TILES_COUNT} \
    --output text \
    --query 'service.[serviceName,desiredCount]'

echo "  ▶️  Starting timeseries-service (count: ${TS_COUNT})..."
aws ecs update-service \
    --cluster $CLUSTER_NAME \
    --service timeseries-service \
    --desired-count ${TS_COUNT} \
    --output text \
    --query 'service.[serviceName,desiredCount]'

echo "  ▶️  Starting dask-scheduler (count: 1)..."
aws ecs update-service \
    --cluster $CLUSTER_NAME \
    --service dask-scheduler \
    --desired-count 1 \
    --output text \
    --query 'service.[serviceName,desiredCount]'

echo "  ▶️  Starting dask-workers (count: ${DASK_WORKERS_MIN})..."
aws ecs update-service \
    --cluster $CLUSTER_NAME \
    --service dask-workers \
    --desired-count ${DASK_WORKERS_MIN} \
    --output text \
    --query 'service.[serviceName,desiredCount]'

echo ""
echo "✅ All services starting!"
echo ""
echo "⏳ Services will take 2-3 minutes to start..."
echo ""
echo "📊 Monitor status:"
echo "  watch -n 10 'aws ecs describe-services --cluster $CLUSTER_NAME --services tiles-service timeseries-service --query \"services[*].[serviceName,runningCount,desiredCount]\" --output table'"
echo ""
echo "📝 View logs:"
echo "  aws logs tail /ecs/tiles-service --follow"
