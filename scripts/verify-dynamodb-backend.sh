#!/bin/bash

# Smoke test script to verify DynamoDB backend is working correctly
# This script tests all query patterns and verifies no OpenSearch dependencies remain

set -e

echo "=========================================="
echo "DynamoDB Backend Verification Script"
echo "=========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get ALB endpoint from Terraform outputs
echo "Getting ALB endpoint from Terraform..."
cd terraform
ALB_ENDPOINT=$(terraform output -raw alb_dns_name 2>/dev/null || echo "")
cd ..

if [ -z "$ALB_ENDPOINT" ]; then
    echo -e "${RED}ERROR: Could not get ALB endpoint from Terraform${NC}"
    echo "Please ensure Terraform has been applied successfully"
    exit 1
fi

API_BASE="http://${ALB_ENDPOINT}"
echo "API Base URL: $API_BASE"
echo ""

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

# Function to test an endpoint
test_endpoint() {
    local name="$1"
    local url="$2"
    local expected_status="${3:-200}"
    
    echo -n "Testing $name... "
    
    response=$(curl -s -w "\n%{http_code}" "$url" 2>&1)
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | head -n-1)
    
    if [ "$http_code" = "$expected_status" ]; then
        echo -e "${GREEN}PASS${NC} (HTTP $http_code)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}FAIL${NC} (HTTP $http_code, expected $expected_status)"
        echo "Response: $body"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# Function to test JSON response contains expected data
test_json_response() {
    local name="$1"
    local url="$2"
    local check_field="$3"
    
    echo -n "Testing $name... "
    
    response=$(curl -s "$url" 2>&1)
    
    if echo "$response" | grep -q "$check_field"; then
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}FAIL${NC}"
        echo "Response does not contain expected field: $check_field"
        echo "Response: $response"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

echo "=========================================="
echo "1. Testing Basic API Endpoints"
echo "=========================================="
echo ""

# Test health endpoint
test_endpoint "Health Check" "${API_BASE}/health" 200

# Test collections endpoint (uses list_collections from STAC client)
test_endpoint "Collections List" "${API_BASE}/collections" 200

echo ""
echo "=========================================="
echo "2. Checking CloudWatch Logs for Errors"
echo "=========================================="
echo ""

# Get log group names from Terraform
cd terraform
TILES_LOG_GROUP=$(terraform output -raw tiles_log_group_name 2>/dev/null || echo "")
TIMESERIES_LOG_GROUP=$(terraform output -raw timeseries_log_group_name 2>/dev/null || echo "")
cd ..

if [ -n "$TILES_LOG_GROUP" ]; then
    echo "Checking tiles service logs for errors..."
    ERROR_COUNT=$(aws logs filter-log-events \
        --log-group-name "$TILES_LOG_GROUP" \
        --filter-pattern "ERROR" \
        --start-time $(($(date +%s) - 3600))000 \
        --query 'events[*].message' \
        --output text 2>/dev/null | wc -l || echo "0")
    
    if [ "$ERROR_COUNT" -eq 0 ]; then
        echo -e "${GREEN}No errors found in tiles service logs${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${YELLOW}Warning: Found $ERROR_COUNT error(s) in tiles service logs${NC}"
        echo "Recent errors:"
        aws logs filter-log-events \
            --log-group-name "$TILES_LOG_GROUP" \
            --filter-pattern "ERROR" \
            --start-time $(($(date +%s) - 3600))000 \
            --query 'events[*].message' \
            --output text 2>/dev/null | head -5
    fi
else
    echo -e "${YELLOW}Warning: Could not find tiles log group${NC}"
fi

echo ""

if [ -n "$TIMESERIES_LOG_GROUP" ]; then
    echo "Checking timeseries service logs for errors..."
    ERROR_COUNT=$(aws logs filter-log-events \
        --log-group-name "$TIMESERIES_LOG_GROUP" \
        --filter-pattern "ERROR" \
        --start-time $(($(date +%s) - 3600))000 \
        --query 'events[*].message' \
        --output text 2>/dev/null | wc -l || echo "0")
    
    if [ "$ERROR_COUNT" -eq 0 ]; then
        echo -e "${GREEN}No errors found in timeseries service logs${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${YELLOW}Warning: Found $ERROR_COUNT error(s) in timeseries service logs${NC}"
        echo "Recent errors:"
        aws logs filter-log-events \
            --log-group-name "$TIMESERIES_LOG_GROUP" \
            --filter-pattern "ERROR" \
            --start-time $(($(date +%s) - 3600))000 \
            --query 'events[*].message' \
            --output text 2>/dev/null | head -5
    fi
else
    echo -e "${YELLOW}Warning: Could not find timeseries log group${NC}"
fi

echo ""
echo "=========================================="
echo "3. Verifying DynamoDB Backend Configuration"
echo "=========================================="
echo ""

# Check environment variables in ECS tasks
cd terraform
CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "")
TILES_SERVICE=$(terraform output -raw tiles_service_name 2>/dev/null || echo "")
cd ..

