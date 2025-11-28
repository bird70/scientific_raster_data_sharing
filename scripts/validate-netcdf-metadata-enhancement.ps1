# Validate NetCDF Metadata Enhancement Deployment
# This script validates that the CRS detection and metadata extraction features are working

$ErrorActionPreference = "Stop"

# Configuration
$AWS_PROFILE = "DEVcloud"
$AWS_REGION = "ap-southeast-2"
$CLUSTER_NAME = "cloud-scientific-raster-sharing-cluster"

Write-Host "========================================" -ForegroundColor Green
Write-Host "NetCDF Metadata Enhancement Validation" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

# Step 1: Check ECS service status
Write-Host "Step 1: Checking ECS service status..." -ForegroundColor Yellow
try {
    $services = aws ecs list-services `
        --cluster $CLUSTER_NAME `
        --region $AWS_REGION `
        --profile $AWS_PROFILE `
        --query 'serviceArns' `
        --output json | ConvertFrom-Json
    
    if ($services.Count -eq 0) {
        Write-Host "✗ No services found in cluster" -ForegroundColor Red
        exit 1
    }
    
    foreach ($serviceArn in $services) {
        $serviceName = $serviceArn.Split('/')[-1]
        
        $serviceInfo = aws ecs describe-services `
            --cluster $CLUSTER_NAME `
            --services $serviceName `
            --region $AWS_REGION `
            --profile $AWS_PROFILE `
            --query 'services[0]' `
            --output json | ConvertFrom-Json
        
        $runningCount = $serviceInfo.runningCount
        $desiredCount = $serviceInfo.desiredCount
        $status = $serviceInfo.status
        
        Write-Host "  Service: $serviceName" -ForegroundColor Cyan
        Write-Host "    Status: $status"
        Write-Host "    Running: $runningCount / $desiredCount"
        
        if ($runningCount -eq $desiredCount -and $status -eq "ACTIVE") {
            Write-Host "    ✓ Service is healthy" -ForegroundColor Green
        } else {
            Write-Host "    ⚠ Service may be updating or unhealthy" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "✗ Failed to check ECS services" -ForegroundColor Red
    Write-Host $_.Exception.Message
}
Write-Host ""

# Step 2: Check CloudWatch logs for CRS detection
Write-Host "Step 2: Checking CloudWatch logs for CRS detection..." -ForegroundColor Yellow
Write-Host "Looking for recent CRS detection log entries..."
Write-Host ""

try {
    $logGroups = @(
        "/ecs/zarr-converter",
        "/ecs/cloud-scientific-raster-sharing"
    )
    
    $foundLogs = $false
    
    foreach ($logGroup in $logGroups) {
        try {
            # Get recent log events
            $logStreams = aws logs describe-log-streams `
                --log-group-name $logGroup `
                --order-by LastEventTime `
                --descending `
                --max-items 5 `
                --region $AWS_REGION `
                --profile $AWS_PROFILE `
                --query 'logStreams[*].logStreamName' `
                --output json | ConvertFrom-Json
            
            if ($logStreams.Count -gt 0) {
                Write-Host "  Log group: $logGroup" -ForegroundColor Cyan
                
                # Check first log stream for CRS-related messages
                $logStream = $logStreams[0]
                $events = aws logs get-log-events `
                    --log-group-name $logGroup `
                    --log-stream-name $logStream `
                    --limit 100 `
                    --region $AWS_REGION `
                    --profile $AWS_PROFILE `
                    --query 'events[*].message' `
                    --output json | ConvertFrom-Json
                
                # Look for CRS-related messages
                $crsMessages = $events | Where-Object { 
                    $_ -match "CRS|coordinate|transform|metadata|collection" 
                }
                
                if ($crsMessages.Count -gt 0) {
                    Write-Host "    ✓ Found $($crsMessages.Count) CRS/metadata related log entries" -ForegroundColor Green
                    Write-Host "    Recent messages:" -ForegroundColor Cyan
                    $crsMessages | Select-Object -First 3 | ForEach-Object {
                        $msg = $_ -replace "`n", " " -replace "`r", ""
                        if ($msg.Length -gt 100) {
                            $msg = $msg.Substring(0, 100) + "..."
                        }
                        Write-Host "      - $msg"
                    }
                    $foundLogs = $true
                } else {
                    Write-Host "    ⚠ No CRS/metadata messages found in recent logs" -ForegroundColor Yellow
                }
            }
        } catch {
            # Log group might not exist yet
            continue
        }
    }
    
    if (-not $foundLogs) {
        Write-Host "  ⚠ No CRS detection logs found yet" -ForegroundColor Yellow
        Write-Host "  This is normal if no files have been ingested since deployment"
    }
} catch {
    Write-Host "✗ Failed to check CloudWatch logs" -ForegroundColor Red
    Write-Host $_.Exception.Message
}
Write-Host ""

