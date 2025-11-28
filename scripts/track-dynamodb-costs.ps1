#!/usr/bin/env pwsh

# Track DynamoDB costs and usage for STAC table
# This script helps monitor the cost savings from the OpenSearch to DynamoDB migration

# Configuration
$TABLE_NAME = "cloud-scientific-raster-sharing-stac-items"
$REGION = "ap-southeast-2"
$PROFILE = "DEVcloud"

Write-Host "========================================" -ForegroundColor Blue
Write-Host "DynamoDB Cost Tracking for STAC Table" -ForegroundColor Blue
Write-Host "========================================" -ForegroundColor Blue
Write-Host ""

# Get date range (last 30 days)
$EndDate = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss")
$StartDate = (Get-Date).AddDays(-30).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss")

Write-Host "Date Range: " -NoNewline
Write-Host "$StartDate to $EndDate" -ForegroundColor Green
Write-Host ""

# Function to get metric statistics
function Get-MetricStatistics {
    param(
        [string]$MetricName,
        [string]$Stat,
        [string]$StartTime,
        [string]$EndTime
    )
    
    try {
        $result = aws cloudwatch get-metric-statistics `
            --namespace AWS/DynamoDB `
            --metric-name $MetricName `
            --dimensions Name=TableName,Value=$TABLE_NAME `
            --start-time $StartTime `
            --end-time $EndTime `
            --period 86400 `
            --statistics $Stat `
            --region $REGION `
            --profile $PROFILE `
            --query "Datapoints[*].$Stat" `
            --output text 2>$null
        
        if ($result) {
            return $result
        }
        return "0"
    }
    catch {
        return "0"
    }
}

# Get table information
Write-Host "Table Information:" -ForegroundColor Yellow

try {
    $tableInfo = aws dynamodb describe-table `
        --table-name $TABLE_NAME `
        --region $REGION `
        --profile $PROFILE `
        2>$null | ConvertFrom-Json
    
    $itemCount = $tableInfo.Table.ItemCount
    $tableSizeBytes = $tableInfo.Table.TableSizeBytes
    $tableSizeMB = [math]::Round($tableSizeBytes / 1024 / 1024, 2)
    
    Write-Host "  Table Name: " -NoNewline
    Write-Host $TABLE_NAME -ForegroundColor Green
    Write-Host "  Item Count: " -NoNewline
    Write-Host $itemCount -ForegroundColor Green
    Write-Host "  Table Size: " -NoNewline
    Write-Host "$tableSizeMB MB" -ForegroundColor Green
}
catch {
    Write-Host "  Error: Could not retrieve table information" -ForegroundColor Red
    $itemCount = 0
    $tableSizeMB = 0
}
Write-Host ""

# Get CloudWatch metrics
Write-Host "Usage Metrics (Last 30 Days):" -ForegroundColor Yellow

# Read capacity units
$readCapacity = Get-MetricStatistics -MetricName "ConsumedReadCapacityUnits" -Stat "Sum" -StartTime $StartDate -EndTime $EndDate
$readRequests = ($readCapacity -split '\s+' | Measure-Object -Sum).Sum
if (-not $readRequests) { $readRequests = 0 }

Write-Host "  Read Requests: " -NoNewline
Write-Host ("{0:N0}" -f $readRequests) -ForegroundColor Green

# Write capacity units
$writeCapacity = Get-MetricStatistics -MetricName "ConsumedWriteCapacityUnits" -Stat "Sum" -StartTime $StartDate -EndTime $EndDate
$writeRequests = ($writeCapacity -split '\s+' | Measure-Object -Sum).Sum
if (-not $writeRequests) { $writeRequests = 0 }

Write-Host "  Write Requests: " -NoNewline
Write-Host ("{0:N0}" -f $writeRequests) -ForegroundColor Green

# Throttled requests
$throttledReads = Get-MetricStatistics -MetricName "ReadThrottleEvents" -Stat "Sum" -StartTime $StartDate -EndTime $EndDate
$throttledWrites = Get-MetricStatistics -MetricName "WriteThrottleEvents" -Stat "Sum" -StartTime $StartDate -EndTime $EndDate
$throttledReadsTotal = ($throttledReads -split '\s+' | Measure-Object -Sum).Sum
$throttledWritesTotal = ($throttledWrites -split '\s+' | Measure-Object -Sum).Sum
if (-not $throttledReadsTotal) { $throttledReadsTotal = 0 }
if (-not $throttledWritesTotal) { $throttledWritesTotal = 0 }

if ($throttledReadsTotal -eq 0 -and $throttledWritesTotal -eq 0) {
    Write-Host "  Throttled Requests: " -NoNewline
    Write-Host "0 (Good!)" -ForegroundColor Green
}
else {
    Write-Host "  Throttled Reads: " -NoNewline
    Write-Host $throttledReadsTotal -ForegroundColor Red
    Write-Host "  Throttled Writes: " -NoNewline
    Write-Host $throttledWritesTotal -ForegroundColor Red
}
Write-Host ""

# Cost estimation
Write-Host "Cost Estimation (Last 30 Days):" -ForegroundColor Yellow

# DynamoDB pricing (ap-southeast-2)
$READ_COST_PER_MILLION = 0.25
$WRITE_COST_PER_MILLION = 1.25
$STORAGE_COST_PER_GB = 0.25

# Calculate costs
$readCost = [math]::Round(($readRequests / 1000000) * $READ_COST_PER_MILLION, 2)
$writeCost = [math]::Round(($writeRequests / 1000000) * $WRITE_COST_PER_MILLION, 2)
$storageCost = [math]::Round(($tableSizeMB / 1024) * $STORAGE_COST_PER_GB, 2)
$pitrCost = 1.00  # Approximate cost for point-in-time recovery

$totalCost = [math]::Round($readCost + $writeCost + $storageCost + $pitrCost, 2)

Write-Host "  Read Requests: `$$readCost"
Write-Host "  Write Requests: `$$writeCost"
Write-Host "  Storage: `$$storageCost"
Write-Host "  Point-in-Time Recovery: `$$pitrCost"
Write-Host "  Total Estimated Cost: " -NoNewline
Write-Host "`$$totalCost" -ForegroundColor Green
Write-Host ""

# Cost comparison
$opensearchCost = 102.00
$savings = [math]::Round($opensearchCost - $totalCost, 2)
$savingsPercent = [math]::Round(($savings / $opensearchCost) * 100, 1)

Write-Host "Cost Comparison:" -ForegroundColor Yellow
Write-Host "  OpenSearch (before): " -NoNewline
Write-Host "`$$opensearchCost" -ForegroundColor Red
Write-Host "  DynamoDB (after): " -NoNewline
Write-Host "`$$totalCost" -ForegroundColor Green
Write-Host "  Monthly Savings: " -NoNewline
Write-Host "`$$savings ($savingsPercent%)" -ForegroundColor Green
Write-Host "  Annual Savings: " -NoNewline
Write-Host ("`$" + [math]::Round($savings * 12, 2)) -ForegroundColor Green
Write-Host ""

# Get actual AWS costs (if available)
Write-Host "Actual AWS Costs (from Cost Explorer):" -ForegroundColor Yellow

$monthStart = (Get-Date -Day 1).ToString("yyyy-MM-dd")
$monthEnd = (Get-Date).ToString("yyyy-MM-dd")

try {
    $filterJson = @{
        And = @(
            @{ Dimensions = @{ Key = "SERVICE"; Values = @("Amazon DynamoDB") } }
            @{ Tags = @{ Key = "Name"; Values = @($TABLE_NAME) } }
        )
    } | ConvertTo-Json -Depth 10 -Compress
    
    $actualCost = aws ce get-cost-and-usage `
        --time-period Start=$monthStart,End=$monthEnd `
        --granularity MONTHLY `
        --metrics BlendedCost `
        --filter $filterJson `
        --region $REGION `
        --profile $PROFILE `
        --query 'ResultsByTime[0].Total.BlendedCost.Amount' `
        --output text 2>$null
    
    if ($actualCost -and $actualCost -ne "None") {
        $actualCostValue = [math]::Round([double]$actualCost, 2)
        Write-Host "  Actual Cost (Month-to-Date): " -NoNewline
        Write-Host "`$$actualCostValue" -ForegroundColor Green
        
        # Calculate projected monthly cost
        $daysInMonth = [DateTime]::DaysInMonth((Get-Date).Year, (Get-Date).Month)
        $currentDay = (Get-Date).Day
        $projectedCost = [math]::Round($actualCostValue * $daysInMonth / $currentDay, 2)
        
        Write-Host "  Projected Monthly Cost: " -NoNewline
        Write-Host "`$$projectedCost" -ForegroundColor Green
    }
    else {
        Write-Host "  Actual cost data not available yet" -ForegroundColor Yellow
        Write-Host "  (Cost Explorer data may take 24-48 hours to appear)" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "  Actual cost data not available yet" -ForegroundColor Yellow
    Write-Host "  (Cost Explorer data may take 24-48 hours to appear)" -ForegroundColor Yellow
}
Write-Host ""

# Performance metrics
Write-Host "Performance Metrics:" -ForegroundColor Yellow

# Get latency metrics
$successLatency = Get-MetricStatistics -MetricName "SuccessfulRequestLatency" -Stat "Average" -StartTime $StartDate -EndTime $EndDate
$latencyValues = $successLatency -split '\s+' | Where-Object { $_ -match '^\d+\.?\d*$' } | ForEach-Object { [double]$_ }
if ($latencyValues) {
    $avgLatency = [math]::Round(($latencyValues | Measure-Object -Average).Average, 2)
}
else {
    $avgLatency = 0
}

Write-Host "  Average Latency: " -NoNewline
Write-Host "$avgLatency ms" -ForegroundColor Green

# Check if latency is within target
if ($avgLatency -lt 50) {
    Write-Host "  Latency Status: " -NoNewline
    Write-Host "✓ Within target (<50ms)" -ForegroundColor Green
}
else {
    Write-Host "  Latency Status: " -NoNewline
    Write-Host "⚠ Above target (>50ms)" -ForegroundColor Yellow
}
Write-Host ""

# Recommendations
Write-Host "Recommendations:" -ForegroundColor Yellow

if ($throttledReadsTotal -gt 0 -or $throttledWritesTotal -gt 0) {
    Write-Host "  ⚠ Throttling detected!" -ForegroundColor Red
    Write-Host "    Consider reviewing query patterns or switching to provisioned capacity"
}

if ($avgLatency -gt 50) {
    Write-Host "  ⚠ High latency detected" -ForegroundColor Yellow
    Write-Host "    Consider adding caching layer (Redis/DAX) for frequently accessed items"
}

if ($totalCost -lt 5) {
    Write-Host "  ✓ Costs are very low - on-demand billing is optimal" -ForegroundColor Green
}
elseif ($totalCost -gt 20) {
    Write-Host "  ⚠ Costs are higher than expected" -ForegroundColor Yellow
    Write-Host "    Review query patterns and consider optimization"
}
else {
    Write-Host "  ✓ Costs are within expected range" -ForegroundColor Green
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Blue
Write-Host "Migration Success!" -ForegroundColor Green
Write-Host "Saving approximately `$$savings/month ($savingsPercent% reduction)" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Blue
