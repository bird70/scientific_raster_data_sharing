# Batch Upload NetCDF Files with Monitoring
# Uploads NetCDF files to S3 for ingestion pipeline processing

param(
    [Parameter(Mandatory=$true)]
    [string]$LocalFolder,
    
    [Parameter(Mandatory=$false)]
    [int]$BatchSize = 0,  # 0 = upload all at once
    
    [Parameter(Mandatory=$false)]
    [int]$DelayBetweenBatches = 120  # seconds
)

$ErrorActionPreference = "Continue"

# Configuration
$AWS_PROFILE = "DEVcloud"
$AWS_REGION = "ap-southeast-2"
$S3_BUCKET = "cloud-scientific-raster-sharing-raw-2e6c448c"
$S3_PREFIX = "ingestion"

Write-Host "========================================" -ForegroundColor Green
Write-Host "Batch NetCDF Upload" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

# Get all NetCDF files
$files = Get-ChildItem -Path $LocalFolder -Filter "*.nc" -File
$totalFiles = $files.Count

if ($totalFiles -eq 0) {
    Write-Host "No NetCDF files found in $LocalFolder" -ForegroundColor Red
    exit 1
}

Write-Host "Found $totalFiles NetCDF files" -ForegroundColor Cyan
Write-Host "Target: s3://$S3_BUCKET/$S3_PREFIX/" -ForegroundColor Cyan
Write-Host ""

# Confirm upload
$confirm = Read-Host "Upload $totalFiles files? (yes/no)"
if ($confirm -ne "yes") {
    Write-Host "Upload cancelled" -ForegroundColor Yellow
    exit 0
}

# Upload function
function Upload-File {
    param($file)
    
    $fileName = $file.Name
    $s3Key = "$S3_PREFIX/$fileName"
    
    try {
        aws s3 cp $file.FullName "s3://$S3_BUCKET/$s3Key" --profile $AWS_PROFILE 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  checkmark Uploaded: $fileName" -ForegroundColor Green
            return $true
        } else {
            Write-Host "  x Failed: $fileName" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "  x Error: $fileName - $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Upload files
$startTime = Get-Date
$successCount = 0
$failCount = 0

if ($BatchSize -eq 0) {
    # Upload all at once
    Write-Host "Uploading all $totalFiles files..." -ForegroundColor Yellow
    Write-Host ""
    
    foreach ($file in $files) {
        if (Upload-File $file) {
            $successCount++
        } else {
            $failCount++
        }
    }
} else {
    # Upload in batches
    $batchCount = [Math]::Ceiling($totalFiles / $BatchSize)
    Write-Host "Uploading in $batchCount batches of $BatchSize files..." -ForegroundColor Yellow
    Write-Host ""
    
    for ($i = 0; $i -lt $totalFiles; $i += $BatchSize) {
        $batchNum = [Math]::Floor($i / $BatchSize) + 1
        $batch = $files[$i..([Math]::Min($i + $BatchSize - 1, $totalFiles - 1))]
        
        Write-Host "Batch $batchNum of $batchCount ($($batch.Count) files):" -ForegroundColor Cyan
        
        foreach ($file in $batch) {
            if (Upload-File $file) {
                $successCount++
            } else {
                $failCount++
            }
        }
        
        if ($i + $BatchSize -lt $totalFiles) {
            Write-Host ""
            Write-Host "Waiting $DelayBetweenBatches seconds before next batch..." -ForegroundColor Yellow
            Start-Sleep -Seconds $DelayBetweenBatches
            Write-Host ""
        }
    }
}

$endTime = Get-Date
$duration = $endTime - $startTime

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "Upload Complete" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Total files: $totalFiles" -ForegroundColor Cyan
Write-Host "Successful: $successCount" -ForegroundColor Green
Write-Host "Failed: $failCount" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "Green" })
Write-Host "Duration: $($duration.ToString('mm\:ss'))" -ForegroundColor Cyan
Write-Host ""

# Monitor Step Functions
Write-Host "Monitoring Step Functions executions..." -ForegroundColor Yellow
Write-Host "Waiting 30 seconds for executions to start..." -ForegroundColor Cyan
Start-Sleep -Seconds 30

try {
    $stateMachineArn = aws stepfunctions list-state-machines `
        --profile $AWS_PROFILE `
        --region $AWS_REGION `
        --query "stateMachines[?contains(name, 'cloud-scientific-raster-sharing-ingestion')].stateMachineArn" `
        --output text
    
    if ($stateMachineArn) {
        $runningCount = (aws stepfunctions list-executions `
            --state-machine-arn $stateMachineArn `
            --status-filter RUNNING `
            --profile $AWS_PROFILE `
            --region $AWS_REGION `
            --query 'executions | length(@)' `
            --output text)
        
        Write-Host "Running executions: $runningCount" -ForegroundColor Cyan
        
        $succeededCount = (aws stepfunctions list-executions `
            --state-machine-arn $stateMachineArn `
            --status-filter SUCCEEDED `
            --max-results 1000 `
            --profile $AWS_PROFILE `
            --region $AWS_REGION `
            --query 'executions | length(@)' `
            --output text)
        
        Write-Host "Succeeded (recent): $succeededCount" -ForegroundColor Green
    }
} catch {
    Write-Host "Could not fetch Step Functions status" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Monitor progress with:" -ForegroundColor Cyan
Write-Host "  ./scripts/monitor-ingestion-pipeline.ps1" -ForegroundColor White
Write-Host ""
