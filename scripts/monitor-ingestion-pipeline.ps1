# Monitor Ingestion Pipeline Script (PowerShell)
# This script provides quick access to key metrics and logs for the ECS-based ingestion pipeline

param(
    [string]$Region = $env:AWS_REGION ?? "us-east-1",
    [string]$ProjectName = $env:PROJECT_NAME ?? "[YOURORG]"
)

$ErrorActionPreference = "Stop"

# Get Terraform outputs
Write-Host "Fetching infrastructure details..." -ForegroundColor Blue

Push-Location
try {
    if (Test-Path "terraform") {
        Set-Location terraform
    } elseif (Test-Path "../terraform") {
        Set-Location ../terraform
    } else {
        throw "terraform directory not found"
    }
    
    $StateMachineArn = terraform output -raw ingestion_state_machine_arn 2>$null
    $ClusterName = terraform output -raw ecs_cluster_name 2>$null
    
    if ([string]::IsNullOrEmpty($StateMachineArn)) {
        throw "Could not get Step Functions ARN from Terraform"
    }
} finally {
    Pop-Location
}

function Show-Menu {
    Write-Host ""
    Write-Host "=== Ingestion Pipeline Monitoring ===" -ForegroundColor Green
    Write-Host "1. Show recent Step Functions executions"
    Write-Host "2. Show execution success rate (last 24 hours)"
    Write-Host "3. Show average execution time (last 24 hours)"
    Write-Host "4. Show ECS task metrics (Zarr conversion)"
    Write-Host "5. Show ECS task metrics (COG generation)"
    Write-Host "6. Show recent errors from logs"
    Write-Host "7. Show cost estimation (last 30 days)"
    Write-Host "8. Show CloudWatch alarms status"
    Write-Host "9. Open CloudWatch dashboard (browser)"
    Write-Host "0. Exit"
    Write-Host ""
}

