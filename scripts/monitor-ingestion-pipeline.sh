#!/bin/bash
# Monitor Ingestion Pipeline Script
# This script provides quick access to key metrics and logs for the ECS-based ingestion pipeline

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REGION="${AWS_REGION:-us-east-1}"
PROJECT_NAME="${PROJECT_NAME:-[YOURORG]}"

# Get Terraform outputs
echo -e "${BLUE}Fetching infrastructure details...${NC}"
cd terraform 2>/dev/null || cd ../terraform 2>/dev/null || { echo "Error: terraform directory not found"; exit 1; }

STATE_MACHINE_ARN=$(terraform output -raw ingestion_state_machine_arn 2>/dev/null || echo "")
CLUSTER_NAME=$(terraform output -raw ecs_cluster_name 2>/dev/null || echo "")

if [ -z "$STATE_MACHINE_ARN" ]; then
    echo -e "${RED}Error: Could not get Step Functions ARN from Terraform${NC}"
    exit 1
fi

cd - > /dev/null

# Function to display menu
show_menu() {
    echo ""
    echo -e "${GREEN}=== Ingestion Pipeline Monitoring ===${NC}"
    echo "1. Show recent Step Functions executions"
    echo "2. Show execution success rate (last 24 hours)"
    echo "3. Show average execution time (last 24 hours)"
    echo "4. Show ECS task metrics (Zarr conversion)"
    echo "5. Show ECS task metrics (COG generation)"
    echo "6. Show recent errors from logs"
    echo "7. Show cost estimation (last 30 days)"
    echo "8. Show CloudWatch alarms status"
    echo "9. Open CloudWatch dashboard (browser)"
    echo "10. Tail Zarr conversion logs"
    echo "11. Tail COG generation logs"
    echo "0. Exit"
    echo ""
}

# Function to get recent executions
show_recent_executions() {
    echo -e "${BLUE}Recent Step Functions Executions:${NC}"
    aws stepfunctions list-executions \
        --state-machine-arn "$STATE_MACHINE_ARN" \
        --max-results 10 \
        --region "$REGION" \
        --query 'executions[*].[name,status,startDate,stopDate]' \
        --output table
}

# Function to calculate success rate
show_success_rate() {
    echo -e "${BLUE}Calculating success rate (last 24 hours)...${NC}"
    
    START_TIME=$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S)
    END_TIME=$(date -u +%Y-%m-%dT%H:%M:%S)
    
    SUCCEEDED=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/States \
        --metric-name ExecutionsSucceeded \
        --dimensions Name=StateMachineArn,Value="$STATE_MACHINE_ARN" \
        --start-time "$START_TIME" \
        --end-time "$END_TIME" \
        --period 86400 \
        --statistics Sum \
        --region "$REGION" \
        --query 'Datapoints[0].Sum' \
        --output text)
    
    FAILED=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/States \
        --metric-name ExecutionsFailed \
        --dimensions Name=StateMachineArn,Value="$STATE_MACHINE_ARN" \
        --start-time "$START_TIME" \
        --end-time "$END_TIME" \
        --period 86400 \
        --statistics Sum \
        --region "$REGION" \
        --query 'Datapoints[0].Sum' \
        --output text)
    
    SUCCEEDED=${SUCCEEDED:-0}
    FAILED=${FAILED:-0}
    TOTAL=$((SUCCEEDED + FAILED))
    
    if [ "$TOTAL" -gt 0 ]; then
        SUCCESS_RATE=$(echo "scale=2; ($SUCCEEDED / $TOTAL) * 100" | bc)
        echo -e "Succeeded: ${GREEN}$SUCCEEDED${NC}"
        echo -e "Failed: ${RED}$FAILED${NC}"
        echo -e "Total: $TOTAL"
        echo -e "Success Rate: ${GREEN}${SUCCESS_RATE}%${NC}"
        
        if (( $(echo "$SUCCESS_RATE < 95" | bc -l) )); then
            echo -e "${YELLOW}⚠ Warning: Success rate below 95% target${NC}"
        fi
    else
        echo "No executions in the last 24 hours"
    fi
}

