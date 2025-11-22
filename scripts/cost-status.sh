#!/bin/bash
# Show current infrastructure status and estimated costs

set -e

echo "💰 Infrastructure Cost Status"
echo "=============================="
echo ""

# Get cluster name
cd terraform
CLUSTER_NAME=$(terraform output -raw ecs_cluster_name 2>/dev/null)
cd ..

if [ -z "$CLUSTER_NAME" ]; then
    echo "❌ Error: Could not get ECS cluster name from Terraform"
    exit 1
fi

# Get service status
echo "📊 ECS Services Status:"
echo ""
aws ecs describe-services \
    --cluster $CLUSTER_NAME \
    --services tiles-service timeseries-service dask-scheduler dask-workers \
    --query 'services[*].[serviceName,runningCount,desiredCount]' \
    --output table 2>/dev/null || echo "Could not fetch service status"

echo ""
echo "💵 Estimated Monthly Costs:"
echo ""

# Calculate running costs
TILES_RUNNING=$(aws ecs describe-services --cluster $CLUSTER_NAME --services tiles-service --query 'services[0].runningCount' --output text 2>/dev/null || echo "0")
TS_RUNNING=$(aws ecs describe-services --cluster $CLUSTER_NAME --services timeseries-service --query 'services[0].runningCount' --output text 2>/dev/null || echo "0")
DASK_SCHED_RUNNING=$(aws ecs describe-services --cluster $CLUSTER_NAME --services dask-scheduler --query 'services[0].runningCount' --output text 2>/dev/null || echo "0")
DASK_WORKERS_RUNNING=$(aws ecs describe-services --cluster $CLUSTER_NAME --services dask-workers --query 'services[0].runningCount' --output text 2>/dev/null || echo "0")

# Cost per task per month (730 hours)
TILES_COST_PER_TASK=35
TS_COST_PER_TASK=50
DASK_SCHED_COST=15
DASK_WORKER_COST_PER_TASK=25

# Calculate ECS costs
ECS_COST=$((TILES_RUNNING * TILES_COST_PER_TASK + TS_RUNNING * TS_COST_PER_TASK + DASK_SCHED_RUNNING * DASK_SCHED_COST + DASK_WORKERS_RUNNING * DASK_WORKER_COST_PER_TASK))

# Fixed costs (always running)
OPENSEARCH_COST=50
REDIS_COST=25
ALB_COST=20
S3_COST=30
LAMBDA_COST=5
CLOUDWATCH_COST=10

FIXED_COST=$((OPENSEARCH_COST + REDIS_COST + ALB_COST + S3_COST + LAMBDA_COST + CLOUDWATCH_COST))
TOTAL_COST=$((ECS_COST + FIXED_COST))

echo "  ECS Fargate (variable):"
echo "    - Tiles service:      $TILES_RUNNING tasks × \$$TILES_COST_PER_TASK = \$$((TILES_RUNNING * TILES_COST_PER_TASK))/mo"
echo "    - Timeseries service: $TS_RUNNING tasks × \$$TS_COST_PER_TASK = \$$((TS_RUNNING * TS_COST_PER_TASK))/mo"
echo "    - Dask scheduler:     $DASK_SCHED_RUNNING tasks × \$$DASK_SCHED_COST = \$$((DASK_SCHED_RUNNING * DASK_SCHED_COST))/mo"
echo "    - Dask workers:       $DASK_WORKERS_RUNNING tasks × \$$DASK_WORKER_COST_PER_TASK = \$$((DASK_WORKERS_RUNNING * DASK_WORKER_COST_PER_TASK))/mo"
echo "    Subtotal: \$$ECS_COST/mo"
echo ""
echo "  Fixed costs (always running):"
echo "    - OpenSearch:  \$$OPENSEARCH_COST/mo"
echo "    - Redis:       \$$REDIS_COST/mo"
echo "    - ALB:         \$$ALB_COST/mo"
echo "    - S3:          \$$S3_COST/mo"
echo "    - Lambda:      \$$LAMBDA_COST/mo"
echo "    - CloudWatch:  \$$CLOUDWATCH_COST/mo"
echo "    Subtotal: \$$FIXED_COST/mo"
echo ""
echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  TOTAL ESTIMATED: \$$TOTAL_COST/month"
echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ "$ECS_COST" -eq 0 ]; then
    echo "✅ All ECS services stopped - saving ~\$120/month!"
    echo ""
    echo "To start services: ./scripts/start-services.sh"
else
    echo "💡 Cost Optimization Tips:"
    echo "  - Stop services when not needed: ./scripts/stop-services.sh (saves ~\$120/mo)"
    echo "  - Use cost-optimized config: terraform apply -var-file=terraform.tfvars.cost-optimized"
    echo "  - Set up auto-scheduling: ./scripts/schedule-services.sh (saves ~\$80/mo)"
fi

echo ""
echo "📊 For detailed cost analysis:"
echo "  cd terraform && infracost breakdown --path . --usage-file infracost-usage.yml"
