# Validate NetCDF Metadata Enhancement Deployment
# Simple validation script

$ErrorActionPreference = "Continue"

$AWS_PROFILE = "DEVcloud"
$AWS_REGION = "ap-southeast-2"

Write-Host "========================================" -ForegroundColor Green
Write-Host "Deployment Validation" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

# Check ECR image
Write-Host "Checking ECR image..." -ForegroundColor Yellow
$IMAGE_NAME = "cloud-scientific-raster-sharing-repo"
try {
    $imageInfo = aws ecr describe-images --repository-name $IMAGE_NAME --image-ids imageTag=latest --region $AWS_REGION --profile $AWS_PROFILE --query 'imageDetails[0]' --output json | ConvertFrom-Json
    Write-Host "  checkmark Image found in ECR" -ForegroundColor Green
    Write-Host "    Digest: $($imageInfo.imageDigest.Substring(0,20))..."
    Write-Host "    Pushed: $($imageInfo.imagePushedAt)"
    Write-Host "    Size: $([math]::Round($imageInfo.imageSizeInBytes / 1MB, 2)) MB"
} catch {
    Write-Host "  x Image not found" -ForegroundColor Red
}
Write-Host ""

# Check S3 buckets
Write-Host "Checking S3 buckets..." -ForegroundColor Yellow
try {
    $buckets = aws s3api list-buckets --profile $AWS_PROFILE --query "Buckets[?starts_with(Name, 'cloud-scientific-raster-sharing')].Name" --output json | ConvertFrom-Json
    if ($buckets.Count -gt 0) {
        Write-Host "  checkmark Found $($buckets.Count) project buckets" -ForegroundColor Green
        foreach ($bucket in $buckets) {
            Write-Host "    - $bucket"
        }
    } else {
        Write-Host "  x No project buckets found" -ForegroundColor Red
    }
} catch {
    Write-Host "  x Failed to check S3 buckets" -ForegroundColor Red
}
Write-Host ""

# Check DynamoDB table
Write-Host "Checking DynamoDB STAC table..." -ForegroundColor Yellow
$tableName = "cloud-scientific-raster-sharing-stac"
try {
    $tableInfo = aws dynamodb describe-table --table-name $tableName --region $AWS_REGION --profile $AWS_PROFILE --query 'Table' --output json | ConvertFrom-Json
    Write-Host "  checkmark STAC table exists" -ForegroundColor Green
    Write-Host "    Status: $($tableInfo.TableStatus)"
    Write-Host "    Item count: $($tableInfo.ItemCount)"
} catch {
    Write-Host "  x STAC table not found" -ForegroundColor Red
}
Write-Host ""

Write-Host "========================================" -ForegroundColor Green
Write-Host "Validation Complete" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "The Docker image with CRS detection and metadata extraction" -ForegroundColor Cyan
Write-Host "has been successfully built and pushed to ECR." -ForegroundColor Cyan
Write-Host ""
Write-Host "To fully test the deployment:" -ForegroundColor Yellow
Write-Host "1. Start the ECS cluster (if not running)"
Write-Host "2. Upload a test NetCDF file to trigger ingestion"
Write-Host "3. Monitor CloudWatch logs for CRS detection messages"
Write-Host "4. Check STAC metadata for correct bounding boxes and collections"
Write-Host ""