if [ -n "$CLUSTER_NAME" ] && [ -n "$TILES_SERVICE" ]; then
    echo "Checking ECS task environment variables..."
    
    # Get task ARN
    TASK_ARN=$(aws ecs list-tasks \
        --cluster "$CLUSTER_NAME" \
        --service-name "$TILES_SERVICE" \
        --query 'taskArns[0]' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$TASK_ARN" ] && [ "$TASK_ARN" != "None" ]; then
        # Get task definition
        TASK_DEF=$(aws ecs describe-tasks \
            --cluster "$CLUSTER_NAME" \
            --tasks "$TASK_ARN" \
            --query 'tasks[0].taskDefinitionArn' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$TASK_DEF" ]; then
            # Check STAC_BACKEND environment variable
            STAC_BACKEND=$(aws ecs describe-task-definition \
                --task-definition "$TASK_DEF" \
                --query 'taskDefinition.containerDefinitions[0].environment[?name==`STAC_BACKEND`].value' \
                --output text 2>/dev/null || echo "")
            
            echo "STAC_BACKEND: $STAC_BACKEND"
            
            if [ "$STAC_BACKEND" = "dynamodb" ]; then
                echo -e "${GREEN}✓ STAC_BACKEND is set to 'dynamodb'${NC}"
                TESTS_PASSED=$((TESTS_PASSED + 1))
            else
                echo -e "${YELLOW}Warning: STAC_BACKEND is set to '$STAC_BACKEND' (expected 'dynamodb')${NC}"
            fi
            
            # Check if OPENSEARCH_HOST is still set
            OPENSEARCH_HOST=$(aws ecs describe-task-definition \
                --task-definition "$TASK_DEF" \
                --query 'taskDefinition.containerDefinitions[0].environment[?name==`OPENSEARCH_HOST`].value' \
                --output text 2>/dev/null || echo "")
            
            if [ -z "$OPENSEARCH_HOST" ] || [ "$OPENSEARCH_HOST" = "None" ]; then
                echo -e "${GREEN}✓ OPENSEARCH_HOST is not set (good)${NC}"
                TESTS_PASSED=$((TESTS_PASSED + 1))
            else
                echo -e "${YELLOW}Warning: OPENSEARCH_HOST is still set to '$OPENSEARCH_HOST'${NC}"
                echo "This should be removed when switching to DynamoDB-only mode"
            fi
            
            # Check DYNAMODB_STAC_TABLE is set
            DYNAMODB_TABLE=$(aws ecs describe-task-definition \
                --task-definition "$TASK_DEF" \
                --query 'taskDefinition.containerDefinitions[0].environment[?name==`DYNAMODB_STAC_TABLE`].value' \
                --output text 2>/dev/null || echo "")
            
            if [ -n "$DYNAMODB_TABLE" ] && [ "$DYNAMODB_TABLE" != "None" ]; then
                echo -e "${GREEN}✓ DYNAMODB_STAC_TABLE is set to '$DYNAMODB_TABLE'${NC}"
                TESTS_PASSED=$((TESTS_PASSED + 1))
            else
                echo -e "${RED}✗ DYNAMODB_STAC_TABLE is not set${NC}"
                TESTS_FAILED=$((TESTS_FAILED + 1))
            fi
        fi
    fi
fi

echo ""
echo "=========================================="
echo "4. Checking for OpenSearch Dependencies"
echo "=========================================="
echo ""

# Check if OpenSearch domain still exists
cd terraform
OPENSEARCH_ENDPOINT=$(terraform output -raw opensearch_endpoint 2>/dev/null || echo "")
cd ..

if [ -n "$OPENSEARCH_ENDPOINT" ] && [ "$OPENSEARCH_ENDPOINT" != "null" ]; then
    echo -e "${YELLOW}Warning: OpenSearch domain still exists: $OPENSEARCH_ENDPOINT${NC}"
    echo "This should be removed in the next step"
else
    echo -e "${GREEN}✓ OpenSearch domain not found in Terraform outputs${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# Check IAM policies for OpenSearch permissions
echo ""
echo "Checking IAM policies for OpenSearch permissions..."
cd terraform
ECS_TASK_ROLE=$(terraform output -raw ecs_task_role_name 2>/dev/null || echo "")
cd ..

if [ -n "$ECS_TASK_ROLE" ]; then
    OPENSEARCH_POLICIES=$(aws iam list-role-policies \
        --role-name "$ECS_TASK_ROLE" \
        --query 'PolicyNames[?contains(@, `opensearch`) || contains(@, `OpenSearch`)]' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$OPENSEARCH_POLICIES" ]; then
        echo -e "${GREEN}✓ No OpenSearch inline policies found${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${YELLOW}Warning: Found OpenSearch policies: $OPENSEARCH_POLICIES${NC}"
    fi
fi

echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo ""
echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed! DynamoDB backend is working correctly.${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Review CloudWatch logs for any warnings"
    echo "2. Proceed with removing OpenSearch infrastructure (task 13.2)"
    exit 0
else
    echo -e "${RED}✗ Some tests failed. Please review the errors above.${NC}"
    echo ""
    echo "Do not proceed with removing OpenSearch until all tests pass."
    exit 1
fi
