# Ingestion Pipeline Documentation

## Overview

The platform includes an automated data ingestion pipeline that converts uploaded NetCDF files into analysis-ready formats (Zarr and Cloud Optimized GeoTIFF) with automatic STAC metadata indexing.

**Current Implementation**: ECS-based (migrated from Lambda for cost savings and reliability)

## Architecture

```
S3 Raw Bucket → Lambda Trigger → Step Functions → ECS Tasks → S3 Output Buckets + OpenSearch
```

**Key Innovation**: Uses ResultSelector pattern for data flow between ECS tasks (see [ResultSelector Data Flow Pattern](RESULTSELECTOR_DATA_FLOW_PATTERN.md))

### Components

1. **S3 Raw Bucket**: Upload location for NetCDF files (`s3://bucket/ingestion/`)
2. **Lambda Trigger**: Detects new uploads and starts Step Functions execution
3. **Step Functions State Machine**: Orchestrates the conversion workflow
4. **Lambda Functions**: Serverless conversion jobs
   - `zarr-converter`: NetCDF → Zarr (Lambda, 10GB memory, 15min timeout)
   - `stac-creator`: Creates STAC metadata (Lambda)
   - `stac-indexer`: Indexes STAC in OpenSearch (Lambda)
5. **ECS Task**: Containerized COG generation
   - `cog-generation`: Zarr → Cloud Optimized GeoTIFF (ECS Fargate)
6. **Output Buckets**: 
   - Zarr bucket for analysis-ready multidimensional data
   - COG bucket for web mapping tiles
   - STAC bucket for metadata JSON files
7. **OpenSearch**: STAC metadata index for data discovery

## Workflow Steps

### 1. Upload Detection
- User uploads NetCDF file to `s3://{raw-bucket}/ingestion/{filename}.nc`
- S3 event notification triggers Lambda function
- Lambda validates file and starts Step Functions execution

### 2. Zarr Conversion (ECS Task)
**Task Definition**: `zarr-conversion`
**Location**: `app/ingestion/zarr_converter.py`

**Process**:
- Downloads NetCDF file from S3
- Opens with xarray
- **Detects coordinate reference system (CRS)** from CF metadata
- **Transforms projected coordinates to WGS84** if needed
- Extracts bounding box from coordinates or global attributes
- **Extracts variable metadata** (name, units, standard_name, etc.)
- **Extracts global attributes** (institution, title, creator, etc.)
- Converts to Zarr format with optimal chunking
- Uploads to Zarr bucket: `s3://{zarr-bucket}/zarr/{filename}.zarr`
- Writes metadata file with bounding box, CRS info, and variable metadata

**Container Configuration**:
- CPU: 512 units (0.5 vCPU)
- Memory: 2048 MB (2 GB)
- Image: ECR repository with xarray/zarr dependencies
- Command: `["python", "/app/ingestion/zarr_converter.py"]`

**Environment Variables** (passed by Step Functions):
- `INPUT_BUCKET`: Source bucket
- `INPUT_KEY`: S3 key of NetCDF file
- `OUTPUT_BUCKET`: Destination bucket

**Output** (computed by ResultSelector):
```json
{
  "zarr_key": "zarr/file.zarr",
  "zarr_bucket": "zarr-bucket-name",
  "bbox": [166.5, -47.3, 179.8, -34.4],
  "crs_info": {
    "detected": "EPSG:2193",
    "type": "projected"
  },
  "variables": [
    {
      "name": "SST",
      "standard_name": "sea_surface_temperature",
      "units": "degC"
    }
  ],
  "collections": [
    {
      "name": "sea-surface-temperature",
      "variable": "SST"
    }
  ],
  "status": "success"
}
```

**Migration Note**: Previously Lambda-based (10GB memory, 15min timeout, $2.50/file).
Now ECS-based (0.5 vCPU, 2GB memory, no timeout, $0.01/file). **98% cost reduction.**

### 3. COG Generation (ECS Task)
**Task Definition**: `cog-generation`
**Location**: `app/ingestion/cog_generator.py`

