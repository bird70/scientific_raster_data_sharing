# Validation Script for Task 10 Monitoring Setup (PowerShell)
# This script validates that all monitoring infrastructure is properly configured

param(
    [string]$Region = $env:AWS_REGION ?? "us-east-1",
    [string]$ProjectName = $env:PROJECT_NAME ?? "[YOURORG]"
)

$ErrorActionPreference = "Continue"

Write-Host "=== Validating Monitoring Setup ===" -ForegroundColor Blue
Write-Host ""

# Track validation results
$Passed = 0
$Failed = 0
$Warnings = 0

function Test-Check {
    param(
        [string]$TestName,
        [bool]$Result
    )
    
    if ($Result) {
        Write-Host "✓ $TestName" -ForegroundColor Green
        $script:Passed++
        return $true
    } else {
        Write-Host "✗ $TestName" -ForegroundColor Red
        $script:Failed++
        return $false
    }
}

function Write-Warning-Check {
    param(
        [string]$TestName,
        [string]$Message
    )
    
    Write-Host "⚠ $TestName`: $Message" -ForegroundColor Yellow
    $script:Warnings++
}

# 1. Check Terraform outputs
Write-Host "1. Checking Terraform Outputs..." -ForegroundColor Blue

Push-Location
try {
    if (Test-Path "terraform") {
        Set-Location terraform
    } elseif (Test-Path "../terraform") {
        Set-Location ../terraform
    } else {
        Write-Host "Error: terraform directory not found" -ForegroundColor Red
        exit 1
    }
    
    $StateMachineArn = terraform output -raw ingestion_state_machine_arn 2>$null
    $ClusterName = terraform output -raw ecs_cluster_name 2>$null
    
    Test-Check "Step Functions ARN available" (-not [string]::IsNullOrEmpty($StateMachineArn))
    Test-Check "ECS Cluster name available" (-not [string]::IsNullOrEmpty($ClusterName))
} finally {
    Pop-Location
}

# 2. Check CloudWatch Alarms
Write-Host ""
Write-Host "2. Checking CloudWatch Alarms..." -ForegroundColor Blue

$ExpectedAlarms = @(
    "$ProjectName-ingestion-high-failure-rate",
    "$ProjectName-ingestion-long-execution",
    "$ProjectName-zarr-task-failure",
    "$ProjectName-cog-task-failure",
    "$ProjectName-zarr-high-memory",
    "$ProjectName-cog-high-memory"
)

foreach ($alarm in $ExpectedAlarms) {
    try {
        $AlarmExists = aws cloudwatch describe-alarms `
            --alarm-names $alarm `
            --region $Region `
            --query 'MetricAlarms[0].AlarmName' `
            --output text 2>$null
        
        Test-Check "Alarm: $alarm" ($AlarmExists -and $AlarmExists -ne "None")
    } catch {
        Test-Check "Alarm: $alarm" $false
    }
}

# 3. Check CloudWatch Dashboard
Write-Host ""
Write-Host "3. Checking CloudWatch Dashboard..." -ForegroundColor Blue

try {
    $DashboardExists = aws cloudwatch list-dashboards `
        --dashboard-name-prefix "$ProjectName-ingestion-pipeline" `
        --region $Region `
        --query 'DashboardEntries[0].DashboardName' `
        --output text 2>$null
    
    Test-Check "Dashboard: $ProjectName-ingestion-pipeline" ($DashboardExists -and $DashboardExists -ne "None")
} catch {
    Test-Check "Dashboard: $ProjectName-ingestion-pipeline" $false
}

# 4. Check SNS Topic
Write-Host ""
Write-Host "4. Checking SNS Topic..." -ForegroundColor Blue

