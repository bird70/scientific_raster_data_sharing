# Verification script for DynamoDB-only STAC backend
# This script verifies that DynamoDB is working correctly and no OpenSearch dependencies remain

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "DynamoDB STAC Backend Verification" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# Get Terraform outputs
Push-Location terraform
$ALB_DNS = terraform output -raw alb_dns_name 2>$null
$DYNAMODB_TABLE = terraform output -raw dynamodb_stac_table_name 2>$null
Pop-Location

if (-not $ALB_DNS) {
    Write-Host "✗ Failed to get ALB DNS name from Terraform" -ForegroundColor Red
    exit 1
}

if (-not $DYNAMODB_TABLE) {
    Write-Host "✗ Failed to get DynamoDB table name from Terraform" -ForegroundColor Red
    exit 1
}

Write-Host "ALB DNS: $ALB_DNS"
Write-Host "DynamoDB Table: $DYNAMODB_TABLE"
Write-Host ""

# Check 1: Verify API health endpoint
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Check 1: API Health Endpoint" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
try {
    $response = Invoke-WebRequest -Uri "http://$ALB_DNS/health" -UseBasicParsing -TimeoutSec 10
    if ($response.StatusCode -eq 200) {
        Write-Host "✓ API health endpoint responding (HTTP 200)" -ForegroundColor Green
    } else {
        Write-Host "✗ API health endpoint failed (HTTP $($response.StatusCode))" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "✗ API health endpoint failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Check 2: Verify DynamoDB table exists and is active
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Check 2: DynamoDB Table Status" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
try {
    $tableInfo = aws dynamodb describe-table --table-name $DYNAMODB_TABLE --output json 2>$null | ConvertFrom-Json
    $tableStatus = $tableInfo.Table.TableStatus
    
    if ($tableStatus -eq "ACTIVE") {
        Write-Host "✓ DynamoDB table is ACTIVE" -ForegroundColor Green
        
        # Get item count
        $scanResult = aws dynamodb scan --table-name $DYNAMODB_TABLE --select COUNT --output json 2>$null | ConvertFrom-Json
        $itemCount = $scanResult.Count
        Write-Host "  Items in table: $itemCount"
        
        # Check GSI status
        if ($tableInfo.Table.GlobalSecondaryIndexes) {
            Write-Host "  Global Secondary Indexes:"
            foreach ($gsi in $tableInfo.Table.GlobalSecondaryIndexes) {
                if ($gsi.IndexStatus -eq "ACTIVE") {
                    Write-Host "    ✓ $($gsi.IndexName): $($gsi.IndexStatus)" -ForegroundColor Green
                } else {
                    Write-Host "    ✗ $($gsi.IndexName): $($gsi.IndexStatus)" -ForegroundColor Red
                }
            }
        }
    } else {
        Write-Host "✗ DynamoDB table status: $tableStatus" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "✗ Failed to describe DynamoDB table: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Check 3: Verify STAC backend configuration
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Check 3: STAC Backend Configuration" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Push-Location terraform
$STAC_BACKEND = (Get-Content terraform.tfvars | Select-String 'stac_backend\s*=\s*"([^"]+)"').Matches.Groups[1].Value
Pop-Location

Write-Host "Current STAC_BACKEND: $STAC_BACKEND"
if ($STAC_BACKEND -eq "dynamodb") {
    Write-Host "✓ STAC backend is set to 'dynamodb' (correct)" -ForegroundColor Green
} elseif ($STAC_BACKEND -eq "dual") {
    Write-Host "⚠ STAC backend is set to 'dual' (migration mode)" -ForegroundColor Yellow
    Write-Host "  This is acceptable but should be changed to 'dynamodb' after verification"
} else {
    Write-Host "✗ STAC backend is set to '$STAC_BACKEND' (unexpected)" -ForegroundColor Red
}
Write-Host ""

# Check 4: Check CloudWatch logs for errors
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Check 4: CloudWatch Logs (Recent Errors)" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Checking ECS task logs for DynamoDB errors..."

$startTime = [DateTimeOffset]::UtcNow.AddHours(-1).ToUnixTimeMilliseconds()

# Check tiles service logs
$TILES_LOG_GROUP = "/ecs/tiles-service"
try {
    $tilesErrors = aws logs filter-log-events `
        --log-group-name $TILES_LOG_GROUP `
        --start-time $startTime `
        --filter-pattern "ERROR" `
        --output json 2>$null | ConvertFrom-Json
    
    $relevantErrors = $tilesErrors.events | Where-Object { $_.message -match "dynamodb|opensearch" }
    
    if (-not $relevantErrors) {
        Write-Host "✓ No DynamoDB/OpenSearch errors in tiles service logs (last hour)" -ForegroundColor Green
    } else {
        Write-Host "⚠ Found errors in tiles service logs:" -ForegroundColor Yellow
        $relevantErrors | Select-Object -First 5 | ForEach-Object { Write-Host "  $($_.message)" }
    }
} catch {
    Write-Host "⚠ Could not check tiles service logs: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Check timeseries service logs
$TIMESERIES_LOG_GROUP = "/ecs/timeseries-service"
try {
    $timeseriesErrors = aws logs filter-log-events `
        --log-group-name $TIMESERIES_LOG_GROUP `
        --start-time $startTime `
        --filter-pattern "ERROR" `
        --output json 2>$null | ConvertFrom-Json
    
    $relevantErrors = $timeseriesErrors.events | Where-Object { $_.message -match "dynamodb|opensearch" }
    
    if (-not $relevantErrors) {
        Write-Host "✓ No DynamoDB/OpenSearch errors in timeseries service logs (last hour)" -ForegroundColor Green
    } else {
        Write-Host "⚠ Found errors in timeseries service logs:" -ForegroundColor Yellow
        $relevantErrors | Select-Object -First 5 | ForEach-Object { Write-Host "  $($_.message)" }
    }
} catch {
    Write-Host "⚠ Could not check timeseries service logs: $($_.Exception.Message)" -ForegroundColor Yellow
}
Write-Host ""

# Check 5: Test STAC item retrieval (if items exist)
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Check 5: STAC Item Retrieval Test" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
if ($itemCount -gt 0) {
    Write-Host "Testing STAC item retrieval from DynamoDB..."
    
    # Get a sample item ID from DynamoDB
    try {
        $sampleItem = aws dynamodb scan --table-name $DYNAMODB_TABLE --limit 1 --output json 2>$null | ConvertFrom-Json
        $sampleId = $sampleItem.Items[0].id.S
        
        if ($sampleId) {
            Write-Host "Sample item ID: $sampleId"
            
            # Try to retrieve via API
            try {
                $apiResponse = Invoke-WebRequest -Uri "http://$ALB_DNS/api/stac/items/$sampleId" -UseBasicParsing -TimeoutSec 10
                if ($apiResponse.StatusCode -eq 200) {
                    Write-Host "✓ Successfully retrieved STAC item via API" -ForegroundColor Green
                }
            } catch {
                Write-Host "⚠ Could not retrieve STAC item via API: $($_.Exception.Message)" -ForegroundColor Yellow
                Write-Host "  This may be expected if STAC API endpoint is not configured"
            }
        } else {
            Write-Host "⚠ Could not get sample item ID from DynamoDB" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "⚠ Error scanning DynamoDB: $($_.Exception.Message)" -ForegroundColor Yellow
    }
} else {
    Write-Host "⚠ No items in DynamoDB table - skipping retrieval test" -ForegroundColor Yellow
    Write-Host "  Consider running ingestion pipeline to populate data"
}
Write-Host ""

# Check 6: Verify no OpenSearch environment variables in ECS tasks
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Check 6: OpenSearch Dependencies Check" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Checking ECS task definitions for OpenSearch environment variables..."

Push-Location terraform
$CLUSTER_NAME = terraform output -raw cluster_name 2>$null
Pop-Location

if ($CLUSTER_NAME) {
    try {
        $serviceInfo = aws ecs describe-services --cluster $CLUSTER_NAME --services tiles-service --output json 2>$null | ConvertFrom-Json
        $taskDefArn = $serviceInfo.services[0].taskDefinition
        
        if ($taskDefArn) {
            $taskDef = aws ecs describe-task-definition --task-definition $taskDefArn --output json 2>$null | ConvertFrom-Json
            $opensearchEnv = $taskDef.taskDefinition.containerDefinitions[0].environment | Where-Object { $_.name -eq "OPENSEARCH_HOST" }
            
            if (-not $opensearchEnv) {
                Write-Host "✓ No OPENSEARCH_HOST environment variable in tiles task definition" -ForegroundColor Green
            } else {
                Write-Host "⚠ OPENSEARCH_HOST environment variable still present in tiles task definition" -ForegroundColor Yellow
                Write-Host "  This should be removed after switching to DynamoDB-only mode"
            }
        }
    } catch {
        Write-Host "⚠ Could not check ECS task definitions: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}
Write-Host ""

# Check 7: Verify DynamoDB metrics
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Check 7: DynamoDB Metrics (Last Hour)" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Checking DynamoDB read/write activity..."

$endTime = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
$startTime = (Get-Date).AddHours(-1).ToString("yyyy-MM-ddTHH:mm:ss")

try {
    # Get read capacity units consumed
    $readMetrics = aws cloudwatch get-metric-statistics `
        --namespace AWS/DynamoDB `
        --metric-name ConsumedReadCapacityUnits `
        --dimensions Name=TableName,Value=$DYNAMODB_TABLE `
        --start-time $startTime `
        --end-time $endTime `
        --period 3600 `
        --statistics Sum `
        --output json 2>$null | ConvertFrom-Json
    
    $readCapacity = $readMetrics.Datapoints[0].Sum
    
    if ($readCapacity -and $readCapacity -gt 0) {
        Write-Host "✓ DynamoDB read activity detected ($readCapacity RCUs consumed)" -ForegroundColor Green
    } else {
        Write-Host "⚠ No DynamoDB read activity in last hour" -ForegroundColor Yellow
    }
} catch {
    Write-Host "⚠ Could not retrieve read metrics: $($_.Exception.Message)" -ForegroundColor Yellow
}

try {
    # Get write capacity units consumed
    $writeMetrics = aws cloudwatch get-metric-statistics `
        --namespace AWS/DynamoDB `
        --metric-name ConsumedWriteCapacityUnits `
        --dimensions Name=TableName,Value=$DYNAMODB_TABLE `
        --start-time $startTime `
        --end-time $endTime `
        --period 3600 `
        --statistics Sum `
        --output json 2>$null | ConvertFrom-Json
    
    $writeCapacity = $writeMetrics.Datapoints[0].Sum
    
    if ($writeCapacity -and $writeCapacity -gt 0) {
        Write-Host "✓ DynamoDB write activity detected ($writeCapacity WCUs consumed)" -ForegroundColor Green
    } else {
        Write-Host "⚠ No DynamoDB write activity in last hour" -ForegroundColor Yellow
    }
} catch {
    Write-Host "⚠ Could not retrieve write metrics: $($_.Exception.Message)" -ForegroundColor Yellow
}
Write-Host ""

# Summary
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Verification Summary" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "✓ = Passed"
Write-Host "⚠ = Warning (review recommended)"
Write-Host "✗ = Failed (action required)"
Write-Host ""
Write-Host "If all checks passed, you can proceed with:" -ForegroundColor Cyan
Write-Host "1. Update STAC_BACKEND to 'dynamodb' in terraform.tfvars (if currently 'dual')"
Write-Host "2. Run task 13.2 to remove OpenSearch from Terraform configuration"
Write-Host "3. Run task 13.3 to apply Terraform changes and delete OpenSearch"
Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
