# Deploy and Test ECS Zarr Conversion Migration
# This script deploys the updated infrastructure and runs integration tests

$ErrorActionPreference = "Stop"

# Configuration
$env:AWS_PROFILE = "DEVcloud"
if (-not $env:AWS_REGION) {
    $env:AWS_REGION = "ap-southeast-2"
}

Write-Host "========================================" -ForegroundColor Green
Write-Host "ECS Zarr Conversion Migration Deployment" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "AWS Profile: $env:AWS_PROFILE"
Write-Host "AWS Region: $env:AWS_REGION"
Write-Host ""

# Step 1: Terraform Plan
Write-Host "Step 1: Running Terraform Plan..." -ForegroundColor Yellow
Set-Location terraform

terraform plan -var-file=terraform.tfvars -out=ecs-migration.tfplan

Write-Host ""
$continue = Read-Host "Review the plan above. Continue with apply? (yes/no)"

if ($continue -ne "yes") {
    Write-Host "Deployment cancelled by user" -ForegroundColor Red
    exit 1
}

# Step 2: Terraform Apply
Write-Host ""
Write-Host "Step 2: Applying Terraform Changes..." -ForegroundColor Yellow
terraform apply ecs-migration.tfplan

# Get outputs
Write-Host ""
Write-Host "Retrieving Terraform Outputs..." -ForegroundColor Yellow

try {
    $env:RAW_BUCKET = terraform output -raw s3_raw_bucket
    $env:ZARR_BUCKET = terraform output -raw s3_zarr_bucket
    $env:COG_BUCKET = terraform output -raw s3_cog_bucket
    $env:STAC_BUCKET = terraform output -raw s3_stac_bucket
    $env:STATE_MACHINE_ARN = terraform output -raw ingestion_state_machine_arn
}
catch {
    Write-Host "Error: Failed to retrieve Terraform outputs" -ForegroundColor Red
    exit 1
}

Set-Location ..

# Verify outputs
if (-not $env:RAW_BUCKET -or -not $env:ZARR_BUCKET -or -not $env:COG_BUCKET -or -not $env:STATE_MACHINE_ARN) {
    Write-Host "Error: Failed to retrieve required Terraform outputs" -ForegroundColor Red
    Write-Host "RAW_BUCKET: $env:RAW_BUCKET"
    Write-Host "ZARR_BUCKET: $env:ZARR_BUCKET"
    Write-Host "COG_BUCKET: $env:COG_BUCKET"
    Write-Host "STATE_MACHINE_ARN: $env:STATE_MACHINE_ARN"
    exit 1
}

Write-Host "✓ Terraform deployment complete" -ForegroundColor Green
Write-Host ""
Write-Host "Bucket Configuration:"
Write-Host "  Raw Bucket: $env:RAW_BUCKET"
Write-Host "  Zarr Bucket: $env:ZARR_BUCKET"
Write-Host "  COG Bucket: $env:COG_BUCKET"
Write-Host "  STAC Bucket: $env:STAC_BUCKET"
Write-Host "  State Machine: $env:STATE_MACHINE_ARN"
Write-Host ""

# Step 3: Run Integration Test
Write-Host "Step 3: Running Integration Test..." -ForegroundColor Yellow
Write-Host ""
$runTest = Read-Host "Run end-to-end integration test? (yes/no)"

if ($runTest -eq "yes") {
    $env:RUN_INTEGRATION_TESTS = "true"
    $env:CLEANUP_TEST_FILES = "false"
    
    Set-Location app
    
    Write-Host ""
    Write-Host "Running pytest integration test..." -ForegroundColor Yellow
    pytest tests/integration/test_ingestion_pipeline.py::test_end_to_end_pipeline -v -s
    
    $testResult = $LASTEXITCODE
    
    Set-Location ..
    
    if ($testResult -eq 0) {
        Write-Host ""
        Write-Host "✅ Integration test PASSED" -ForegroundColor Green
    }
    else {
        Write-Host ""
        Write-Host "❌ Integration test FAILED" -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "Skipping integration test" -ForegroundColor Yellow
}

# Step 4: Monitor CloudWatch Logs
Write-Host ""
Write-Host "Step 4: CloudWatch Logs" -ForegroundColor Yellow
Write-Host ""
Write-Host "To monitor ECS task logs, run:"
Write-Host "  aws logs tail /ecs/zarr-conversion --follow --profile $env:AWS_PROFILE"
Write-Host "  aws logs tail /ecs/cog-generation --follow --profile $env:AWS_PROFILE"
Write-Host ""
Write-Host "To view Step Functions execution:"
Write-Host "  aws stepfunctions list-executions --state-machine-arn $env:STATE_MACHINE_ARN --profile $env:AWS_PROFILE"
Write-Host ""

# Step 5: Summary
Write-Host "========================================" -ForegroundColor Green
Write-Host "Deployment Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Next Steps:"
Write-Host "1. Upload a NetCDF file to test:"
Write-Host "   aws s3 cp data/A2002070120230731_MC_SST_std_coastal_v05.nc s3://$env:RAW_BUCKET/ingestion/ --profile $env:AWS_PROFILE"
Write-Host ""
Write-Host "2. Monitor Step Functions execution in AWS Console:"
Write-Host "   https://console.aws.amazon.com/states/home?region=$env:AWS_REGION#/statemachines"
Write-Host ""
Write-Host "3. Check output files:"
Write-Host "   aws s3 ls s3://$env:ZARR_BUCKET/zarr/ --profile $env:AWS_PROFILE"
Write-Host "   aws s3 ls s3://$env:COG_BUCKET/cog/ --profile $env:AWS_PROFILE"
Write-Host "   aws s3 ls s3://$env:STAC_BUCKET/stac/ --profile $env:AWS_PROFILE"
Write-Host ""
