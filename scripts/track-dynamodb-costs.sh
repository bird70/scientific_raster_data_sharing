#!/bin/bash

# Track DynamoDB costs and usage for STAC table
# This script helps monitor the cost savings from the OpenSearch to DynamoDB migration

set -e

# Configuration
TABLE_NAME="cloud-scientific-raster-sharing-stac-items"
REGION="ap-southeast-2"
PROFILE="DEVcloud"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}DynamoDB Cost Tracking for STAC Table${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Function to get metric statistics
get_metric() {
    local metric_name=$1
    local stat=$2
    local start_date=$3
    local end_date=$4
    
    aws cloudwatch get-metric-statistics \
        --namespace AWS/DynamoDB \
        --metric-name "$metric_name" \
        --dimensions Name=TableName,Value="$TABLE_NAME" \
        --start-time "$start_date" \
        --end-time "$end_date" \
        --period 86400 \
        --statistics "$stat" \
        --region "$REGION" \
        --profile "$PROFILE" \
        --query 'Datapoints[*].'"$stat" \
        --output text 2>/dev/null || echo "0"
}

# Get date range (last 30 days)
END_DATE=$(date -u +"%Y-%m-%dT%H:%M:%S")
START_DATE=$(date -u -d "30 days ago" +"%Y-%m-%dT%H:%M:%S" 2>/dev/null || date -u -v-30d +"%Y-%m-%dT%H:%M:%S")

echo -e "${GREEN}Date Range:${NC} $START_DATE to $END_DATE"
echo ""

# Get table information
echo -e "${YELLOW}Table Information:${NC}"
TABLE_INFO=$(aws dynamodb describe-table \
    --table-name "$TABLE_NAME" \
    --region "$REGION" \
    --profile "$PROFILE" \
    2>/dev/null)

if [ $? -eq 0 ]; then
    ITEM_COUNT=$(echo "$TABLE_INFO" | grep -o '"ItemCount": [0-9]*' | grep -o '[0-9]*')
    TABLE_SIZE=$(echo "$TABLE_INFO" | grep -o '"TableSizeBytes": [0-9]*' | grep -o '[0-9]*')
    TABLE_SIZE_MB=$(echo "scale=2; $TABLE_SIZE / 1024 / 1024" | bc 2>/dev/null || echo "0")
    
    echo -e "  Table Name: ${GREEN}$TABLE_NAME${NC}"
    echo -e "  Item Count: ${GREEN}$ITEM_COUNT${NC}"
    echo -e "  Table Size: ${GREEN}${TABLE_SIZE_MB} MB${NC}"
else
    echo -e "  ${RED}Error: Could not retrieve table information${NC}"
fi
echo ""

# Get CloudWatch metrics
echo -e "${YELLOW}Usage Metrics (Last 30 Days):${NC}"

# Read capacity units
READ_CAPACITY=$(get_metric "ConsumedReadCapacityUnits" "Sum" "$START_DATE" "$END_DATE")
READ_CAPACITY_TOTAL=$(echo "$READ_CAPACITY" | awk '{s+=$1} END {print s}')
READ_REQUESTS=$(echo "scale=0; $READ_CAPACITY_TOTAL / 1" | bc 2>/dev/null || echo "0")

echo -e "  Read Requests: ${GREEN}$(printf "%'d" $READ_REQUESTS)${NC}"

# Write capacity units
WRITE_CAPACITY=$(get_metric "ConsumedWriteCapacityUnits" "Sum" "$START_DATE" "$END_DATE")
WRITE_CAPACITY_TOTAL=$(echo "$WRITE_CAPACITY" | awk '{s+=$1} END {print s}')
WRITE_REQUESTS=$(echo "scale=0; $WRITE_CAPACITY_TOTAL / 1" | bc 2>/dev/null || echo "0")

echo -e "  Write Requests: ${GREEN}$(printf "%'d" $WRITE_REQUESTS)${NC}"

# Throttled requests
THROTTLED_READS=$(get_metric "ReadThrottleEvents" "Sum" "$START_DATE" "$END_DATE")
THROTTLED_WRITES=$(get_metric "WriteThrottleEvents" "Sum" "$START_DATE" "$END_DATE")
THROTTLED_READS_TOTAL=$(echo "$THROTTLED_READS" | awk '{s+=$1} END {print s}')
THROTTLED_WRITES_TOTAL=$(echo "$THROTTLED_WRITES" | awk '{s+=$1} END {print s}')

if [ "$THROTTLED_READS_TOTAL" = "0" ] && [ "$THROTTLED_WRITES_TOTAL" = "0" ]; then
    echo -e "  Throttled Requests: ${GREEN}0 (Good!)${NC}"
else
    echo -e "  Throttled Reads: ${RED}$THROTTLED_READS_TOTAL${NC}"
    echo -e "  Throttled Writes: ${RED}$THROTTLED_WRITES_TOTAL${NC}"
fi
echo ""

# Cost estimation
echo -e "${YELLOW}Cost Estimation (Last 30 Days):${NC}"

# DynamoDB pricing (ap-southeast-2)
READ_COST_PER_MILLION=0.25
WRITE_COST_PER_MILLION=1.25
STORAGE_COST_PER_GB=0.25

# Calculate costs
READ_COST=$(echo "scale=2; $READ_REQUESTS / 1000000 * $READ_COST_PER_MILLION" | bc 2>/dev/null || echo "0")
WRITE_COST=$(echo "scale=2; $WRITE_REQUESTS / 1000000 * $WRITE_COST_PER_MILLION" | bc 2>/dev/null || echo "0")
STORAGE_COST=$(echo "scale=2; $TABLE_SIZE_MB / 1024 * $STORAGE_COST_PER_GB" | bc 2>/dev/null || echo "0")
PITR_COST=1.00  # Approximate cost for point-in-time recovery

TOTAL_COST=$(echo "scale=2; $READ_COST + $WRITE_COST + $STORAGE_COST + $PITR_COST" | bc 2>/dev/null || echo "0")

echo -e "  Read Requests: \$${READ_COST}"
echo -e "  Write Requests: \$${WRITE_COST}"
echo -e "  Storage: \$${STORAGE_COST}"
echo -e "  Point-in-Time Recovery: \$${PITR_COST}"
echo -e "  ${GREEN}Total Estimated Cost: \$${TOTAL_COST}${NC}"
echo ""

# Cost comparison
OPENSEARCH_COST=102.00
SAVINGS=$(echo "scale=2; $OPENSEARCH_COST - $TOTAL_COST" | bc 2>/dev/null || echo "0")
SAVINGS_PERCENT=$(echo "scale=1; ($SAVINGS / $OPENSEARCH_COST) * 100" | bc 2>/dev/null || echo "0")

echo -e "${YELLOW}Cost Comparison:${NC}"
echo -e "  OpenSearch (before): ${RED}\$${OPENSEARCH_COST}${NC}"
echo -e "  DynamoDB (after): ${GREEN}\$${TOTAL_COST}${NC}"
echo -e "  ${GREEN}Monthly Savings: \$${SAVINGS} (${SAVINGS_PERCENT}%)${NC}"
echo -e "  ${GREEN}Annual Savings: \$$(echo "scale=2; $SAVINGS * 12" | bc)${NC}"
echo ""

# Get actual AWS costs (if available)
echo -e "${YELLOW}Actual AWS Costs (from Cost Explorer):${NC}"

# Get first day of current month
MONTH_START=$(date -u +"%Y-%m-01" 2>/dev/null || date -u -v1d +"%Y-%m-01")
MONTH_END=$(date -u +"%Y-%m-%d")

ACTUAL_COST=$(aws ce get-cost-and-usage \
    --time-period Start="$MONTH_START",End="$MONTH_END" \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --filter file://<(echo '{
        "And": [
            {"Dimensions": {"Key": "SERVICE", "Values": ["Amazon DynamoDB"]}},
            {"Tags": {"Key": "Name", "Values": ["'"$TABLE_NAME"'"]}}
        ]
    }') \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query 'ResultsByTime[0].Total.BlendedCost.Amount' \
    --output text 2>/dev/null || echo "N/A")

if [ "$ACTUAL_COST" != "N/A" ] && [ -n "$ACTUAL_COST" ]; then
    echo -e "  Actual Cost (Month-to-Date): ${GREEN}\$${ACTUAL_COST}${NC}"
    
    # Calculate projected monthly cost
    DAYS_IN_MONTH=$(date -d "$(date +%Y-%m-01) +1 month -1 day" +%d 2>/dev/null || echo "30")
    CURRENT_DAY=$(date +%d)
    PROJECTED_COST=$(echo "scale=2; $ACTUAL_COST * $DAYS_IN_MONTH / $CURRENT_DAY" | bc 2>/dev/null || echo "N/A")
    
    if [ "$PROJECTED_COST" != "N/A" ]; then
        echo -e "  Projected Monthly Cost: ${GREEN}\$${PROJECTED_COST}${NC}"
    fi
else
    echo -e "  ${YELLOW}Actual cost data not available yet${NC}"
    echo -e "  ${YELLOW}(Cost Explorer data may take 24-48 hours to appear)${NC}"
fi
echo ""

# Performance metrics
echo -e "${YELLOW}Performance Metrics:${NC}"

# Get latency metrics
SUCCESS_LATENCY=$(get_metric "SuccessfulRequestLatency" "Average" "$START_DATE" "$END_DATE")
SUCCESS_LATENCY_AVG=$(echo "$SUCCESS_LATENCY" | awk '{s+=$1; n++} END {if (n>0) print s/n; else print 0}')
SUCCESS_LATENCY_MS=$(echo "scale=2; $SUCCESS_LATENCY_AVG" | bc 2>/dev/null || echo "0")

echo -e "  Average Latency: ${GREEN}${SUCCESS_LATENCY_MS} ms${NC}"

# Check if latency is within target
if (( $(echo "$SUCCESS_LATENCY_MS < 50" | bc -l) )); then
    echo -e "  Latency Status: ${GREEN}✓ Within target (<50ms)${NC}"
else
    echo -e "  Latency Status: ${YELLOW}⚠ Above target (>50ms)${NC}"
fi
echo ""

# Recommendations
echo -e "${YELLOW}Recommendations:${NC}"

if [ "$THROTTLED_READS_TOTAL" != "0" ] || [ "$THROTTLED_WRITES_TOTAL" != "0" ]; then
    echo -e "  ${RED}⚠ Throttling detected!${NC}"
    echo -e "    Consider reviewing query patterns or switching to provisioned capacity"
fi

if (( $(echo "$SUCCESS_LATENCY_MS > 50" | bc -l) )); then
    echo -e "  ${YELLOW}⚠ High latency detected${NC}"
    echo -e "    Consider adding caching layer (Redis/DAX) for frequently accessed items"
fi

if (( $(echo "$TOTAL_COST < 5" | bc -l) )); then
    echo -e "  ${GREEN}✓ Costs are very low - on-demand billing is optimal${NC}"
elif (( $(echo "$TOTAL_COST > 20" | bc -l) )); then
    echo -e "  ${YELLOW}⚠ Costs are higher than expected${NC}"
    echo -e "    Review query patterns and consider optimization"
else
    echo -e "  ${GREEN}✓ Costs are within expected range${NC}"
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Migration Success!${NC}"
echo -e "Saving approximately ${GREEN}\$${SAVINGS}/month${NC} (${SAVINGS_PERCENT}% reduction)"
echo -e "${BLUE}========================================${NC}"
