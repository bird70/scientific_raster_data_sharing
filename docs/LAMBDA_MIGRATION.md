# Lambda Migration for Ingestion Pipeline

## Overview
Migrated NetCDF→Zarr conversion from ECS to Lambda for improved scalability and cost efficiency.

## Architecture Change

### Before (ECS-based)
- Step Functions invoked ECS tasks via `ecs:runTask.sync`
- Limited to 50-100 concurrent tasks
- Could not return custom JSON to Step Functions (only task metadata)
- Required workaround: write results to S3, read back in next step

### After (Lambda-based)
- Step Functions invokes Lambda via `lambda:invoke`
- Supports 1000+ concurrent executions
- Returns JSON directly to Step Functions
- Cleaner integration, no S3 workaround needed

## Implementation

### Lambda Function
- **Location**: `app/lambda/zarr_converter_lambda.py`
- **Base Image**: `public.ecr.aws/lambda/python:3.12`
- **Memory**: 10GB
- **Timeout**: 15 minutes
- **Package Type**: Container image

### Docker Build Issue & Solution
**Problem**: Docker Desktop's buildx creates OCI manifest lists by default, which Lambda doesn't support.

**Error**: `The image manifest, config or layer media type for the source image is not supported`

**Solution**: Reference specific image digest instead of tag in Terraform:
```hcl
image_uri = "${var.ecr_repository_url}@sha256:7c2cd613015d689b34bf05dd7d8c646291f9a35af1c345ffc7f800a0041fe0ee"
```

### IAM Permissions
Lambda execution role requires:
- `s3:GetObject` - Read NetCDF from raw bucket
- `s3:PutObject` - Write zarr files to zarr bucket
- `s3:ListBucket` - Required by s3fs for zarr storage operations
- `logs:CreateLogGroup`, `logs:CreateLogStream`, `logs:PutLogEvents` - CloudWatch logging

## Deployment

### Automated Deployment (Recommended)
```bash
cd scripts
./deploy-lambda.sh
```

This script:
1. Builds Lambda image with `DOCKER_BUILDKIT=0` (avoids manifest list issues)
2. Pushes to ECR with `lambda` tag
3. Extracts image digest
4. Updates `terraform.tfvars` with new digest
5. Applies Terraform to update Lambda function

### Manual Deployment

### 1. Build Lambda Image
```bash
cd app/lambda
export DOCKER_BUILDKIT=0
docker build -t <ECR_URL>:lambda .
docker push <ECR_URL>:lambda
```

**Note**: Uses `uv` for 2-5x faster pip installs. Docker BuildKit must be disabled to avoid manifest list issues.

### 2. Get Image Digest
```bash
aws ecr describe-images \
  --repository-name cloud-scientific-raster-sharing-repo \
  --image-ids imageTag=lambda \
  --query 'imageDetails[0].imageDigest' \
  --output text
```

### 3. Update terraform.tfvars
```bash
echo 'lambda_image_digest = "sha256:..."' >> terraform/terraform.tfvars
```

### 4. Apply Changes
```bash
cd terraform
terraform apply -target=module.lambda_ingestion.aws_lambda_function.zarr_converter
```

## Testing

### Manual Test
```bash
./debug_ingestion.sh
```

### Expected Flow
1. S3 upload triggers Lambda (via S3 event → trigger Lambda → Step Functions)
2. Step Functions invokes zarr converter Lambda
3. Lambda reads NetCDF from S3, converts to zarr, writes to S3
4. Lambda returns JSON: `{"zarr_key": "...", "zarr_bucket": "...", "status": "success"}`
5. Step Functions continues to COG generation (still ECS)

### Test Results
**Lambda Zarr Conversion**: ✅ SUCCESS
- Completed in ~9 seconds
- Successfully returned JSON to Step Functions
- Zarr files created in S3

**COG Generation**: ❌ FAILED (fixed)
- Issue: NetCDF file had conflicting `_FillValue` (nan) and `missing_value` (-9999.0)
- Fix: Remove `missing_value` attribute before encoding
- Updated `app/ingestion/cog_generator.py`

## Troubleshooting

### Permission Errors
If you see `s3:ListBucket` permission denied:
```bash
cd terraform
terraform apply  # Updates IAM policy
```

### Image Not Found
Verify image exists in ECR:
```bash
aws ecr describe-images \
  --repository-name cloud-scientific-raster-sharing-repo \
  --region ap-southeast-2
```

### Lambda Timeout
Check CloudWatch Logs:
```bash
aws logs tail /aws/lambda/cloud-scientific-raster-sharing-zarr-converter --follow
```

## Benefits

1. **Scalability**: 1000+ concurrent executions vs 50-100 ECS tasks
2. **Cost**: Pay per invocation (no idle time) vs ECS task running time
3. **Integration**: Direct JSON return to Step Functions
4. **Simplicity**: No S3 workaround for passing data between steps

## Future Enhancements

Consider migrating COG generation to Lambda as well for consistency and scalability.
