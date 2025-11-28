#!/bin/bash
# Script to remove OpenSearch infrastructure via Terraform
# This script guides through the process of reviewing and applying Terraform changes

set -e

echo "========================================="
echo "OpenSearch Removal Script"
echo "========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if we're in the right directory
if [ ! -d "terraform" ]; then
    echo -e "${RED}Error: terraform directory not found${NC}"
    echo "Please run this script from the project root directory"
    exit 1
fi

echo -e "${BLUE}This script will:${NC}"
echo "1. Run terraform plan to review changes"
echo "2. Show resources that will be destroyed"
echo "3. Prompt for confirmation before applying"
echo "4. Apply the changes to remove OpenSearch"
echo "5. Verify the deployment"
echo ""

# Step 1: Initialize Terraform (if needed)
echo "========================================="
echo "Step 1: Terraform Initialization"
echo "========================================="
cd terraform

if [ ! -d ".terraform" ]; then
    echo "Initializing Terraform..."
    terraform init
else
    echo -e "${GREEN}✓ Terraform already initialized${NC}"
fi
echo ""

# Step 2: Run terraform plan
echo "========================================="
echo "Step 2: Terraform Plan"
echo "========================================="
echo "Running terraform plan to review changes..."
echo ""

terraform plan -out=opensearch-removal.tfplan

echo ""
echo -e "${YELLOW}⚠ IMPORTANT: Review the plan above carefully${NC}"
echo ""
echo "Expected changes:"
echo "  - OpenSearch domain will be DESTROYED"
echo "  - OpenSearch IAM policies will be DESTROYED"
echo "  - ECS task definitions will be UPDATED (environment variables removed)"
echo "  - Lambda functions will be UPDATED (environment variables removed)"
echo ""

# Step 3: Confirm before applying
echo "========================================="
echo "Step 3: Confirmation"
echo "========================================="
read -p "Do you want to apply these changes? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo -e "${YELLOW}Aborted. No changes were made.${NC}"
    rm -f opensearch-removal.tfplan
    exit 0
fi

# Step 4: Apply changes
echo ""
echo "========================================="
echo "Step 4: Applying Terraform Changes"
echo "========================================="
echo "Applying changes..."
echo ""

terraform apply opensearch-removal.tfplan

echo ""
echo -e "${GREEN}✓ Terraform apply completed${NC}"
echo ""

# Clean up plan file
rm -f opensearch-removal.tfplan

# Step 5: Verify deployment
echo "========================================="
echo "Step 5: Post-Deployment Verification"
echo "========================================="
echo ""

# Wait for ECS services to stabilize
echo "Waiting 30 seconds for ECS services to stabilize..."
sleep 30

# Check ECS service status
echo "Checking ECS service status..."
CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "")

if [ -n "$CLUSTER_NAME" ]; then
    TILES_STATUS=$(aws ecs describe-services --cluster "$CLUSTER_NAME" --services tiles-service --query 'services[0].status' --output text 2>/dev/null || echo "UNKNOWN")
    TIMESERIES_STATUS=$(aws ecs describe-services --cluster "$CLUSTER_NAME" --services timeseries-service --query 'services[0].status' --output text 2>/dev/null || echo "UNKNOWN")
    
    if [ "$TILES_STATUS" = "ACTIVE" ]; then
        echo -e "${GREEN}✓ Tiles service: ACTIVE${NC}"
    else
        echo -e "${RED}✗ Tiles service: $TILES_STATUS${NC}"
    fi
    
    if [ "$TIMESERIES_STATUS" = "ACTIVE" ]; then
        echo -e "${GREEN}✓ Timeseries service: ACTIVE${NC}"
    else
        echo -e "${RED}✗ Timeseries service: $TIMESERIES_STATUS${NC}"
    fi
fi

echo ""

# Check if OpenSearch domain is gone
echo "Verifying OpenSearch domain is deleted..."
cd ..
OPENSEARCH_DOMAINS=$(aws opensearch list-domain-names --query 'DomainNames[?contains(DomainName, `stac`)].DomainName' --output text 2>/dev/null || echo "")

if [ -z "$OPENSEARCH_DOMAINS" ]; then
    echo -e "${GREEN}✓ OpenSearch domain successfully deleted${NC}"
else
    echo -e "${YELLOW}⚠ OpenSearch domain still exists (may take a few minutes to delete):${NC}"
    echo "  $OPENSEARCH_DOMAINS"
fi

echo ""

# Run verification script
echo "Running comprehensive verification..."
echo ""
cd ..
source scripts/verify-dynamodb-only.sh

echo ""
echo "========================================="
echo "Deployment Complete"
echo "========================================="
echo ""
echo -e "${GREEN}✓ OpenSearch infrastructure has been removed${NC}"
echo ""
echo "Next steps:"
echo "1. Monitor CloudWatch logs for any errors"
echo "2. Verify API functionality with test requests"
echo "3. Check AWS Cost Explorer in 24-48 hours to confirm cost savings"
echo ""
echo "Expected cost savings: ~\$90-100/month"
echo ""
echo "For rollback instructions, see: OPENSEARCH_REMOVAL_SUMMARY.md"
echo ""
