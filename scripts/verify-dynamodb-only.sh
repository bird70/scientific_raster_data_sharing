#!/bin/bash
# Verification script for DynamoDB-only STAC backend
# This script verifies that DynamoDB is working correctly and no OpenSearch dependencies remain

set -e

echo "========================================="
echo "DynamoDB STAC Backend Verification"
echo "========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get Terraform outputs
cd terraform
ALB_DNS=$(terraform output -raw alb_dns_name 2>/dev/null || echo "")
DYNAMODB_TABLE=$(terraform output -raw dynamodb_stac_table_name 2>/dev/null || echo "")
cd ..

if [ -z "$ALB_DNS" ]; then
    echo -e "${RED}✗ Failed to get ALB DNS name from Terraform${NC}"
    exit 1
fi

if [ -z "$DYNAMODB_TABLE" ]; then
    echo -e "${RED}✗ Failed to get DynamoDB table name from Terraform${NC}"
    exit 1
fi

echo "ALB DNS: $ALB_DNS"
echo "DynamoDB Table: $DYNAMODB_TABLE"
echo ""

# Check 1: Verify API health endpoint
echo "========================================="
echo "Check 1: API Health Endpoint"
echo "========================================="
HEALTH_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "http://$ALB_DNS/health" || echo "000")
if [ "$HEALTH_RESPONSE" = "200" ]; then
    echo -e "${GREEN}✓ API health endpoint responding (HTTP 200)${NC}"
else
    echo -e "${RED}✗ API health endpoint failed (HTTP $HEALTH_RESPONSE)${NC}"
    exit 1
fi
echo ""

# Check 2: Verify DynamoDB table exists and is active
echo "========================================="
echo "Check 2: DynamoDB Table Status"
echo "========================================="
TABLE_STATUS=$(aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --query 'Table.TableStatus' --output text 2>/dev/null || echo "NOT_FOUND")
if [ "$TABLE_STATUS" = "ACTIVE" ]; then
    echo -e "${GREEN}✓ DynamoDB table is ACTIVE${NC}"
    
    # Get item count
    ITEM_COUNT=$(aws dynamodb scan --table-name "$DYNAMODB_TABLE" --select COUNT --query 'Count' --output text 2>/dev/null || echo "0")
    echo "  Items in table: $ITEM_COUNT"
    
    # Check GSI status
    GSI_STATUS=$(aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --query 'Table.GlobalSecondaryIndexes[*].[IndexName,IndexStatus]' --output text 2>/dev/null || echo "")
    if [ -n "$GSI_STATUS" ]; then
        echo "  Global Secondary Indexes:"
        echo "$GSI_STATUS" | while read -r index_name index_status; do
            if [ "$index_status" = "ACTIVE" ]; then
                echo -e "    ${GREEN}✓ $index_name: $index_status${NC}"
            else
                echo -e "    ${RED}✗ $index_name: $index_status${NC}"
            fi
        done
    fi
else
    echo -e "${RED}✗ DynamoDB table status: $TABLE_STATUS${NC}"
    exit 1
fi
echo ""

# Check 3: Verify STAC backend configuration
echo "========================================="
echo "Check 3: STAC Backend Configuration"
echo "========================================="
cd terraform
STAC_BACKEND=$(terraform output -raw stac_backend 2>/dev/null || grep 'stac_backend' terraform.tfvars | cut -d'=' -f2 | tr -d ' "' || echo "unknown")
cd ..

echo "Current STAC_BACKEND: $STAC_BACKEND"
if [ "$STAC_BACKEND" = "dynamodb" ]; then
    echo -e "${GREEN}✓ STAC backend is set to 'dynamodb' (correct)${NC}"
elif [ "$STAC_BACKEND" = "dual" ]; then
    echo -e "${YELLOW}⚠ STAC backend is set to 'dual' (migration mode)${NC}"
    echo "  This is acceptable but should be changed to 'dynamodb' after verification"
else
    echo -e "${RED}✗ STAC backend is set to '$STAC_BACKEND' (unexpected)${NC}"
fi
echo ""

# Check 4: Check CloudWatch logs for errors
echo "========================================="
echo "Check 4: CloudWatch Logs (Recent Errors)"
echo "========================================="
echo "Checking ECS task logs for DynamoDB errors..."

# Check tiles service logs
TILES_LOG_GROUP="/ecs/tiles-service"
RECENT_ERRORS=$(aws logs filter-log-events \
    --log-group-name "$TILES_LOG_GROUP" \
    --start-time $(($(date +%s) - 3600))000 \
    --filter-pattern "ERROR" \
    --query 'events[*].message' \
    --output text 2>/dev/null | grep -i "dynamodb\|opensearch" || echo "")

if [ -z "$RECENT_ERRORS" ]; then
    echo -e "${GREEN}✓ No DynamoDB/OpenSearch errors in tiles service logs (last hour)${NC}"
else
    echo -e "${YELLOW}⚠ Found errors in tiles service logs:${NC}"
    echo "$RECENT_ERRORS" | head -5
fi

# Check timeseries service logs
TIMESERIES_LOG_GROUP="/ecs/timeseries-service"
RECENT_ERRORS=$(aws logs filter-log-events \
    --log-group-name "$TIMESERIES_LOG_GROUP" \
    --start-time $(($(date +%s) - 3600))000 \
    --filter-pattern "ERROR" \
    --query 'events[*].message' \
    --output text 2>/dev/null | grep -i "dynamodb\|opensearch" || echo "")

