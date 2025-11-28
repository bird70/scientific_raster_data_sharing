# Enhanced Smoke Tests with Data Ingestion

## Overview

The CI/CD pipeline now includes enhanced smoke tests that verify the complete data ingestion pipeline by uploading a test NetCDF file and validating the entire workflow.

## Test Stages

### 1. Basic Smoke Tests
- **Health endpoint**: Verifies API is responding
- **API docs endpoint**: Confirms FastAPI documentation is accessible  
- **Collections endpoint**: Tests collections API (empty response is OK)
- **Metrics endpoint**: Validates Prometheus metrics are exposed

### 2. Enhanced Smoke Tests with Data Ingestion
- **Test file upload**: Uploads `data/your-data.nc` to S3 raw bucket
- **Step Functions monitoring**: Checks ingestion pipeline execution
- **Collections verification**: Confirms collections are populated after ingestion
- **OpenSearch validation**: Verifies STAC documents are indexed

## Required GitHub Secrets

The enhanced tests require additional secrets:

```
S3_RAW_BUCKET=cloud-scientific-raster-sharing-raw-2e6c448c
STEP_FUNCTIONS_ARN=arn:aws:states:ap-southeast-2:123456789101:stateMachine:cloud-scientific-raster-sharing-ingestion-pipeline
OPENSEARCH_ENDPOINT=vpc-cloud-sciraster-stac-aaaabbbbbcccccddddd1231231.ap-southeast-2.es.amazonaws.com
ALB_URL=http://cloud-sciraster-alb-1212121212.ap-southeast-2.elb.amazonaws.com
```

## Test Flow

1. **Deploy services** → Wait for stabilization (60s)
2. **Basic smoke tests** → Verify core endpoints
3. **Upload test data** → `data/your-data.nc` → S3 raw bucket with `ingestion/` prefix
4. **Wait for processing** → Step Functions execution (180s)
5. **Verify ingestion** → Check Step Functions success
6. **Validate results** → Collections API and OpenSearch index

## Test Data

Uses the existing NetCDF file at `data/your-data.nc` which gets uploaded as:
```
s3://S3_RAW_BUCKET/ingestion/test-{timestamp}.nc
```

This triggers the complete ingestion pipeline:
- NetCDF → Zarr conversion
- Zarr → COG generation  
- STAC metadata creation
- OpenSearch indexing

## Monitoring

The enhanced tests provide detailed logging:
- File upload confirmation
- Step Functions execution status
- Collections API response
- OpenSearch document count
- Overall pipeline health

## Benefits

1. **End-to-end validation**: Tests complete data flow
2. **Real data processing**: Uses actual NetCDF file
3. **Pipeline verification**: Confirms Step Functions work
4. **Search validation**: Ensures OpenSearch indexing
5. **API confirmation**: Verifies collections are accessible

## Troubleshooting

### Test File Upload Fails
- Check S3_RAW_BUCKET secret is correct
- Verify AWS credentials have S3 write permissions
- Ensure `data/your-data.nc` exists in repository

### Step Functions Not Executing
- Check STEP_FUNCTIONS_ARN secret is correct
- Verify S3 bucket notification is configured
- Check Lambda trigger function logs

### OpenSearch Access Issues
- Verify OPENSEARCH_ENDPOINT secret is correct
- Check VPC security groups allow access
- Confirm OpenSearch domain is accessible

### Collections API Empty
- Wait longer for processing (may take >3 minutes)
- Check Step Functions execution in AWS console
- Verify STAC indexer Lambda function logs

## Manual Testing

You can manually test the enhanced flow:

```bash
# Upload test file
aws s3 cp data/your-data.nc s3://YOUR_RAW_BUCKET/ingestion/manual-test.nc

# Monitor Step Functions
aws stepfunctions list-executions --state-machine-arn YOUR_STEP_FUNCTIONS_ARN

# Check collections
curl http://YOUR_ALB_URL/api/collections

# Check OpenSearch
curl https://YOUR_OPENSEARCH_ENDPOINT/stac/_count
```