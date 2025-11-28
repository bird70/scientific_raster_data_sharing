# Deploy NetCDF Metadata Enhancement Feature
# This script builds and pushes the Docker image with CRS detection and metadata extraction

$ErrorActionPreference = "Stop"

# Configuration
$AWS_PROFILE = "DEVcloud"
$AWS_REGION = "ap-southeast-2"
$ECR_REGISTRY = "123456789101.dkr.ecr.ap-southeast-2.amazonaws.com"
$IMAGE_NAME = "cloud-scientific-raster-sharing-repo"
$IMAGE_TAG = "latest"

Write-Host "========================================" -ForegroundColor Green
Write-Host "NetCDF Metadata Enhancement Deployment" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

# Check if Docker is running
try {
    docker info | Out-Null
    Write-Host "checkmark Docker is running" -ForegroundColor Green
} catch {
    Write-Host "x Error: Docker is not running" -ForegroundColor Red
    Write-Host "Please start Docker Desktop and try again"
    exit 1
}
Write-Host ""

# Step 1: Login to ECR
Write-Host "Step 1: Logging in to ECR..." -ForegroundColor Yellow
try {
    $password = aws ecr get-login-password --region $AWS_REGION --profile $AWS_PROFILE
    $password | docker login --username AWS --password-stdin $ECR_REGISTRY
    Write-Host "checkmark Successfully logged in to ECR" -ForegroundColor Green
} catch {
    Write-Host "x Failed to login to ECR" -ForegroundColor Red
    Write-Host $_.Exception.Message
    exit 1
}
Write-Host ""

# Step 2: Build Docker image
Write-Host "Step 2: Building Docker image..." -ForegroundColor Yellow
Write-Host "This may take several minutes..."
Write-Host ""

try {
    docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" -f app/Dockerfile .
    Write-Host ""
    Write-Host "checkmark Successfully built Docker image" -ForegroundColor Green
} catch {
    Write-Host "x Failed to build Docker image" -ForegroundColor Red
    Write-Host $_.Exception.Message
    exit 1
}
Write-Host ""

# Step 3: Tag image
Write-Host "Step 3: Tagging image..." -ForegroundColor Yellow
try {
    docker tag "${IMAGE_NAME}:${IMAGE_TAG}" "${ECR_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
    Write-Host "checkmark Successfully tagged image" -ForegroundColor Green
} catch {
    Write-Host "x Failed to tag image" -ForegroundColor Red
    Write-Host $_.Exception.Message
    exit 1
}
Write-Host ""

# Step 4: Push to ECR
Write-Host "Step 4: Pushing image to ECR..." -ForegroundColor Yellow
Write-Host "This may take several minutes..."
Write-Host ""

try {
    docker push "${ECR_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
    Write-Host ""
    Write-Host "checkmark Successfully pushed image to ECR" -ForegroundColor Green
} catch {
    Write-Host "x Failed to push image to ECR" -ForegroundColor Red
    Write-Host $_.Exception.Message
    exit 1
}
Write-Host ""

# Step 5: Verify new image
Write-Host "Step 5: Verifying new image..." -ForegroundColor Yellow
try {
    $imageInfo = aws ecr describe-images --repository-name $IMAGE_NAME --image-ids imageTag=$IMAGE_TAG --region $AWS_REGION --profile $AWS_PROFILE --query 'imageDetails[0]' --output json | ConvertFrom-Json
    
    Write-Host "checkmark Image verified in ECR" -ForegroundColor Green
    Write-Host "  Digest: $($imageInfo.imageDigest)"
    Write-Host "  Pushed: $($imageInfo.imagePushedAt)"
    Write-Host "  Size: $([math]::Round($imageInfo.imageSizeInBytes / 1MB, 2)) MB"
} catch {
    Write-Host "warning Could not verify image details" -ForegroundColor Yellow
    Write-Host $_.Exception.Message
}
Write-Host ""

# Step 6: Update ECS services
Write-Host "Step 6: Updating ECS services..." -ForegroundColor Yellow
Write-Host "Forcing new deployment to use updated image..."
Write-Host ""

try {
    $clusterName = "cloud-scientific-raster-sharing-cluster"
    
    $services = aws ecs list-services --cluster $clusterName --region $AWS_REGION --profile $AWS_PROFILE --query 'serviceArns' --output json | ConvertFrom-Json
    
    if ($services.Count -eq 0) {
        Write-Host "warning No services found in cluster" -ForegroundColor Yellow
    } else {
        foreach ($serviceArn in $services) {
            $serviceName = $serviceArn.Split('/')[-1]
            Write-Host "  Updating service: $serviceName" -ForegroundColor Cyan
            
            aws ecs update-service --cluster $clusterName --service $serviceName --force-new-deployment --region $AWS_REGION --profile $AWS_PROFILE --output json | Out-Null
            
            Write-Host "  checkmark Service update initiated" -ForegroundColor Green
        }
    }
} catch {
    Write-Host "warning Could not update ECS services" -ForegroundColor Yellow
    Write-Host $_.Exception.Message
    Write-Host "You may need to manually update services in the AWS Console"
}
Write-Host ""

Write-Host "========================================" -ForegroundColor Green
Write-Host "Deployment Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Monitor ECS service deployment in AWS Console"
Write-Host "2. Check CloudWatch logs for CRS detection messages"
Write-Host "3. Re-ingest test files to verify functionality"
Write-Host "4. Query STAC API to verify metadata is searchable"
Write-Host ""