if [ -z "$RECENT_ERRORS" ]; then
    echo -e "${GREEN}✓ No DynamoDB/OpenSearch errors in timeseries service logs (last hour)${NC}"
else
    echo -e "${YELLOW}⚠ Found errors in timeseries service logs:${NC}"
    echo "$RECENT_ERRORS" | head -5
fi
echo ""

# Check 5: Test STAC item retrieval (if items exist)
echo "========================================="
echo "Check 5: STAC Item Retrieval Test"
echo "========================================="
if [ "$ITEM_COUNT" -gt 0 ]; then
    echo "Testing STAC item retrieval from DynamoDB..."
    
    # Get a sample item ID from DynamoDB
    SAMPLE_ID=$(aws dynamodb scan --table-name "$DYNAMODB_TABLE" --limit 1 --query 'Items[0].id.S' --output text 2>/dev/null || echo "")
    
    if [ -n "$SAMPLE_ID" ] && [ "$SAMPLE_ID" != "None" ]; then
        echo "Sample item ID: $SAMPLE_ID"
        
        # Try to retrieve via API (if STAC API endpoint exists)
        # Note: This assumes a STAC API endpoint exists - adjust as needed
        API_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "http://$ALB_DNS/api/stac/items/$SAMPLE_ID" 2>/dev/null || echo "000")
        
        if [ "$API_RESPONSE" = "200" ]; then
            echo -e "${GREEN}✓ Successfully retrieved STAC item via API${NC}"
        else
            echo -e "${YELLOW}⚠ Could not retrieve STAC item via API (HTTP $API_RESPONSE)${NC}"
            echo "  This may be expected if STAC API endpoint is not configured"
        fi
    else
        echo -e "${YELLOW}⚠ Could not get sample item ID from DynamoDB${NC}"
    fi
else
    echo -e "${YELLOW}⚠ No items in DynamoDB table - skipping retrieval test${NC}"
    echo "  Consider running ingestion pipeline to populate data"
fi
echo ""

# Check 6: Verify no OpenSearch environment variables in ECS tasks
echo "========================================="
echo "Check 6: OpenSearch Dependencies Check"
echo "========================================="
echo "Checking ECS task definitions for OpenSearch environment variables..."

cd terraform
CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "")
cd ..

if [ -n "$CLUSTER_NAME" ]; then
    # Get task definition ARNs
    TILES_TASK_DEF=$(aws ecs describe-services --cluster "$CLUSTER_NAME" --services tiles-service --query 'services[0].taskDefinition' --output text 2>/dev/null || echo "")
    
    if [ -n "$TILES_TASK_DEF" ]; then
        OPENSEARCH_ENV=$(aws ecs describe-task-definition --task-definition "$TILES_TASK_DEF" --query 'taskDefinition.containerDefinitions[0].environment[?name==`OPENSEARCH_HOST`]' --output text 2>/dev/null || echo "")
        
        if [ -z "$OPENSEARCH_ENV" ]; then
            echo -e "${GREEN}✓ No OPENSEARCH_HOST environment variable in tiles task definition${NC}"
        else
            echo -e "${YELLOW}⚠ OPENSEARCH_HOST environment variable still present in tiles task definition${NC}"
            echo "  This should be removed after switching to DynamoDB-only mode"
        fi
    fi
fi
echo ""

# Check 7: Verify DynamoDB metrics
echo "========================================="
echo "Check 7: DynamoDB Metrics (Last Hour)"
echo "========================================="
echo "Checking DynamoDB read/write activity..."

# Get read capacity units consumed
READ_CAPACITY=$(aws cloudwatch get-metric-statistics \
    --namespace AWS/DynamoDB \
    --metric-name ConsumedReadCapacityUnits \
    --dimensions Name=TableName,Value="$DYNAMODB_TABLE" \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 3600 \
    --statistics Sum \
    --query 'Datapoints[0].Sum' \
    --output text 2>/dev/null || echo "0")

# Get write capacity units consumed
WRITE_CAPACITY=$(aws cloudwatch get-metric-statistics \
    --namespace AWS/DynamoDB \
    --metric-name ConsumedWriteCapacityUnits \
    --dimensions Name=TableName,Value="$DYNAMODB_TABLE" \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 3600 \
    --statistics Sum \
    --query 'Datapoints[0].Sum' \
    --output text 2>/dev/null || echo "0")

if [ "$READ_CAPACITY" != "None" ] && [ "$READ_CAPACITY" != "0" ]; then
    echo -e "${GREEN}✓ DynamoDB read activity detected (${READ_CAPACITY} RCUs consumed)${NC}"
else
    echo -e "${YELLOW}⚠ No DynamoDB read activity in last hour${NC}"
fi

if [ "$WRITE_CAPACITY" != "None" ] && [ "$WRITE_CAPACITY" != "0" ]; then
    echo -e "${GREEN}✓ DynamoDB write activity detected (${WRITE_CAPACITY} WCUs consumed)${NC}"
else
    echo -e "${YELLOW}⚠ No DynamoDB write activity in last hour${NC}"
fi
echo ""

# Summary
echo "========================================="
echo "Verification Summary"
echo "========================================="
echo ""
echo "✓ = Passed"
echo "⚠ = Warning (review recommended)"
echo "✗ = Failed (action required)"
echo ""
echo "If all checks passed, you can proceed with:"
echo "1. Update STAC_BACKEND to 'dynamodb' in terraform.tfvars (if currently 'dual')"
echo "2. Run task 13.2 to remove OpenSearch from Terraform configuration"
echo "3. Run task 13.3 to apply Terraform changes and delete OpenSearch"
echo ""
echo "========================================="