try {
    $SnsTopicJson = aws sns list-topics --region $Region --output json 2>$null
    $SnsTopics = $SnsTopicJson | ConvertFrom-Json
    $AlarmTopic = $SnsTopics.Topics | Where-Object { $_.TopicArn -like "*$ProjectName-alarms*" } | Select-Object -First 1
    
    if ($AlarmTopic) {
        Test-Check "SNS Topic exists" $true
        
        # Check subscriptions
        $SubsJson = aws sns list-subscriptions-by-topic `
            --topic-arn $AlarmTopic.TopicArn `
            --region $Region `
            --output json 2>$null
        $Subscriptions = ($SubsJson | ConvertFrom-Json).Subscriptions
        
        if ($Subscriptions -and $Subscriptions.Count -gt 0) {
            Test-Check "SNS Subscriptions configured" $true
        } else {
            Write-Warning-Check "SNS Subscriptions" "No subscriptions found - alarms won't send notifications"
        }
    } else {
        Test-Check "SNS Topic exists" $false
    }
} catch {
    Test-Check "SNS Topic exists" $false
}

# 5. Check CloudWatch Log Groups
Write-Host ""
Write-Host "5. Checking CloudWatch Log Groups..." -ForegroundColor Blue

$ExpectedLogGroups = @(
    "/ecs/zarr-conversion",
    "/ecs/cog-generation"
)

foreach ($logGroup in $ExpectedLogGroups) {
    try {
        $LogExists = aws logs describe-log-groups `
            --log-group-name-prefix $logGroup `
            --region $Region `
            --query 'logGroups[0].logGroupName' `
            --output text 2>$null
        
        if ($LogExists -and $LogExists -ne "None") {
            Test-Check "Log Group: $logGroup" $true
        } else {
            Write-Warning-Check "Log Group: $logGroup" "Will be created on first task execution"
        }
    } catch {
        Write-Warning-Check "Log Group: $logGroup" "Will be created on first task execution"
    }
}

# 6. Check Monitoring Scripts
Write-Host ""
Write-Host "6. Checking Monitoring Scripts..." -ForegroundColor Blue

Test-Check "Bash monitoring script exists" (Test-Path "scripts/monitor-ingestion-pipeline.sh")
Test-Check "PowerShell monitoring script exists" (Test-Path "scripts/monitor-ingestion-pipeline.ps1")

# 7. Check Documentation
Write-Host ""
Write-Host "7. Checking Documentation..." -ForegroundColor Blue

$ExpectedDocs = @(
    "docs/INGESTION_PIPELINE_MONITORING.md",
    "docs/TASK_10_DEPLOYMENT_CHECKLIST.md",
    "docs/MONITORING_QUICK_REFERENCE.md"
)

foreach ($doc in $ExpectedDocs) {
    Test-Check "Documentation: $doc" (Test-Path $doc)
}

# 8. Check Terraform Configuration
Write-Host ""
Write-Host "8. Checking Terraform Configuration..." -ForegroundColor Blue

Push-Location
try {
    if (Test-Path "terraform") {
        Set-Location terraform
    } elseif (Test-Path "../terraform") {
        Set-Location ../terraform
    }
    
    $TerraformOutput = terraform validate 2>&1
    $TerraformValid = $TerraformOutput -match "Success"
    
    Test-Check "Terraform configuration valid" $TerraformValid
} finally {
    Pop-Location
}

# 9. Check ECS Task Definitions
Write-Host ""
Write-Host "9. Checking ECS Task Definitions..." -ForegroundColor Blue

$ExpectedTasks = @(
    "zarr-conversion",
    "cog-generation"
)

foreach ($task in $ExpectedTasks) {
    try {
        $TaskExists = aws ecs list-task-definitions `
            --family-prefix $task `
            --region $Region `
            --query 'taskDefinitionArns[0]' `
            --output text 2>$null
        
        if ($TaskExists -and $TaskExists -ne "None") {
            Test-Check "Task Definition: $task" $true
        } else {
            Write-Warning-Check "Task Definition: $task" "Will be created on terraform apply"
        }
    } catch {
        Write-Warning-Check "Task Definition: $task" "Will be created on terraform apply"
    }
}

# 10. Check Step Functions State Machine
Write-Host ""
Write-Host "10. Checking Step Functions State Machine..." -ForegroundColor Blue

if (-not [string]::IsNullOrEmpty($StateMachineArn)) {
    try {
        $StateMachineStatus = aws stepfunctions describe-state-machine `
            --state-machine-arn $StateMachineArn `
            --region $Region `
            --query 'status' `
            --output text 2>$null
        
        Test-Check "State Machine status" ($StateMachineStatus -eq "ACTIVE")
    } catch {
        Test-Check "State Machine status" $false
    }
}

# Summary
Write-Host ""
Write-Host "=== Validation Summary ===" -ForegroundColor Blue
Write-Host "Passed:   $Passed" -ForegroundColor Green
Write-Host "Failed:   $Failed" -ForegroundColor Red
Write-Host "Warnings: $Warnings" -ForegroundColor Yellow

if ($Failed -eq 0) {
    Write-Host ""
    Write-Host "✓ All critical checks passed!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:"
    Write-Host "1. Review any warnings above"
    Write-Host "2. Deploy infrastructure: cd terraform && terraform apply"
    Write-Host "3. Confirm SNS subscription (check email)"
    Write-Host "4. Start monitoring: .\scripts\monitor-ingestion-pipeline.ps1"
    Write-Host "5. Follow deployment checklist: docs\TASK_10_DEPLOYMENT_CHECKLIST.md"
    exit 0
} else {
    Write-Host ""
    Write-Host "✗ Some checks failed. Please review the errors above." -ForegroundColor Red
    Write-Host ""
    Write-Host "Common fixes:"
    Write-Host "1. Run: cd terraform && terraform apply"
    Write-Host "2. Ensure AWS credentials are configured"
    Write-Host "3. Check AWS region is correct: `$env:AWS_REGION='us-east-1'"
    exit 1
}
