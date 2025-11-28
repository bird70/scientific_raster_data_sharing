#!/bin/bash

# Deploy and Test ECS Zarr Conversion Migration
# This script deploys the updated infrastructure and runs integration tests

set -e

# Configuration
export AWS_PROFILE="DEVcloud"
export AWS_REGION="${AWS_REGION:-ap-southeast-2}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}ECS Zarr Conversion Migration Deployment${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "AWS Profile: $AWS_PROFILE"
echo "AWS Region: $AWS_REGION"
echo ""

# Step 1: Terraform Plan
echo -e "${YELLOW}Step 1: Running Terraform Plan...${NC}"
cd terraform

terraform plan -var-file=terraform.tfvars -out=ecs-migration.tfplan

echo ""
read -p "Review the plan above. Continue with apply? (yes/no): " CONTINUE

if [ "$CONTINUE" != "yes" ]; then
    echo -e "${RED}Deployment cancelled by user${NC}"
    exit 1
fi

# Step 2: Terraform Apply
echo ""
echo -e "${YELLOW}Step 2: Applying Terraform Changes...${NC}"
terraform apply ecs-migration.tfplan

# Get outputs
echo ""
echo -e "${YELLOW}Retrieving Terraform Outputs...${NC}"
export RAW_BUCKET=$(terraform output -raw s3_raw_bucket 2>/dev/null || echo "")
export ZARR_BUCKET=$(terraform output -raw s3_zarr_bucket 2>/dev/null || echo "")
export COG_BUCKET=$(terraform output -raw s3_cog_bucket 2>/dev/null || echo "")
export STAC_BUCKET=$(terraform output -raw s3_stac_bucket 2>/dev/null || echo "")
export STATE_MACHINE_ARN=$(terraform output -raw ingestion_state_machine_arn 2>/dev/null || echo "")

cd ..

# Verify outputs
if [ -z "$RAW_BUCKET" ] || [ -z "$ZARR_BUCKET" ] || [ -z "$COG_BUCKET" ] || [ -z "$STATE_MACHINE_ARN" ]; then
    echo -e "${RED}Error: Failed to retrieve required Terraform outputs${NC}"
    echo "RAW_BUCKET: $RAW_BUCKET"
    echo "ZARR_BUCKET: $ZARR_BUCKET"
    echo "COG_BUCKET: $COG_BUCKET"
    echo "STATE_MACHINE_ARN: $STATE_MACHINE_ARN"
    exit 1
fi

echo -e "${GREEN}✓ Terraform deployment complete${NC}"
echo ""
echo "Bucket Configuration:"
echo "  Raw Bucket: $RAW_BUCKET"
echo "  Zarr Bucket: $ZARR_BUCKET"
echo "  COG Bucket: $COG_BUCKET"
echo "  STAC Bucket: $STAC_BUCKET"
echo "  State Machine: $STATE_MACHINE_ARN"
echo ""

# Step 3: Run Integration Test
echo -e "${YELLOW}Step 3: Running Integration Test...${NC}"
echo ""
read -p "Run end-to-end integration test? (yes/no): " RUN_TEST

if [ "$RUN_TEST" == "yes" ]; then
    export RUN_INTEGRATION_TESTS=true
    export CLEANUP_TEST_FILES=false  # Keep files for inspection
    
    cd app
    
    echo ""
    echo -e "${YELLOW}Running pytest integration test...${NC}"
    pytest tests/integration/test_ingestion_pipeline.py::test_end_to_end_pipeline -v -s
    
    TEST_RESULT=$?
    
    cd ..
    
    if [ $TEST_RESULT -eq 0 ]; then
        echo ""
        echo -e "${GREEN}✅ Integration test PASSED${NC}"
    else
        echo ""
        echo -e "${RED}❌ Integration test FAILED${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}Skipping integration test${NC}"
fi

# Step 4: Monitor CloudWatch Logs
echo ""
echo -e "${YELLOW}Step 4: CloudWatch Logs${NC}"
echo ""
echo "To monitor ECS task logs, run:"
echo "  aws logs tail /ecs/zarr-conversion --follow --profile $AWS_PROFILE"
echo "  aws logs tail /ecs/cog-generation --follow --profile $AWS_PROFILE"
echo ""
echo "To view Step Functions execution:"
echo "  aws stepfunctions list-executions --state-machine-arn $STATE_MACHINE_ARN --profile $AWS_PROFILE"
echo ""

# Step 5: Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Next Steps:"
echo "1. Upload a NetCDF file to test:"
echo "   aws s3 cp data/A2002070120230731_MC_SST_std_coastal_v05.nc s3://$RAW_BUCKET/ingestion/ --profile $AWS_PROFILE"
echo ""
echo "2. Monitor Step Functions execution in AWS Console:"
echo "   https://console.aws.amazon.com/states/home?region=$AWS_REGION#/statemachines"
echo ""
echo "3. Check output files:"
echo "   aws s3 ls s3://$ZARR_BUCKET/zarr/ --profile $AWS_PROFILE"
echo "   aws s3 ls s3://$COG_BUCKET/cog/ --profile $AWS_PROFILE"
echo "   aws s3 ls s3://$STAC_BUCKET/stac/ --profile $AWS_PROFILE"
echo ""
