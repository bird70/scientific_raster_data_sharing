#!/bin/bash
# Enhanced script to stop all costly services when not in use
# Provides options for different levels of cost savings

set -e

echo "🛑 Stopping AWS services to save costs..."
echo ""

# Get configuration from Terraform
cd terraform
CLUSTER_NAME=$(terraform output -raw ecs_cluster_name 2>/dev/null)
PROJECT_NAME=$(terraform output -raw project_name 2>/dev/null)
cd ..

if [ -z "$CLUSTER_NAME" ]; then
    echo "❌ Error: Could not get ECS cluster name from Terraform"
    exit 1
fi

echo "📊 Project: $PROJECT_NAME"
echo "📊 Cluster: $CLUSTER_NAME"
echo ""

# Function to stop ECS services
stop_ecs_services() {
    echo "🔴 Stopping ECS Services..."
    
    SERVICES=(
        "tiles-service"
        "timeseries-service"
        "dask-scheduler"
        "dask-workers"
    )
    
    for SERVICE in "${SERVICES[@]}"; do
        echo "  ⏸️  Stopping $SERVICE..."
        aws ecs update-service \
            --cluster $CLUSTER_NAME \
            --service $SERVICE \
            --desired-count 0 \
            --output text \
            --query 'service.[serviceName,desiredCount]' 2>/dev/null || echo "    ⚠️  Service $SERVICE not found or already stopped"
    done
    
    echo "  ✅ ECS services stopped"
    echo ""
}

# Function to check ingestion pipeline status
check_ingestion_pipeline() {
    echo "🔍 Checking Ingestion Pipeline Status..."
    echo ""
    echo "  ℹ️  ECS ingestion tasks (zarr-conversion, cog-generation):"
    echo "     - Event-driven, only run when files are uploaded"
    echo "     - Cost: ~\$0.01 per file processed"
    echo "     - No action needed - already cost-optimized"
    echo ""
    
    # Check for running ingestion tasks
    RUNNING_TASKS=$(aws ecs list-tasks \
        --cluster $CLUSTER_NAME \
        --query 'taskArns' \
        --output text 2>/dev/null | wc -w)
    
    if [ "$RUNNING_TASKS" -gt 0 ]; then
        echo "  ⚠️  Warning: $RUNNING_TASKS ECS tasks currently running"
        echo "     These may be ingestion tasks processing files"
        echo "     They will stop automatically when complete"
    else
        echo "  ✅ No ECS tasks currently running"
    fi
    echo ""
}

# Function to show OpenSearch status
show_opensearch_status() {
    echo "🔍 OpenSearch Status..."
    echo ""
    echo "  ℹ️  OpenSearch domain:"
    echo "     - Runs 24/7, costs ~\$50-100/month"
    echo "     - NOT stopped by this script (complex to stop/restart)"
    echo "     - To reduce costs: Use smaller instance type or delete domain"
    echo ""
    echo "  💡 To stop OpenSearch (advanced):"
    echo "     1. Create snapshot: aws opensearch create-domain-snapshot"
    echo "     2. Delete domain: terraform destroy -target=module.opensearch"
    echo "     3. Restore later from snapshot"
    echo ""
}

# Function to show Redis status
show_redis_status() {
    echo "🔍 Redis/ElastiCache Status..."
    echo ""
    echo "  ℹ️  Redis cluster:"
    echo "     - Runs 24/7, costs ~\$25/month"
    echo "     - NOT stopped by this script"
    echo "     - To reduce costs: Use smaller instance type"
    echo ""
}

# Main execution
echo "═══════════════════════════════════════════════════════════"
echo "  COST SAVINGS SUMMARY"
echo "═══════════════════════════════════════════════════════════"
echo ""

# Stop ECS services
stop_ecs_services

# Check ingestion pipeline
check_ingestion_pipeline

# Show OpenSearch status
show_opensearch_status

# Show Redis status
show_redis_status

# Show final status
echo "═══════════════════════════════════════════════════════════"
echo "  FINAL STATUS"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "✅ STOPPED (Saving ~\$120/month):"
echo "   - ECS Services (tiles, timeseries, dask)"
echo ""
echo "✅ ALREADY OPTIMIZED (No action needed):"
echo "   - ECS Ingestion Tasks (event-driven, ~\$0.01/file)"
echo "   - Lambda Functions (serverless, only cost when invoked)"
echo "   - Step Functions (only cost per execution)"
echo "   - S3 Storage (minimal cost, ~\$0.023/GB/month)"
echo ""
echo "⚠️  STILL RUNNING (Consider optimizing):"
echo "   - OpenSearch: ~\$50-100/month"
echo "   - Redis: ~\$25/month"
echo ""
echo "💰 Total Monthly Savings: ~\$120"
echo "💰 Remaining Monthly Cost: ~\$75-125 (OpenSearch + Redis + S3)"
echo ""
echo "📊 Current ECS service status:"
aws ecs describe-services \
    --cluster $CLUSTER_NAME \
    --services tiles-service timeseries-service dask-scheduler dask-workers \
    --query 'services[*].[serviceName,runningCount,desiredCount]' \
    --output table 2>/dev/null || echo "Could not fetch service status"

echo ""
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "To restart services: ./scripts/start-services.sh"
echo "To monitor ingestion: ./scripts/monitor-ingestion-pipeline.sh"
echo ""