# Function to show average execution time
show_execution_time() {
    echo -e "${BLUE}Calculating average execution time (last 24 hours)...${NC}"
    
    START_TIME=$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S)
    END_TIME=$(date -u +%Y-%m-%dT%H:%M:%S)
    
    AVG_TIME=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/States \
        --metric-name ExecutionTime \
        --dimensions Name=StateMachineArn,Value="$STATE_MACHINE_ARN" \
        --start-time "$START_TIME" \
        --end-time "$END_TIME" \
        --period 86400 \
        --statistics Average \
        --region "$REGION" \
        --query 'Datapoints[0].Average' \
        --output text)
    
    MAX_TIME=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/States \
        --metric-name ExecutionTime \
        --dimensions Name=StateMachineArn,Value="$STATE_MACHINE_ARN" \
        --start-time "$START_TIME" \
        --end-time "$END_TIME" \
        --period 86400 \
        --statistics Maximum \
        --region "$REGION" \
        --query 'Datapoints[0].Maximum' \
        --output text)
    
    if [ "$AVG_TIME" != "None" ] && [ -n "$AVG_TIME" ]; then
        AVG_MINUTES=$(echo "scale=2; $AVG_TIME / 60000" | bc)
        MAX_MINUTES=$(echo "scale=2; $MAX_TIME / 60000" | bc)
        
        echo -e "Average: ${GREEN}${AVG_MINUTES} minutes${NC}"
        echo -e "Maximum: ${YELLOW}${MAX_MINUTES} minutes${NC}"
        
        if (( $(echo "$AVG_MINUTES > 20" | bc -l) )); then
            echo -e "${YELLOW}⚠ Warning: Average execution time exceeds 20 minute target${NC}"
        fi
    else
        echo "No execution data available"
    fi
}

# Function to show ECS task metrics
show_ecs_metrics() {
    TASK_FAMILY=$1
    TASK_NAME=$2
    
    echo -e "${BLUE}ECS Task Metrics for $TASK_NAME (last 1 hour):${NC}"
    
    START_TIME=$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S)
    END_TIME=$(date -u +%Y-%m-%dT%H:%M:%S)
    
    CPU=$(aws cloudwatch get-metric-statistics \
        --namespace ECS/ContainerInsights \
        --metric-name CpuUtilization \
        --dimensions Name=ClusterName,Value="$CLUSTER_NAME" Name=TaskDefinitionFamily,Value="$TASK_FAMILY" \
        --start-time "$START_TIME" \
        --end-time "$END_TIME" \
        --period 3600 \
        --statistics Average \
        --region "$REGION" \
        --query 'Datapoints[0].Average' \
        --output text)
    
    MEMORY=$(aws cloudwatch get-metric-statistics \
        --namespace ECS/ContainerInsights \
        --metric-name MemoryUtilization \
        --dimensions Name=ClusterName,Value="$CLUSTER_NAME" Name=TaskDefinitionFamily,Value="$TASK_FAMILY" \
        --start-time "$START_TIME" \
        --end-time "$END_TIME" \
        --period 3600 \
        --statistics Average \
        --region "$REGION" \
        --query 'Datapoints[0].Average' \
        --output text)
    
    FAILED=$(aws cloudwatch get-metric-statistics \
        --namespace ECS/ContainerInsights \
        --metric-name TasksFailed \
        --dimensions Name=ClusterName,Value="$CLUSTER_NAME" Name=TaskDefinitionFamily,Value="$TASK_FAMILY" \
        --start-time "$START_TIME" \
        --end-time "$END_TIME" \
        --period 3600 \
        --statistics Sum \
        --region "$REGION" \
        --query 'Datapoints[0].Sum' \
        --output text)
    
    if [ "$CPU" != "None" ] && [ -n "$CPU" ]; then
        CPU_ROUNDED=$(printf "%.1f" "$CPU")
        MEMORY_ROUNDED=$(printf "%.1f" "$MEMORY")
        FAILED=${FAILED:-0}
        
        echo -e "CPU Utilization: ${GREEN}${CPU_ROUNDED}%${NC}"
        echo -e "Memory Utilization: ${GREEN}${MEMORY_ROUNDED}%${NC}"
        echo -e "Failed Tasks: ${RED}${FAILED}${NC}"
        
        if (( $(echo "$MEMORY > 90" | bc -l) )); then
            echo -e "${RED}⚠ Critical: Memory utilization above 90%${NC}"
        elif (( $(echo "$MEMORY > 80" | bc -l) )); then
            echo -e "${YELLOW}⚠ Warning: Memory utilization above 80%${NC}"
        fi
    else
        echo "No task data available (tasks may not have run recently)"
    fi
}

# Function to show recent errors
show_recent_errors() {
    echo -e "${BLUE}Recent errors from Zarr conversion logs:${NC}"
    aws logs filter-log-events \
        --log-group-name /ecs/zarr-conversion \
        --filter-pattern "ERROR" \
        --start-time $(($(date +%s) - 3600))000 \
        --region "$REGION" \
        --query 'events[*].[timestamp,message]' \
        --output text 2>/dev/null | head -10 || echo "No errors found or log group doesn't exist"
    
    echo ""
    echo -e "${BLUE}Recent errors from COG generation logs:${NC}"
    aws logs filter-log-events \
        --log-group-name /ecs/cog-generation \
        --filter-pattern "ERROR" \
        --start-time $(($(date +%s) - 3600))000 \
        --region "$REGION" \
        --query 'events[*].[timestamp,message]' \
        --output text 2>/dev/null | head -10 || echo "No errors found or log group doesn't exist"
}

