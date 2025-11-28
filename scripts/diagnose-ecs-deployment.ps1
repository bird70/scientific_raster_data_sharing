# Diagnose ECS Deployment Issues
# Checks ECS service status, task failures, and logs

$ErrorActionPreference = "Continue"

$AWS_PROFILE = "DEVcloud"
$AWS_REGION = "ap-southeast-2"
$CLUSTER_NAME = "cloud-scientific-raster-sharing-ecs-cluster"

Write-Host "========================================" -ForegroundColor Green
Write-Host "ECS Deployment Diagnostics" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

# Get services
Write-Host "Checking ECS services..." -ForegroundColor Yellow
$services = aws ecs list-services --cluster $CLUSTER_NAME --region $AWS_REGION --profile $AWS_PROFILE --query 'serviceArns' --output json | ConvertFrom-Json

if ($services.Count -eq 0) {
    Write-Host "No services found in cluster" -ForegroundColor Red
    exit 1
}

foreach ($serviceArn in $services) {
    $serviceName = $serviceArn.Split('/')[-1]
    Write-Host ""
    Write-Host "Service: $serviceName" -ForegroundColor Cyan
    Write-Host "----------------------------------------" -ForegroundColor Cyan
    
    # Get service details
    $serviceInfo = aws ecs describe-services `
        --cluster $CLUSTER_NAME `
        --services $serviceName `
        --region $AWS_REGION `
        --profile $AWS_PROFILE `
        --query 'services[0]' `
        --output json | ConvertFrom-Json
    
    Write-Host "Status: $($serviceInfo.status)"
    Write-Host "Desired Count: $($serviceInfo.desiredCount)"
    Write-Host "Running Count: $($serviceInfo.runningCount)"
    Write-Host "Pending Count: $($serviceInfo.pendingCount)"
    
    # Check deployments
    Write-Host ""
    Write-Host "Deployments:" -ForegroundColor Yellow
    foreach ($deployment in $serviceInfo.deployments) {
        Write-Host "  - Status: $($deployment.status)"
        Write-Host "    Rollout: $($deployment.rolloutState)"
        Write-Host "    Running: $($deployment.runningCount) / Desired: $($deployment.desiredCount)"
        Write-Host "    Failed: $($deployment.failedTasks)"
        if ($deployment.rolloutStateReason) {
            Write-Host "    Reason: $($deployment.rolloutStateReason)" -ForegroundColor Yellow
        }
    }
    
    # Check recent events
    Write-Host ""
    Write-Host "Recent Events:" -ForegroundColor Yellow
    $serviceInfo.events | Select-Object -First 5 | ForEach-Object {
        $timestamp = $_.createdAt
        $message = $_.message
        Write-Host "  [$timestamp] $message"
    }
    
    # Get tasks
    Write-Host ""
    Write-Host "Checking tasks..." -ForegroundColor Yellow
    $taskArns = aws ecs list-tasks `
        --cluster $CLUSTER_NAME `
        --service-name $serviceName `
        --region $AWS_REGION `
        --profile $AWS_PROFILE `
        --query 'taskArns' `
        --output json | ConvertFrom-Json
    
    if ($taskArns.Count -gt 0) {
        $tasks = aws ecs describe-tasks `
            --cluster $CLUSTER_NAME `
            --tasks $taskArns `
            --region $AWS_REGION `
            --profile $AWS_PROFILE `
            --query 'tasks' `
            --output json | ConvertFrom-Json
        
        foreach ($task in $tasks | Select-Object -First 3) {
            $taskId = $task.taskArn.Split('/')[-1]
            Write-Host "  Task: $taskId"
            Write-Host "    Status: $($task.lastStatus)"
            Write-Host "    Health: $($task.healthStatus)"
            Write-Host "    Started: $($task.startedAt)"
            
            # Check for stopped reason
            if ($task.stoppedReason) {
                Write-Host "    Stopped Reason: $($task.stoppedReason)" -ForegroundColor Red
            }
            
            # Check container status
            foreach ($container in $task.containers) {
                Write-Host "    Container: $($container.name)"
                Write-Host "      Status: $($container.lastStatus)"
                if ($container.exitCode) {
                    Write-Host "      Exit Code: $($container.exitCode)" -ForegroundColor Red
                }
                if ($container.reason) {
                    Write-Host "      Reason: $($container.reason)" -ForegroundColor Red
                }
            }
        }
    } else {
        Write-Host "  No tasks found" -ForegroundColor Yellow
    }
    
    # Check stopped tasks (failures)
    Write-Host ""
    Write-Host "Checking stopped tasks (recent failures)..." -ForegroundColor Yellow
    $stoppedTasks = aws ecs list-tasks `
        --cluster $CLUSTER_NAME `
        --service-name $serviceName `
        --desired-status STOPPED `
        --region $AWS_REGION `
        --profile $AWS_PROFILE `
        --query 'taskArns' `
        --output json | ConvertFrom-Json
    
    if ($stoppedTasks.Count -gt 0) {
        $recentStopped = aws ecs describe-tasks `
            --cluster $CLUSTER_NAME `
            --tasks ($stoppedTasks | Select-Object -First 3) `
            --region $AWS_REGION `
            --profile $AWS_PROFILE `
            --query 'tasks' `
            --output json | ConvertFrom-Json
        
        foreach ($task in $recentStopped) {
            $taskId = $task.taskArn.Split('/')[-1]
            Write-Host "  Stopped Task: $taskId" -ForegroundColor Red
            Write-Host "    Stopped At: $($task.stoppedAt)"
            Write-Host "    Stopped Reason: $($task.stoppedReason)"
            
            foreach ($container in $task.containers) {
                if ($container.exitCode -ne 0) {
                    Write-Host "    Container: $($container.name) - Exit Code: $($container.exitCode)" -ForegroundColor Red
                    if ($container.reason) {
                        Write-Host "      Reason: $($container.reason)"
                    }
                }
            }
        }
    } else {
        Write-Host "  No stopped tasks found"
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "Diagnostics Complete" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "To check logs for a specific task:" -ForegroundColor Cyan
Write-Host "  aws logs tail /ecs/cloud-scientific-raster-sharing --since 30m --follow --profile $AWS_PROFILE" -ForegroundColor White
Write-Host ""
Write-Host "To force a new deployment:" -ForegroundColor Cyan
Write-Host "  aws ecs update-service --cluster $CLUSTER_NAME --service SERVICE_NAME --force-new-deployment --profile $AWS_PROFILE" -ForegroundColor White
Write-Host ""
