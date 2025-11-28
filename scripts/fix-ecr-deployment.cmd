@echo off
REM Windows batch script to deploy the application

echo Starting deployment process...

REM Get AWS account ID
for /f "tokens=*" %%i in ('aws sts get-caller-identity --query Account --output text') do set AWS_ACCOUNT_ID=%%i
set AWS_REGION=ap-southeast-2
set ECR_REPO_NAME=cloud-scientific-raster-sharing-repo
set ECR_URI=%AWS_ACCOUNT_ID%.dkr.ecr.%AWS_REGION%.amazonaws.com/%ECR_REPO_NAME%

echo ECR Repository: %ECR_URI%

REM Login to ECR
echo Logging into ECR...
aws ecr get-login-password --region %AWS_REGION% | docker login --username AWS --password-stdin %AWS_ACCOUNT_ID%.dkr.ecr.%AWS_REGION%.amazonaws.com

REM Build Docker image
echo Building Docker image...
cd app
docker build -t raster-app .

REM Tag image for ECR
echo Tagging image for ECR...
docker tag raster-app:latest %ECR_URI%:latest

REM Push to ECR
echo Pushing image to ECR...
docker push %ECR_URI%:latest

REM Update ECS services
echo Updating ECS services...
aws ecs update-service --cluster cloud-sciraster-ecs-cluster --service tiles-service --force-new-deployment --region %AWS_REGION%
aws ecs update-service --cluster cloud-sciraster-ecs-cluster --service timeseries-service --force-new-deployment --region %AWS_REGION%

echo Deployment initiated. Services are updating...
echo Check deployment status with:
echo aws ecs describe-services --cluster cloud-sciraster-ecs-cluster --services tiles-service timeseries-service

cd ..