**Process**:
- Opens Zarr dataset from S3
- Extracts spatial slices using rioxarray
- Generates Cloud Optimized GeoTIFF with overviews
- Uploads to COG bucket: `s3://{cog-bucket}/cog/{filename}.tif`

**Container Configuration**:
- CPU: 2048 (2 vCPU)
- Memory: 4096 MB
- Image: ECR repository with GDAL/rasterio dependencies
- Command: `["python", "-m", "app.ingestion.cog_generator"]`

**Environment Variables** (passed by Step Functions):
- `ZARR_BUCKET`: Source bucket
- `ZARR_KEY`: S3 key of Zarr dataset
- `OUTPUT_BUCKET`: Destination bucket

### 4. STAC Metadata Creation (Lambda Function)
**Function**: `stac-creator`
**Location**: `terraform/modules/ingestion/lambda/stac_creator/`

**Process**:
- Extracts metadata from Zarr and COG
- Creates STAC Item with:
  - Spatial extent (bounding box from CRS transformation)
  - Temporal extent (time range)
  - Asset links (Zarr and COG S3 URLs)
  - **Variable metadata** (name, units, standard_name)
  - **Global attributes** (institution, title, creator)
  - Collection information (derived from standard_name)
- **Creates or updates collections** for each variable type
- Saves STAC JSON to S3 STAC bucket

**Lambda Configuration**:
- Runtime: Python 3.12
- Memory: 512 MB
- Timeout: 300 seconds (5 minutes)

**Input Event**:
```json
{
  "zarr_bucket": "zarr-bucket-name",
  "zarr_key": "zarr/file.zarr",
  "cog_bucket": "cog-bucket-name",
  "cog_key": "cog/file.tif",
  "metadata": {"source": "upload"}
}
```

**Output**:
```json
{
  "statusCode": 200,
  "stac_key": "items/uuid.json",
  "stac_id": "uuid"
}
```

### 5. OpenSearch Indexing (Lambda Function)
**Function**: `stac-indexer`
**Location**: `terraform/modules/ingestion/lambda/stac_indexer/`

**Process**:
- Reads STAC JSON from S3
- Connects to OpenSearch using IAM authentication
- Creates index if it doesn't exist
- Indexes STAC document
- Makes data discoverable via API

**Lambda Configuration**:
- Runtime: Python 3.12
- Memory: 256 MB
- Timeout: 60 seconds
- Dependencies: `opensearch-py`, `requests-aws4auth`

**Input Event**:
```json
{
  "stac_bucket": "stac-bucket-name",
  "stac_key": "items/uuid.json"
}
```

**Output**:
```json
{
  "statusCode": 200,
  "result": "created",
  "stac_id": "uuid"
}
```

## Infrastructure as Code

### Terraform Resources

#### Lambda Functions
**File**: `terraform/modules/ingestion/main.tf`

```hcl
# Zarr Converter Lambda
resource "aws_lambda_function" "zarr_converter" {
  filename         = "lambda_packages/zarr_converter.zip"
  function_name    = "${var.project_name}-zarr-converter"
  role             = var.lambda_execution_role_arn
  handler          = "zarr_converter_lambda.lambda_handler"
  runtime          = "python3.12"
  memory_size      = 10240
  timeout          = 900
  ephemeral_storage {
    size = 10240  # 10GB
  }
}

# STAC Creator Lambda
resource "aws_lambda_function" "stac_creator" {
  filename         = "lambda_packages/stac_creator.zip"
  function_name    = "${var.project_name}-stac-creator"
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  memory_size      = 512
  timeout          = 300
}

# STAC Indexer Lambda
resource "aws_lambda_function" "stac_indexer" {
  filename         = "lambda_packages/stac_indexer.zip"
  function_name    = "${var.project_name}-stac-indexer"
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  memory_size      = 256
  timeout          = 60
}
```

#### ECS Task Definition (COG Generation)
**File**: `terraform/modules/ecs/main.tf`