# Function to estimate costs
show_cost_estimation() {
    echo -e "${BLUE}Cost estimation (last 30 days):${NC}"
    
    START_TIME=$(date -u -d '30 days ago' +%Y-%m-%dT%H:%M:%S)
    END_TIME=$(date -u +%Y-%m-%dT%H:%M:%S)
    
    TOTAL_EXEC_TIME=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/States \
        --metric-name ExecutionTime \
        --dimensions Name=StateMachineArn,Value="$STATE_MACHINE_ARN" \
        --start-time "$START_TIME" \
        --end-time "$END_TIME" \
        --period 2592000 \
        --statistics Sum \
        --region "$REGION" \
        --query 'Datapoints[0].Sum' \
        --output text)
    
    if [ "$TOTAL_EXEC_TIME" != "None" ] && [ -n "$TOTAL_EXEC_TIME" ]; then
        # Convert milliseconds to hours
        TOTAL_HOURS=$(echo "scale=4; $TOTAL_EXEC_TIME / 3600000" | bc)
        
        # ECS Fargate pricing: $0.04048/hour for 0.5 vCPU + 2GB
        COST_PER_HOUR=0.04048
        TOTAL_COST=$(echo "scale=2; $TOTAL_HOURS * $COST_PER_HOUR" | bc)
        
        # Calculate number of executions
        EXECUTIONS=$(aws cloudwatch get-metric-statistics \
            --namespace AWS/States \
            --metric-name ExecutionsSucceeded \
            --dimensions Name=StateMachineArn,Value="$STATE_MACHINE_ARN" \
            --start-time "$START_TIME" \
            --end-time "$END_TIME" \
            --period 2592000 \
            --statistics Sum \
            --region "$REGION" \
            --query 'Datapoints[0].Sum' \
            --output text)
        
        EXECUTIONS=${EXECUTIONS:-0}
        
        if [ "$EXECUTIONS" -gt 0 ]; then
            COST_PER_FILE=$(echo "scale=4; $TOTAL_COST / $EXECUTIONS" | bc)
            echo -e "Total execution time: ${GREEN}${TOTAL_HOURS} hours${NC}"
            echo -e "Estimated ECS cost: ${GREEN}\$${TOTAL_COST}${NC}"
            echo -e "Number of files processed: ${GREEN}${EXECUTIONS}${NC}"
            echo -e "Cost per file: ${GREEN}\$${COST_PER_FILE}${NC}"
            echo ""
            echo -e "${YELLOW}Note: This is an estimate based on execution time.${NC}"
            echo -e "${YELLOW}Check AWS Cost Explorer for actual costs including Step Functions, S3, etc.${NC}"
        else
            echo "No successful executions in the last 30 days"
        fi
    else
        echo "No execution data available"
    fi
}

# Function to show alarm status
show_alarm_status() {
    echo -e "${BLUE}CloudWatch Alarms Status:${NC}"
    aws cloudwatch describe-alarms \
        --alarm-name-prefix "$PROJECT_NAME-ingestion" \
        --region "$REGION" \
        --query 'MetricAlarms[*].[AlarmName,StateValue,StateReason]' \
        --output table
}

# Function to open dashboard
open_dashboard() {
    DASHBOARD_URL="https://${REGION}.console.aws.amazon.com/cloudwatch/home?region=${REGION}#dashboards:name=${PROJECT_NAME}-ingestion-pipeline"
    echo -e "${BLUE}Opening CloudWatch dashboard in browser...${NC}"
    echo "URL: $DASHBOARD_URL"
    
    # Try to open in browser (works on macOS, Linux with xdg-open, Windows with WSL)
    if command -v open &> /dev/null; then
        open "$DASHBOARD_URL"
    elif command -v xdg-open &> /dev/null; then
        xdg-open "$DASHBOARD_URL"
    elif command -v start &> /dev/null; then
        start "$DASHBOARD_URL"
    else
        echo "Please open the URL manually in your browser"
    fi
}

# Function to tail logs
tail_logs() {
    LOG_GROUP=$1
    echo -e "${BLUE}Tailing logs from $LOG_GROUP (Ctrl+C to stop)...${NC}"
    aws logs tail "$LOG_GROUP" --follow --format short --region "$REGION"
}

# Main loop
while true; do
    show_menu
    read -p "Select an option: " choice
    
    case $choice in
        1) show_recent_executions ;;
        2) show_success_rate ;;
        3) show_execution_time ;;
        4) show_ecs_metrics "zarr-conversion" "Zarr Conversion" ;;
        5) show_ecs_metrics "cog-generation" "COG Generation" ;;
        6) show_recent_errors ;;
        7) show_cost_estimation ;;
        8) show_alarm_status ;;
        9) open_dashboard ;;
        10) tail_logs "/ecs/zarr-conversion" ;;
        11) tail_logs "/ecs/cog-generation" ;;
        0) echo "Exiting..."; exit 0 ;;
        *) echo -e "${RED}Invalid option${NC}" ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
done