function Show-RecentExecutions {
    Write-Host "Recent Step Functions Executions:" -ForegroundColor Blue
    aws stepfunctions list-executions `
        --state-machine-arn $StateMachineArn `
        --max-results 10 `
        --region $Region `
        --query 'executions[*].[name,status,startDate,stopDate]' `
        --output table
}

function Show-SuccessRate {
    Write-Host "Calculating success rate (last 24 hours)..." -ForegroundColor Blue
    
    $StartTime = (Get-Date).AddHours(-24).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss")
    $EndTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss")
    
    $Succeeded = aws cloudwatch get-metric-statistics `
        --namespace AWS/States `
        --metric-name ExecutionsSucceeded `
        --dimensions Name=StateMachineArn,Value=$StateMachineArn `
        --start-time $StartTime `
        --end-time $EndTime `
        --period 86400 `
        --statistics Sum `
        --region $Region `
        --query 'Datapoints[0].Sum' `
        --output text
    
    $Failed = aws cloudwatch get-metric-statistics `
        --namespace AWS/States `
        --metric-name ExecutionsFailed `
        --dimensions Name=StateMachineArn,Value=$StateMachineArn `
        --start-time $StartTime `
        --end-time $EndTime `
        --period 86400 `
        --statistics Sum `
        --region $Region `
        --query 'Datapoints[0].Sum' `
        --output text
    
    $Succeeded = if ($Succeeded -eq "None" -or [string]::IsNullOrEmpty($Succeeded)) { 0 } else { [int]$Succeeded }
    $Failed = if ($Failed -eq "None" -or [string]::IsNullOrEmpty($Failed)) { 0 } else { [int]$Failed }
    $Total = $Succeeded + $Failed
    
    if ($Total -gt 0) {
        $SuccessRate = [math]::Round(($Succeeded / $Total) * 100, 2)
        Write-Host "Succeeded: $Succeeded" -ForegroundColor Green
        Write-Host "Failed: $Failed" -ForegroundColor Red
        Write-Host "Total: $Total"
        Write-Host "Success Rate: $SuccessRate%" -ForegroundColor Green
        
        if ($SuccessRate -lt 95) {
            Write-Host "⚠ Warning: Success rate below 95% target" -ForegroundColor Yellow
        }
    } else {
        Write-Host "No executions in the last 24 hours"
    }
}

function Show-ExecutionTime {
    Write-Host "Calculating average execution time (last 24 hours)..." -ForegroundColor Blue
    
    $StartTime = (Get-Date).AddHours(-24).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss")
    $EndTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss")
    
    $AvgTime = aws cloudwatch get-metric-statistics `
        --namespace AWS/States `
        --metric-name ExecutionTime `
        --dimensions Name=StateMachineArn,Value=$StateMachineArn `
        --start-time $StartTime `
        --end-time $EndTime `
        --period 86400 `
        --statistics Average `
        --region $Region `
        --query 'Datapoints[0].Average' `
        --output text
    
    $MaxTime = aws cloudwatch get-metric-statistics `
        --namespace AWS/States `
        --metric-name ExecutionTime `
        --dimensions Name=StateMachineArn,Value=$StateMachineArn `
        --start-time $StartTime `
        --end-time $EndTime `
        --period 86400 `
        --statistics Maximum `
        --region $Region `
        --query 'Datapoints[0].Maximum' `
        --output text
    
    if ($AvgTime -ne "None" -and -not [string]::IsNullOrEmpty($AvgTime)) {
        $AvgMinutes = [math]::Round([double]$AvgTime / 60000, 2)
        $MaxMinutes = [math]::Round([double]$MaxTime / 60000, 2)
        
        Write-Host "Average: $AvgMinutes minutes" -ForegroundColor Green
        Write-Host "Maximum: $MaxMinutes minutes" -ForegroundColor Yellow
        
        if ($AvgMinutes -gt 20) {
            Write-Host "⚠ Warning: Average execution time exceeds 20 minute target" -ForegroundColor Yellow
        }
    } else {
        Write-Host "No execution data available"
    }
}

function Show-EcsMetrics {
    param(
        [string]$TaskFamily,
        [string]$TaskName
    )
    
    Write-Host "ECS Task Metrics for $TaskName (last 1 hour):" -ForegroundColor Blue
    
    $StartTime = (Get-Date).AddHours(-1).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss")
    $EndTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss")
    
    $Cpu = aws cloudwatch get-metric-statistics `
        --namespace ECS/ContainerInsights `
        --metric-name CpuUtilization `
        --dimensions Name=ClusterName,Value=$ClusterName Name=TaskDefinitionFamily,Value=$TaskFamily `
        --start-time $StartTime `
        --end-time $EndTime `
        --period 3600 `
        --statistics Average `
        --region $Region `
        --query 'Datapoints[0].Average' `
        --output text
    
    $Memory = aws cloudwatch get-metric-statistics `
        --namespace ECS/ContainerInsights `
        --metric-name MemoryUtilization `
        --dimensions Name=ClusterName,Value=$ClusterName Name=TaskDefinitionFamily,Value=$TaskFamily `
        --start-time $StartTime `
        --end-time $EndTime `
        --period 3600 `
        --statistics Average `
        --region $Region `
        --query 'Datapoints[0].Average' `
        --output text
    
    $Failed = aws cloudwatch get-metric-statistics `
        --namespace ECS/ContainerInsights `
        --metric-name TasksFailed `
        --dimensions Name=ClusterName,Value=$ClusterName Name=TaskDefinitionFamily,Value=$TaskFamily `
        --start-time $StartTime `
        --end-time $EndTime `
        --period 3600 `
        --statistics Sum `
        --region $Region `
        --query 'Datapoints[0].Sum' `
        --output text
    
    if ($Cpu -ne "None" -and -not [string]::IsNullOrEmpty($Cpu)) {
        $CpuRounded = [math]::Round([double]$Cpu, 1)
        $MemoryRounded = [math]::Round([double]$Memory, 1)
        $FailedCount = if ($Failed -eq "None" -or [string]::IsNullOrEmpty($Failed)) { 0 } else { [int]$Failed }
        
        Write-Host "CPU Utilization: $CpuRounded%" -ForegroundColor Green
        Write-Host "Memory Utilization: $MemoryRounded%" -ForegroundColor Green
        Write-Host "Failed Tasks: $FailedCount" -ForegroundColor Red
        
        if ($MemoryRounded -gt 90) {
            Write-Host "⚠ Critical: Memory utilization above 90%" -ForegroundColor Red
        } elseif ($MemoryRounded -gt 80) {
            Write-Host "⚠ Warning: Memory utilization above 80%" -ForegroundColor Yellow
        }
    } else {
        Write-Host "No task data available (tasks may not have run recently)"
    }
}

function Show-RecentErrors {
    Write-Host "Recent errors from Zarr conversion logs:" -ForegroundColor Blue
    $ZarrErrors = aws logs filter-log-events `
        --log-group-name /ecs/zarr-conversion `
        --filter-pattern "ERROR" `
        --start-time $([int]((Get-Date).AddHours(-1) - (Get-Date "1970-01-01")).TotalMilliseconds) `
        --region $Region `
        --query 'events[*].[timestamp,message]' `
        --output text 2>$null
    
    if ($ZarrErrors) {
        $ZarrErrors | Select-Object -First 10
    } else {
        Write-Host "No errors found or log group doesn't exist"
    }
    
    Write-Host ""
    Write-Host "Recent errors from COG generation logs:" -ForegroundColor Blue
    $CogErrors = aws logs filter-log-events `
        --log-group-name /ecs/cog-generation `
        --filter-pattern "ERROR" `
        --start-time $([int]((Get-Date).AddHours(-1) - (Get-Date "1970-01-01")).TotalMilliseconds) `
        --region $Region `
        --query 'events[*].[timestamp,message]' `
        --output text 2>$null
    
    if ($CogErrors) {
        $CogErrors | Select-Object -First 10
    } else {
        Write-Host "No errors found or log group doesn't exist"
    }
}

function Show-CostEstimation {
    Write-Host "Cost estimation (last 30 days):" -ForegroundColor Blue
    
    $StartTime = (Get-Date).AddDays(-30).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss")
    $EndTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss")
    
    $TotalExecTime = aws cloudwatch get-metric-statistics `
        --namespace AWS/States `
        --metric-name ExecutionTime `
        --dimensions Name=StateMachineArn,Value=$StateMachineArn `
        --start-time $StartTime `
        --end-time $EndTime `
        --period 2592000 `
        --statistics Sum `
        --region $Region `
        --query 'Datapoints[0].Sum' `
        --output text
    
    if ($TotalExecTime -ne "None" -and -not [string]::IsNullOrEmpty($TotalExecTime)) {
        $TotalHours = [math]::Round([double]$TotalExecTime / 3600000, 4)
        $CostPerHour = 0.04048
        $TotalCost = [math]::Round($TotalHours * $CostPerHour, 2)
        
        $Executions = aws cloudwatch get-metric-statistics `
            --namespace AWS/States `
            --metric-name ExecutionsSucceeded `
            --dimensions Name=StateMachineArn,Value=$StateMachineArn `
            --start-time $StartTime `
            --end-time $EndTime `
            --period 2592000 `
            --statistics Sum `
            --region $Region `
            --query 'Datapoints[0].Sum' `
            --output text
        
        $ExecutionCount = if ($Executions -eq "None" -or [string]::IsNullOrEmpty($Executions)) { 0 } else { [int]$Executions }
        
        if ($ExecutionCount -gt 0) {
            $CostPerFile = [math]::Round($TotalCost / $ExecutionCount, 4)
            Write-Host "Total execution time: $TotalHours hours" -ForegroundColor Green
            Write-Host "Estimated ECS cost: `$$TotalCost" -ForegroundColor Green
            Write-Host "Number of files processed: $ExecutionCount" -ForegroundColor Green
            Write-Host "Cost per file: `$$CostPerFile" -ForegroundColor Green
            Write-Host ""
            Write-Host "Note: This is an estimate based on execution time." -ForegroundColor Yellow
            Write-Host "Check AWS Cost Explorer for actual costs including Step Functions, S3, etc." -ForegroundColor Yellow
        } else {
            Write-Host "No successful executions in the last 30 days"
        }
    } else {
        Write-Host "No execution data available"
    }
}

