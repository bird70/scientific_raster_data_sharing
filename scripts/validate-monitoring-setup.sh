#!/bin/bash
# Validation Script for Task 10 Monitoring Setup
# This script validates that all monitoring infrastructure is properly configured

# Don't exit on errors - we want to check everything
set +e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

REGION="${AWS_REGION:-us-east-1}"
PROJECT_NAME="${PROJECT_NAME:-[YOURORG]}"

echo -e "${BLUE}=== Validating Monitoring Setup ===${NC}\n"

# Track validation results
PASSED=0
FAILED=0
WARNINGS=0

# Function to check and report
check_result() {
    local test_name=$1
    local result=$2
    local expected=$3
    
    if [ "$result" == "$expected" ]; then
        echo -e "${GREEN}✓${NC} $test_name"
        ((PASSED++))
        return 0
    else
        echo -e "${RED}✗${NC} $test_name"
        ((FAILED++))
        return 1
    fi
}

check_warning() {
    local test_name=$1
    local message=$2
    
    echo -e "${YELLOW}⚠${NC} $test_name: $message"
    ((WARNINGS++))
}

# 1. Check Terraform outputs
echo -e "${BLUE}1. Checking Terraform Outputs...${NC}"

# Try to find terraform directory
TERRAFORM_DIR=""
if [ -d "terraform" ]; then
    TERRAFORM_DIR="terraform"
elif [ -d "../terraform" ]; then
    TERRAFORM_DIR="../terraform"
fi

if [ -z "$TERRAFORM_DIR" ]; then
    check_warning "Terraform directory" "Not found - skipping terraform checks"
    STATE_MACHINE_ARN=""
    CLUSTER_NAME=""
else
    cd "$TERRAFORM_DIR" > /dev/null 2>&1
    
    STATE_MACHINE_ARN=$(terraform output -raw ingestion_state_machine_arn 2>/dev/null || echo "")
    CLUSTER_NAME=$(terraform output -raw ecs_cluster_name 2>/dev/null || echo "")
    
    if [ -n "$STATE_MACHINE_ARN" ]; then
        check_result "Step Functions ARN available" "pass" "pass"
    else
        check_warning "Step Functions ARN" "Not available - infrastructure may not be deployed yet"
    fi
    
    if [ -n "$CLUSTER_NAME" ]; then
        check_result "ECS Cluster name available" "pass" "pass"
    else
        check_warning "ECS Cluster name" "Not available - infrastructure may not be deployed yet"
    fi
    
    cd - > /dev/null 2>&1
fi

# 2. Check CloudWatch Alarms
echo -e "\n${BLUE}2. Checking CloudWatch Alarms...${NC}"

# Check if AWS CLI is available
if ! command -v aws &> /dev/null; then
    check_warning "AWS CLI" "Not found - skipping AWS resource checks"
    echo -e "${YELLOW}Install AWS CLI to check deployed resources${NC}"
else
    EXPECTED_ALARMS=(
        "${PROJECT_NAME}-ingestion-high-failure-rate"
        "${PROJECT_NAME}-ingestion-long-execution"
        "${PROJECT_NAME}-zarr-task-failure"
        "${PROJECT_NAME}-cog-task-failure"
        "${PROJECT_NAME}-zarr-high-memory"
        "${PROJECT_NAME}-cog-high-memory"
    )
    
    for alarm in "${EXPECTED_ALARMS[@]}"; do
        ALARM_EXISTS=$(aws cloudwatch describe-alarms \
            --alarm-names "$alarm" \
            --region "$REGION" \
            --query 'MetricAlarms[0].AlarmName' \
            --output text 2>/dev/null || echo "None")
        
        if [ "$ALARM_EXISTS" != "None" ] && [ -n "$ALARM_EXISTS" ]; then
            check_result "Alarm: $alarm" "pass" "pass"
        else
            check_warning "Alarm: $alarm" "Not deployed yet - will be created by terraform apply"
        fi
    done
fi

# 3. Check CloudWatch Dashboard
echo -e "\n${BLUE}3. Checking CloudWatch Dashboard...${NC}"

