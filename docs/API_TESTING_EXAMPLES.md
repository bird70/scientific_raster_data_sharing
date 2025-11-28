# API Testing Examples

## Base URL
```
http://cloud-sciraster-alb-1212121212.ap-southeast-2.elb.amazonaws.com
```

## Core Endpoints

### 1. Health Check
```bash
curl "http://cloud-sciraster-alb-1212121212.ap-southeast-2.elb.amazonaws.com/health"
# Expected: {"status":"ok"}
```

### 2. API Documentation
```bash
curl "http://cloud-sciraster-alb-1212121212.ap-southeast-2.elb.amazonaws.com/docs"
# Opens FastAPI interactive documentation
```

### 3. Collections (STAC Catalog)
```bash
curl "http://cloud-sciraster-alb-1212121212.ap-southeast-2.elb.amazonaws.com/api/collections"
# Expected: {"collections": [...]} or {"collections": []} if no data ingested yet
```

### 4. Available Variables
```bash
curl "http://cloud-sciraster-alb-1212121212.ap-southeast-2.elb.amazonaws.com/api/variables"
# Expected: {"variables": [{"name": "temperature", "count": 5}, ...]}
```

### 4. Root Information
```bash
curl "http://cloud-sciraster-alb-1212121212.ap-southeast-2.elb.amazonaws.com/"
# Shows API information and available endpoints
```

### 5. Metrics (Prometheus Format)
```bash
curl "http://cloud-sciraster-alb-1212121212.ap-southeast-2.elb.amazonaws.com/metrics"
# Shows application metrics in Prometheus format
```

## Data Ingestion Testing

### Upload Test NetCDF File
```bash
# Upload to trigger ingestion pipeline
aws s3 cp data/your-data.nc s3://cloud-scientific-raster-sharing-raw-2e6c448c/ingestion/test-$(date +%s).nc

# Monitor Step Functions execution
aws stepfunctions list-executions \
  --state-machine-arn arn:aws:states:ap-southeast-2:123456789101:stateMachine:cloud-scientific-raster-sharing-ingestion-pipeline \
  --max-items 5
```

### Check Processing Results
```bash
# Check if collections were created
curl "http://cloud-sciraster-alb-1212121212.ap-southeast-2.elb.amazonaws.com/api/collections"

# Check OpenSearch index
curl -s "https://vpc-cloud-sciraster-stac-aaaabbbbbcccccddddd1231231.ap-southeast-2.es.amazonaws.com/stac/_count"
```

## API Endpoints (After Data Ingestion)

### Timeseries Data
```bash
# First, get available variables
curl "http://cloud-sciraster-alb-1212121212.ap-southeast-2.elb.amazonaws.com/api/variables"

# Then query timeseries with a valid variable name
curl "http://cloud-sciraster-alb-1212121212.ap-southeast-2.elb.amazonaws.com/api/timeseries?lon=150&lat=-33&start=2024-01-01T00:00:00Z&end=2024-01-31T23:59:59Z&variable=temperature"

# Check required parameters
curl "http://cloud-sciraster-alb-1212121212.ap-southeast-2.elb.amazonaws.com/api/timeseries?lon=150&lat=-33&variable=temperature"
# Expected: {"detail":[{"type":"missing","loc":["query","start"],"msg":"Field required"},...]}
```

### Map Tiles
```bash
# Format: /tiles/{collection}/{z}/{x}/{y}.png
curl "http://cloud-sciraster-alb-1212121212.ap-southeast-2.elb.amazonaws.com/tiles/your-collection/10/512/512.png" -o tile.png
```

## Troubleshooting

### Common Issues

1. **Internal Server Error on /api/timeseries**
   - Missing required parameters (start, end)
   - No data ingested yet
   - Check logs: `aws logs tail /ecs/timeseries-service --follow`

2. **Empty Collections Response**
   - No data has been ingested yet
   - Upload NetCDF file to S3 raw bucket with `ingestion/` prefix
   - Wait for Step Functions to complete processing

3. **404 Not Found**
   - Check ALB routing rules
   - Verify service is running: `aws ecs describe-services --cluster cloud-scientific-raster-sharing-ecs-cluster --services tiles-service timeseries-service`

### Monitoring Commands

```bash
# Check ECS service status
aws ecs describe-services \
  --cluster cloud-scientific-raster-sharing-ecs-cluster \
  --services tiles-service timeseries-service

# Check task health
aws ecs list-tasks \
  --cluster cloud-scientific-raster-sharing-ecs-cluster \
  --service-name tiles-service

# View logs
aws logs tail /ecs/tiles-service --follow
aws logs tail /ecs/timeseries-service --follow

# Check ALB target health
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:ap-southeast-2:123456789101:targetgroup/cloud-sciraster-tiles-tg/158098eae867d5d2
```

## Expected Responses

### Healthy System
- `/health` → `{"status":"ok"}`
- `/api/collections` → `{"collections":[...]}` (after data ingestion)
- `/metrics` → Prometheus metrics starting with `# HELP`
- `/docs` → HTML FastAPI documentation page

### Before Data Ingestion
- `/api/collections` → `{"collections":[]}`
- `/api/timeseries` → Validation errors for missing parameters
- `/tiles/*` → 404 or empty responses

### After Data Ingestion
- `/api/collections` → List of available collections
- `/api/timeseries` → Time series data (with proper parameters)
- `/tiles/*` → PNG tile images