# Step 3: Check S3 buckets
Write-Host "Step 3: Checking S3 buckets..." -ForegroundColor Yellow
try {
    $bucketPrefix = "cloud-scientific-raster-sharing"
    
    $buckets = aws s3api list-buckets `
        --profile $AWS_PROFILE `
        --query "Buckets[?starts_with(Name, '$bucketPrefix')].Name" `
        --output json | ConvertFrom-Json
    
    if ($buckets.Count -gt 0) {
        Write-Host "  ✓ Found $($buckets.Count) project buckets" -ForegroundColor Green
        foreach ($bucket in $buckets) {
            Write-Host "    - $bucket"
        }
    } else {
        Write-Host "  ✗ No project buckets found" -ForegroundColor Red
    }
} catch {
    Write-Host "✗ Failed to check S3 buckets" -ForegroundColor Red
    Write-Host $_.Exception.Message
}
Write-Host ""

# Step 4: Check DynamoDB table
Write-Host "Step 4: Checking DynamoDB STAC table..." -ForegroundColor Yellow
try {
    $tableName = "cloud-scientific-raster-sharing-stac"
    
    $tableInfo = aws dynamodb describe-table `
        --table-name $tableName `
        --region $AWS_REGION `
        --profile $AWS_PROFILE `
        --query 'Table' `
        --output json | ConvertFrom-Json
    
    Write-Host "  ✓ STAC table exists" -ForegroundColor Green
    Write-Host "    Status: $($tableInfo.TableStatus)"
    Write-Host "    Item count: $($tableInfo.ItemCount)"
    
    # Check for recent items with metadata
    $items = aws dynamodb scan `
        --table-name $tableName `
        --limit 5 `
        --region $AWS_REGION `
        --profile $AWS_PROFILE `
        --query 'Items[*]' `
        --output json | ConvertFrom-Json
    
    if ($items.Count -gt 0) {
        Write-Host "    ✓ Found $($items.Count) items in table" -ForegroundColor Green
        
        # Check if any items have the new metadata fields
        $itemsWithMetadata = $items | Where-Object {
            $_.properties.M.variables -or $_.properties.M.collections
        }
        
        if ($itemsWithMetadata.Count -gt 0) {
            Write-Host "    ✓ Found items with enhanced metadata" -ForegroundColor Green
        } else {
            Write-Host "    ⚠ No items with enhanced metadata found yet" -ForegroundColor Yellow
            Write-Host "    Re-ingest files to populate metadata"
        }
    } else {
        Write-Host "    ⚠ No items in table yet" -ForegroundColor Yellow
    }
} catch {
    Write-Host "✗ Failed to check DynamoDB table" -ForegroundColor Red
    Write-Host $_.Exception.Message
}
Write-Host ""

Write-Host "========================================" -ForegroundColor Green
Write-Host "Validation Complete" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps to fully validate:" -ForegroundColor Cyan
Write-Host "1. Upload a test NetCDF file with projected CRS (e.g., NZTM2000)"
Write-Host "2. Monitor CloudWatch logs for CRS detection messages"
Write-Host "3. Check DynamoDB for STAC items with correct bounding boxes"
Write-Host "4. Query STAC API to verify metadata is searchable"
Write-Host ""
Write-Host "Test file upload command:" -ForegroundColor Cyan
Write-Host "  aws s3 cp data/A2002070120230731_MC_SST_std_coastal_v05.nc s3://<bucket>/ingestion/ --profile $AWS_PROFILE"
Write-Host ""
Write-Host "Monitor logs command:" -ForegroundColor Cyan
Write-Host "  aws logs tail /ecs/zarr-converter --follow --profile $AWS_PROFILE"
Write-Host ""
