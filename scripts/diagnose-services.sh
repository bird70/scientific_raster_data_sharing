#!/bin/bash
# Diagnose ECS service issues

set -e

echo "🔍 Diagnosing ECS Services"
echo "=========================="
echo ""

# Get cluster name
cd terraform
CLUSTER_NAME=$(terraform output -raw ecs_cluster_name 2>/dev/null)
cd ..

if [ -z "$CLUSTER_NAME" ]; then
    echo "❌ Error: Could not get ECS cluster name"
    exit 1
fi

echo "📊 Cluster: $CLUSTER_NAME"
echo ""

# Check service status
echo "1️⃣  Service Status:"
echo ""
aws ecs describe-services \
    --cluster $CLUSTER_NAME \
    --services tiles-service timeseries-service \
    --query 'services[*].[serviceName,status,runningCount,desiredCount,deployments[0].rolloutState]' \
    --output table

echo ""
echo "2️⃣  Recent Task Failures:"
echo ""

# Get stopped tasks (failures)
STOPPED_TASKS=$(aws ecs list-tasks \
    --cluster $CLUSTER_NAME \
    --desired-status STOPPED \
    --max-results 5 \
    --query 'taskArns[]' \
    --output text)

if [ -n "$STOPPED_TASKS" ]; then
    echo "Found stopped tasks. Checking reasons..."
    for TASK_ARN in $STOPPED_TASKS; do
        echo ""
        echo "Task: $(basename $TASK_ARN)"
        aws ecs describe-tasks \
            --cluster $CLUSTER_NAME \
            --tasks $TASK_ARN \
            --query 'tasks[0].[lastStatus,stoppedReason,containers[0].reason]' \
            --output table
    done
else
    echo "✅ No recently stopped tasks"
fi

echo ""
echo "3️⃣  Running Tasks:"
echo ""

RUNNING_TASKS=$(aws ecs list-tasks \
    --cluster $CLUSTER_NAME \
    --desired-status RUNNING \
    --query 'taskArns[]' \
    --output text)

if [ -n "$RUNNING_TASKS" ]; then
    for TASK_ARN in $RUNNING_TASKS; do
        echo "Task: $(basename $TASK_ARN)"
        aws ecs describe-tasks \
            --cluster $CLUSTER_NAME \
            --tasks $TASK_ARN \
            --query 'tasks[0].[group,lastStatus,healthStatus,containers[0].name,containers[0].lastStatus]' \
            --output table
        echo ""
    done
else
    echo "⚠️  No running tasks found!"
fi

echo ""
echo "4️⃣  Recent Logs (tiles-service):"
echo ""
aws logs tail /ecs/tiles-service --since 5m 2>/dev/null | head -30 || echo "No logs available yet"

echo ""
echo "5️⃣  Recent Logs (timeseries-service):"
echo ""
aws logs tail /ecs/timeseries-service --since 5m 2>/dev/null | head -30 || echo "No logs available yet"

echo ""
echo "6️⃣  Target Group Health:"
echo ""

# Get target group ARNs
TG_TILES=$(aws elbv2 describe-target-groups \
    --names raster-app-prod-tiles-tg \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text 2>/dev/null)

TG_TS=$(aws elbv2 describe-target-groups \
    --names raster-app-prod-ts-tg \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text 2>/dev/null)

if [ -n "$TG_TILES" ] && [ "$TG_TILES" != "None" ]; then
    echo "Tiles Target Group:"
    aws elbv2 describe-target-health \
        --target-group-arn $TG_TILES \
        --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State,TargetHealth.Reason]' \
        --output table
fi

if [ -n "$TG_TS" ] && [ "$TG_TS" != "None" ]; then
    echo ""
    echo "Timeseries Target Group:"
    aws elbv2 describe-target-health \
        --target-group-arn $TG_TS \
        --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State,TargetHealth.Reason]' \
        --output table
fi

echo ""
echo "💡 Common Issues:"
echo "  - Tasks failing to start: Check logs above for errors"
echo "  - Health checks failing: Verify /health endpoint works in container"
echo "  - No tasks running: Check task definition has valid image"
echo "  - Connection timeout: Check security groups allow ALB → ECS"
echo ""
echo "📝 To view full logs:"
echo "  aws logs tail /ecs/tiles-service --follow"
echo "  aws logs tail /ecs/timeseries-service --follow"