```hcl
resource "aws_ecs_task_definition" "cog_generation" {
  family                   = "cog-generation"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "2048"
  memory                   = "4096"
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn
  
  container_definitions = jsonencode([{
    name  = "cog-generator"
    image = "${var.ecr_repository_url}:latest"
    command = ["python", "-m", "app.ingestion.cog_generator"]
    # ... environment, logging, etc.
  }])
}
```

#### Step Functions State Machine
**File**: `terraform/modules/ingestion/main.tf`

```hcl
resource "aws_sfn_state_machine" "ingestion" {
  name     = "${var.project_name}-ingestion-pipeline"
  role_arn = var.step_functions_role_arn
  
  definition = jsonencode({
    StartAt = "ConvertToZarr"
    States = {
      ConvertToZarr = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.zarr_converter.arn
          Payload = {
            "bucket"        = var.raw_bucket
            "key.$"         = "$.key"
            "output_bucket" = var.zarr_bucket
          }
        }
        ResultPath = "$.zarr_conversion"
        Next       = "GenerateCOG"
        Retry = [{
          ErrorEquals     = ["States.TaskFailed"]
          IntervalSeconds = 10
          MaxAttempts     = 2
        }]
      }
      GenerateCOG = {
        Type     = "Task"
        Resource = "arn:aws:states:::ecs:runTask.sync"
        Parameters = {
          LaunchType     = "FARGATE"
          Cluster        = var.ecs_cluster_arn
          TaskDefinition = var.cog_task_definition_arn
          NetworkConfiguration = {
            AwsvpcConfiguration = {
              Subnets        = var.private_subnets
              SecurityGroups = [var.ecs_security_group_id]
            }
          }
          Overrides = {
            ContainerOverrides = [{
              Name = "cog-generator"
              Environment = [
                {Name = "ZARR_BUCKET", "Value.$" = "$.zarr_conversion.zarr_bucket"},
                {Name = "ZARR_KEY", "Value.$" = "$.zarr_conversion.zarr_key"},
                {Name = "OUTPUT_BUCKET", Value = var.cog_bucket}
              ]
            }]
          }
        }
        ResultPath = "$.cog_generation"
        Next       = "CreateSTAC"
      }
      CreateSTAC = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.stac_creator.arn
          Payload = {
            "zarr_bucket" = var.zarr_bucket
            "zarr_key.$"  = "$.zarr_conversion.zarr_key"
            "cog_bucket"  = var.cog_bucket
            "cog_key.$"   = "States.Format('cog/{}.tif', $.zarr_conversion.zarr_key)"
          }
        }
        ResultPath = "$.stac_creation"
        Next       = "IndexSTAC"
      }
      IndexSTAC = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.stac_indexer.arn
          Payload = {
            "stac_bucket" = var.stac_bucket
            "stac_key.$"  = "$.stac_creation.Payload.stac_key"
          }
        }
        ResultPath = "$.stac_indexing"
        Next       = "Success"
      }
      Success = { Type = "Succeed" }
    }
  })
}
```

#### IAM Permissions
**File**: `terraform/modules/iam/main.tf`

**Step Functions Role**:
```hcl
data "aws_iam_policy_document" "step_functions_policy" {
  # ECS RunTask permissions
  statement {
    actions = [
      "ecs:RunTask",
      "ecs:StopTask",
      "ecs:DescribeTasks"
    ]
    resources = [
      "arn:aws:ecs:${var.region}:${data.aws_caller_identity.current.account_id}:task-definition/${var.project_name}-zarr-conversion:*",
      "arn:aws:ecs:${var.region}:${data.aws_caller_identity.current.account_id}:task-definition/${var.project_name}-cog-generation:*"
    ]
  }
  
  # PassRole for ECS execution
  statement {
    actions   = ["iam:PassRole"]
    resources = [
      var.execution_role_arn,
      var.task_role_arn
    ]
  }
  
  # CloudWatch Events
  statement {
    actions   = ["events:PutTargets", "events:PutRule", "events:DescribeRule"]
    resources = ["*"]
  }
}
```