if command -v aws &> /dev/null; then
    DASHBOARD_EXISTS=$(aws cloudwatch list-dashboards \
        --dashboard-name-prefix "${PROJECT_NAME}-ingestion-pipeline" \
        --region "$REGION" \
        --query 'DashboardEntries[0].DashboardName' \
        --output text 2>/dev/null || echo "None")
    
    if [ "$DASHBOARD_EXISTS" != "None" ] && [ -n "$DASHBOARD_EXISTS" ]; then
        check_result "Dashboard: ${PROJECT_NAME}-ingestion-pipeline" "pass" "pass"
    else
        check_warning "Dashboard: ${PROJECT_NAME}-ingestion-pipeline" "Not deployed yet - will be created by terraform apply"
    fi
fi

# 4. Check SNS Topic
echo -e "\n${BLUE}4. Checking SNS Topic...${NC}"

if command -v aws &> /dev/null; then
    SNS_TOPIC=$(aws sns list-topics \
        --region "$REGION" \
        --query "Topics[?contains(TopicArn, '${PROJECT_NAME}-alarms')].TopicArn" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$SNS_TOPIC" ]; then
        check_result "SNS Topic exists" "pass" "pass"
        
        # Check subscriptions
        SUBSCRIPTIONS=$(aws sns list-subscriptions-by-topic \
            --topic-arn "$SNS_TOPIC" \
            --region "$REGION" \
            --query 'Subscriptions[*].SubscriptionArn' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$SUBSCRIPTIONS" ]; then
            check_result "SNS Subscriptions configured" "pass" "pass"
        else
            check_warning "SNS Subscriptions" "No subscriptions found - configure alarm_email in terraform.tfvars"
        fi
    else
        check_warning "SNS Topic" "Not deployed yet - will be created by terraform apply"
    fi
fi

# 5. Check CloudWatch Log Groups
echo -e "\n${BLUE}5. Checking CloudWatch Log Groups...${NC}"

if command -v aws &> /dev/null; then
    EXPECTED_LOG_GROUPS=(
        "/ecs/zarr-conversion"
        "/ecs/cog-generation"
    )
    
    for log_group in "${EXPECTED_LOG_GROUPS[@]}"; do
        LOG_EXISTS=$(aws logs describe-log-groups \
            --log-group-name-prefix "$log_group" \
            --region "$REGION" \
            --query 'logGroups[0].logGroupName' \
            --output text 2>/dev/null || echo "None")
        
        if [ "$LOG_EXISTS" != "None" ] && [ -n "$LOG_EXISTS" ]; then
            check_result "Log Group: $log_group" "pass" "pass"
        else
            check_warning "Log Group: $log_group" "Will be created automatically on first ECS task execution"
        fi
    done
fi

# 6. Check Monitoring Scripts
echo -e "\n${BLUE}6. Checking Monitoring Scripts...${NC}"

if [ -f "scripts/monitor-ingestion-pipeline.sh" ]; then
    check_result "Bash monitoring script exists" "pass" "pass"
    
    if [ -x "scripts/monitor-ingestion-pipeline.sh" ]; then
        check_result "Bash script is executable" "pass" "pass"
    else
        check_warning "Bash script" "Not executable - run: chmod +x scripts/monitor-ingestion-pipeline.sh"
    fi
else
    check_result "Bash monitoring script exists" "fail" "pass"
fi

if [ -f "scripts/monitor-ingestion-pipeline.ps1" ]; then
    check_result "PowerShell monitoring script exists" "pass" "pass"
else
    check_result "PowerShell monitoring script exists" "fail" "pass"
fi

# 7. Check Documentation
echo -e "\n${BLUE}7. Checking Documentation...${NC}"

EXPECTED_DOCS=(
    "docs/INGESTION_PIPELINE_MONITORING.md"
    "docs/TASK_10_DEPLOYMENT_CHECKLIST.md"
    "docs/MONITORING_QUICK_REFERENCE.md"
)

for doc in "${EXPECTED_DOCS[@]}"; do
    if [ -f "$doc" ]; then
        check_result "Documentation: $doc" "pass" "pass"
    else
        check_result "Documentation: $doc" "fail" "pass"
    fi
done

# 8. Check Terraform Configuration
echo -e "\n${BLUE}8. Checking Terraform Configuration...${NC}"

if [ -n "$TERRAFORM_DIR" ] && command -v terraform &> /dev/null; then
    cd "$TERRAFORM_DIR" > /dev/null 2>&1
    
    TERRAFORM_VALID=$(terraform validate 2>&1 | grep -c "Success" || echo "0")
    
    if [ "$TERRAFORM_VALID" -gt 0 ]; then
        check_result "Terraform configuration valid" "pass" "pass"
    else
        check_warning "Terraform configuration" "Validation failed - check terraform validate output"
    fi
    
    cd - > /dev/null 2>&1
elif [ -z "$TERRAFORM_DIR" ]; then
    check_warning "Terraform configuration" "Terraform directory not found"
else
    check_warning "Terraform configuration" "Terraform CLI not installed"
fi

# 9. Check ECS Task Definitions
echo -e "\n${BLUE}9. Checking ECS Task Definitions...${NC}"

if command -v aws &> /dev/null; then
    EXPECTED_TASKS=(
        "zarr-conversion"
        "cog-generation"
    )
    
    for task in "${EXPECTED_TASKS[@]}"; do
        TASK_EXISTS=$(aws ecs list-task-definitions \
            --family-prefix "$task" \
            --region "$REGION" \
            --query 'taskDefinitionArns[0]' \
            --output text 2>/dev/null || echo "None")
        
        if [ "$TASK_EXISTS" != "None" ] && [ -n "$TASK_EXISTS" ]; then
            check_result "Task Definition: $task" "pass" "pass"
        else
            check_warning "Task Definition: $task" "Will be created by terraform apply"
        fi
    done
fi

# 10. Check Step Functions State Machine
echo -e "\n${BLUE}10. Checking Step Functions State Machine...${NC}"

if command -v aws &> /dev/null && [ -n "$STATE_MACHINE_ARN" ]; then
    STATE_MACHINE_STATUS=$(aws stepfunctions describe-state-machine \
        --state-machine-arn "$STATE_MACHINE_ARN" \
        --region "$REGION" \
        --query 'status' \
        --output text 2>/dev/null || echo "None")
    
    if [ "$STATE_MACHINE_STATUS" == "ACTIVE" ]; then
        check_result "State Machine status" "pass" "pass"
    else
        check_warning "State Machine status" "Status: $STATE_MACHINE_STATUS"
    fi
elif [ -z "$STATE_MACHINE_ARN" ]; then
    check_warning "State Machine" "Not deployed yet - will be created by terraform apply"
fi

# Summary
echo -e "\n${BLUE}=== Validation Summary ===${NC}"
echo -e "Passed:   ${GREEN}$PASSED${NC}"
echo -e "Failed:   ${RED}$FAILED${NC}"
echo -e "Warnings: ${YELLOW}$WARNINGS${NC}"

if [ $FAILED -eq 0 ]; then
    echo -e "\n${GREEN}✓ All critical checks passed!${NC}"
    echo -e "\nNext steps:"
    echo -e "1. Review any warnings above"
    echo -e "2. Deploy infrastructure: cd terraform && terraform apply"
    echo -e "3. Confirm SNS subscription (check email)"
    echo -e "4. Start monitoring: ./scripts/monitor-ingestion-pipeline.sh"
    echo -e "5. Follow deployment checklist: docs/TASK_10_DEPLOYMENT_CHECKLIST.md"
    exit 0
else
    echo -e "\n${RED}✗ Some checks failed. Please review the errors above.${NC}"
    echo -e "\nCommon fixes:"
    echo -e "1. Run: cd terraform && terraform apply"
    echo -e "2. Ensure AWS credentials are configured"
    echo -e "3. Check AWS region is correct: export AWS_REGION=us-east-1"
    exit 1
fi
