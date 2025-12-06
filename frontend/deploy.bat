@echo off
REM Deploy frontend to S3 with dynamic configuration

echo Deploying frontend to S3...

REM Set AWS profile
set AWS_PROFILE=DEVplatform

REM Get outputs from Terraform
cd ..\terraform
for /f "tokens=*" %%i in ('terraform output -raw alb_dns_name') do set ALB_DNS=%%i
for /f "tokens=*" %%i in ('terraform output -raw frontend_bucket_name') do set BUCKET_NAME=%%i

if "%ALB_DNS%"=="" (
    echo Error: Could not get ALB DNS name from Terraform
    exit /b 1
)

if "%BUCKET_NAME%"=="" (
    echo Error: Could not get frontend bucket name from Terraform
    exit /b 1
)

echo Using API URL: http://%ALB_DNS%
echo Deploying to bucket: %BUCKET_NAME%

REM Build frontend with dynamic API URL
cd ..\frontend
set VITE_API_BASE_URL=http://%ALB_DNS%
npm run build

REM Upload to S3
aws s3 sync dist/ s3://%BUCKET_NAME%/ --delete

echo Frontend deployed successfully!