**ECS Task Role** (for conversion tasks):
```hcl
# S3 access for reading/writing data
statement {
  actions = [
    "s3:GetObject",
    "s3:PutObject",
    "s3:ListBucket"
  ]
  resources = [
    "${var.s3_raw_bucket_arn}/*",
    "${var.s3_zarr_bucket_arn}/*",
    "${var.s3_cog_bucket_arn}/*"
  ]
}

# OpenSearch access for STAC indexing
statement {
  actions = [
    "es:ESHttpPost",
    "es:ESHttpPut"
  ]
  resources = ["${var.opensearch_domain_arn}/*"]
}
```

## Deployment

### Prerequisites
1. Docker image built with ingestion modules
2. ECR repository populated
3. Terraform applied with ingestion module enabled

### Terraform Outputs
```bash
terraform output ingestion_state_machine_arn
terraform output zarr_conversion_task_definition_arn
terraform output cog_generation_task_definition_arn
```

### Manual Trigger (Testing)
```bash
# Start execution with test payload
aws stepfunctions start-execution \
  --state-machine-arn $(terraform output -raw ingestion_state_machine_arn) \
  --input '{
    "bucket": "raw-bucket-name",
    "key": "ingestion/test-file.nc",
    "metadata": {
      "source": "manual-test"
    }
  }'

# Monitor execution
aws stepfunctions describe-execution \
  --execution-arn <execution-arn>

# Use debug script
./debug_ingestion.sh
```

## Monitoring

### CloudWatch Logs
```bash
# Zarr conversion logs (Lambda)
aws logs tail /aws/lambda/cloud-scientific-raster-sharing-zarr-converter --follow

# COG generation logs (ECS)
aws logs tail /ecs/cog-generation --follow

# STAC creator logs (Lambda)
aws logs tail /aws/lambda/cloud-scientific-raster-sharing-stac-creator --follow

# STAC indexer logs (Lambda)
aws logs tail /aws/lambda/cloud-scientific-raster-sharing-stac-indexer --follow

# Lambda trigger logs
aws logs tail /aws/lambda/cloud-scientific-raster-sharing-ingestion-trigger --follow

# Step Functions execution history
aws stepfunctions get-execution-history \
  --execution-arn <execution-arn> \
  --max-results 50
```

### Metrics
- **Step Functions**: Execution success/failure rate
- **ECS Tasks**: Task duration, CPU/memory utilization
- **S3**: Object count in output buckets
- **OpenSearch**: Document count in STAC index

## Troubleshooting

### Common Issues

#### 1. Step Functions Execution Fails Immediately
**Symptom**: Execution fails with "AccessDeniedException"
**Cause**: Missing IAM permissions for Step Functions role
**Fix**: Ensure Step Functions role has `ecs:RunTask` and `iam:PassRole` permissions

#### 2. Lambda Function Timeout
**Symptom**: Zarr conversion Lambda times out after 15 minutes
**Cause**: Large NetCDF file or insufficient memory
**Fix**: 
- Increase Lambda memory (up to 10GB)
- Increase ephemeral storage (up to 10GB)
- Consider splitting large files

#### 3. ECS Task Fails to Start
**Symptom**: COG generation task transitions to STOPPED state
**Cause**: Missing execution role or incorrect image
**Fix**: 
- Verify execution role exists and has ECR pull permissions
- Check CloudWatch logs for error details
- Ensure Docker image exists in ECR

#### 4. Lambda Missing Dependencies
**Symptom**: `ImportModuleError: No module named 'opensearchpy'`
**Cause**: Lambda package doesn't include dependencies
**Fix**: 
```bash
cd terraform/modules/ingestion/lambda/stac_indexer
python -m pip install -r requirements.txt -t package/
cp handler.py package/
python -c "import shutil; shutil.make_archive('../../lambda_packages/stac_indexer', 'zip', 'package')"
aws lambda update-function-code --function-name stac-indexer --zip-file fileb://../../lambda_packages/stac_indexer.zip
```