function Show-AlarmStatus {
    Write-Host "CloudWatch Alarms Status:" -ForegroundColor Blue
    aws cloudwatch describe-alarms `
        --alarm-name-prefix "$ProjectName-ingestion" `
        --region $Region `
        --query 'MetricAlarms[*].[AlarmName,StateValue,StateReason]' `
        --output table
}

function Open-Dashboard {
    $DashboardUrl = "https://$Region.console.aws.amazon.com/cloudwatch/home?region=$Region#dashboards:name=$ProjectName-ingestion-pipeline"
    Write-Host "Opening CloudWatch dashboard in browser..." -ForegroundColor Blue
    Write-Host "URL: $DashboardUrl"
    Start-Process $DashboardUrl
}

# Main loop
while ($true) {
    Show-Menu
    $choice = Read-Host "Select an option"
    
    switch ($choice) {
        "1" { Show-RecentExecutions }
        "2" { Show-SuccessRate }
        "3" { Show-ExecutionTime }
        "4" { Show-EcsMetrics -TaskFamily "zarr-conversion" -TaskName "Zarr Conversion" }
        "5" { Show-EcsMetrics -TaskFamily "cog-generation" -TaskName "COG Generation" }
        "6" { Show-RecentErrors }
        "7" { Show-CostEstimation }
        "8" { Show-AlarmStatus }
        "9" { Open-Dashboard }
        "0" { Write-Host "Exiting..."; exit 0 }
        default { Write-Host "Invalid option" -ForegroundColor Red }
    }
    
    Write-Host ""
    Read-Host "Press Enter to continue"
}
