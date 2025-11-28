#!/usr/bin/env pwsh
# Debug Step Functions Ingestion Pipeline
# This script starts an execution and retrieves debugging information

$env:AWS_PROFILE = "DEVcloud"

$STATE_MACHINE_ARN = "arn:aws:states:ap-southeast-2:123456789101:stateMachine:cloud-scientific-raster-sharing-ingestion-pipeline"
$BUCKET = "cloud-scientific-raster-sharing-raw-2e6c448c"
$TEST_FILE = "ingestion/test-file_MC_SST.nc"  # Using the real NetCDF file

Write-Host "=== Starting Step Functions Execution ===" -ForegroundColor Green

# Start execution
$timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$executionName = "debug-test-$timestamp"
$eventTime = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
$input = '{"bucket": "' + $BUCKET + '", "key": "' + $TEST_FILE + '", "metadata": {"source": "Debug script", "event_time": "' + $eventTime + '"}}'

Write-Host "Starting execution: $executionName"
Write-Host "Input: $input"
$execution = aws stepfunctions start-execution --state-machine-arn $STATE_MACHINE_ARN --name $executionName --input $input | ConvertFrom-Json
$executionArn = $execution.executionArn

Write-Host "Execution ARN: $executionArn"
Write-Host "Waiting for execution to complete..." -ForegroundColor Yellow

# Wait for completion (max 5 minutes)
$maxWait = 300
$waited = 0
do {
    Start-Sleep 10
    $waited += 10
    $status = aws stepfunctions describe-execution --execution-arn $executionArn | ConvertFrom-Json
    Write-Host "Status: $($status.status) (waited ${waited}s)"
} while ($status.status -eq "RUNNING" -and $waited -lt $maxWait)

Write-Host "`n=== Execution Status ===" -ForegroundColor Green
aws stepfunctions describe-execution --execution-arn $executionArn

Write-Host "`n=== Execution History ===" -ForegroundColor Green
$history = aws stepfunctions get-execution-history --execution-arn $executionArn --max-items 20 | ConvertFrom-Json

# Extract task ARNs from failed tasks
$failedTasks = $history.events | Where-Object { $_.type -eq "TaskFailed" }
if ($failedTasks) {
    Write-Host "`n=== Failed Task Details ===" -ForegroundColor Red
    foreach ($task in $failedTasks) {
        Write-Host "Task failed with error: $($task.taskFailedEventDetails.error)"
        
        # Extract task ID from the cause (JSON)
        try {
            $cause = $task.taskFailedEventDetails.cause | ConvertFrom-Json
            if ($cause.TaskArn) {
                $taskId = $cause.TaskArn.Split('/')[-1]
                Write-Host "Task ID: $taskId"
                
                # Get logs
                Write-Host "`n=== CloudWatch Logs ===" -ForegroundColor Yellow
                $logStream = "ecs/converter/$taskId"
                
                # Get log events
                $startTime = [DateTimeOffset]::FromUnixTimeMilliseconds($cause.StartedAt).ToUnixTimeMilliseconds()
                $endTime = [DateTimeOffset]::FromUnixTimeMilliseconds($cause.StoppedAt).ToUnixTimeMilliseconds()
                
                Write-Host "Fetching logs from stream: $logStream"
                aws logs get-log-events --log-group-name "/ecs/zarr-conversion" --log-stream-name $logStream --start-time $startTime --end-time $endTime
            }
        }
        catch {
            Write-Host "Could not parse task details: $_"
        }
    }
}

Write-Host "`n=== Full Execution History ===" -ForegroundColor Green
aws stepfunctions get-execution-history --execution-arn $executionArn --max-items 20

Write-Host "`n=== Debug Complete ===" -ForegroundColor Green
Write-Host "Execution ARN: $executionArn"