#### 5. S3 Access Denied
**Symptom**: Task fails with S3 permission errors
**Cause**: Task role missing S3 permissions
**Fix**: Update task role IAM policy to include required S3 buckets

#### 6. OpenSearch Connection Timeout
**Symptom**: Cannot connect to OpenSearch from ECS task
**Cause**: Security group or network configuration
**Fix**: 
- Ensure ECS task is in same VPC as OpenSearch
- Verify security group allows inbound from ECS task security group
- Check VPC endpoints configuration

## Testing

### Unit Tests
```bash
# Test zarr converter
pytest app/tests/unit/test_zarr_converter.py

# Test COG generator
pytest app/tests/unit/test_cog_generator.py
```

### Integration Tests
```bash
# End-to-end ingestion test
pytest app/tests/integration/test_ingestion_pipeline.py
```

### Manual Validation
```bash
# 1. Upload test file
aws s3 cp test-data.nc s3://${RAW_BUCKET}/ingestion/test-data.nc

# 2. Wait for processing (check Step Functions console)

# 3. Verify Zarr output
aws s3 ls s3://${ZARR_BUCKET}/datasets/test-collection/

# 4. Verify COG output
aws s3 ls s3://${COG_BUCKET}/tiles/test-collection/

# 5. Query STAC catalog
curl "http://${ALB_DNS}/api/collections"
```

## Performance Tuning

### Lambda Resources
- **Zarr Converter**: 10GB memory, 15min timeout, 10GB ephemeral storage
- **STAC Creator**: 512MB memory, 5min timeout
- **STAC Indexer**: 256MB memory, 1min timeout

### ECS Task Resources (COG Generation)
- **Small files (<100MB)**: 2 vCPU, 4GB RAM
- **Medium files (100MB-1GB)**: 2 vCPU, 4GB RAM
- **Large files (>1GB)**: 4 vCPU, 8GB RAM

### Zarr Chunking
Optimize chunk size based on access patterns:
- **Time-series access**: Chunk by time dimension
- **Spatial access**: Chunk by lat/lon
- **Default**: Auto-chunking via xarray

### COG Overviews
- Generate 4-6 overview levels for optimal tile serving
- Use DEFLATE compression for smaller file sizes
- Consider JPEG compression for RGB imagery

## Cost Optimization

### Strategies
1. **Use Spot instances** for ECS tasks (non-critical workloads)
2. **Batch processing**: Accumulate files and process in bulk
3. **S3 Lifecycle policies**: Archive old data to Glacier
4. **Right-size tasks**: Monitor CPU/memory and adjust

### Estimated Costs (per 1000 files)
- Lambda invocations: ~$2-5 (Zarr conversion)
- ECS Fargate tasks: ~$3-6 (COG generation)
- Step Functions executions: ~$0.25
- S3 storage: Variable (depends on data size)
- Data transfer: Minimal (within same region)

**Total**: ~$5-12 per 1000 files

## Security Best Practices

1. **Least privilege IAM**: Task roles only access required S3 prefixes
2. **VPC isolation**: All processing in private subnets
3. **Encryption**: S3 buckets use SSE-S3 or SSE-KMS
4. **Secrets management**: Use AWS Secrets Manager for credentials
5. **Audit logging**: Enable CloudTrail for all API calls

## Current Status

✅ **Implemented**:
- Lambda-based Zarr conversion (10GB memory, 15min timeout)
- ECS-based COG generation (2 vCPU, 4GB RAM)
- Lambda-based STAC creation and indexing
- Step Functions orchestration with retry logic
- S3 event-driven triggers
- OpenSearch integration with IAM auth
- CloudWatch logging and monitoring

## Future Enhancements

- [ ] Parallel processing for large files
- [ ] Dead letter queue for failed conversions
- [ ] Real-time progress notifications (SNS/SQS)
- [ ] Multi-format support (HDF5, GeoTIFF input)
- [ ] Validation and quality checks
- [ ] Automatic thumbnail generation
- [ ] Metadata extraction and enrichment
- [ ] Cost optimization with Lambda reserved concurrency
