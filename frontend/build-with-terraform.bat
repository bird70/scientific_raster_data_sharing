@echo off
REM Build frontend with dynamic API URL from Terraform

echo Building frontend with Terraform-provided API URL...

REM Get ALB DNS name from Terraform
cd ..\terraform
for /f "tokens=*" %%i in ('terraform output -raw alb_dns_name') do set ALB_DNS=%%i

if "%ALB_DNS%"=="" (
    echo Error: Could not get ALB DNS name from Terraform
    exit /b 1
)

echo Using API URL: http://%ALB_DNS%

REM Build frontend with dynamic API URL
cd ..\frontend
set VITE_API_BASE_URL=http://%ALB_DNS%
npm run build

echo Frontend built successfully with API URL: http://%ALB_DNS%