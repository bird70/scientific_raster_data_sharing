# Known Issues

This document tracks known issues in the infrastructure that are outside the scope of the current migration task but should be addressed in the future.

## 1. Lambda Container Images - Windows Docker Build Issues

### Issue
Lambda functions using container images fail to deploy with the following errors:

**Zarr Converter Lambda:**
```
InvalidParameterValueException: The image manifest, config or layer media type 
for the source image is not supported.
```

**COG Generator Lambda:**
```
InvalidParameterValueException: Source image does not exist.
SHA: sha256:0000000000000000000000000000000000000000000000000000000000000000
```

### Root Cause
- Docker images built on Windows include manifest formats not supported by AWS Lambda
- Lambda requires specific OCI (Open Container Initiative) image format
- Windows Docker may add extra layers or use incompatible manifest versions
- COG generator has a placeholder SHA digest (never built)

### Impact
- **Severity:** Medium
- **Affected Components:** Ingestion pipeline (Zarr conversion, COG generation)
- **Workaround:** Use existing Lambda functions if already deployed
- **Blocks:** New Lambda deployments, ingestion pipeline updates

### Recommended Solution

#### Option 1: Build on Linux (Recommended)
```bash
# Use WSL2, Linux VM, or Linux CI/CD environment
docker build -t zarr-converter:latest -f app/lambda/Dockerfile .
docker build -t cog-generator:latest -f app/lambda/Dockerfile.cog .

# Tag and push to ECR
aws ecr get-login-password --region ap-southeast-2 | docker login --username AWS --password-stdin 123456789101.dkr.ecr.ap-southeast-2.amazonaws.com

docker tag zarr-converter:latest 123456789101.dkr.ecr.ap-southeast-2.amazonaws.com/cloud-scientific-raster-sharing-repo:zarr-converter
docker push 123456789101.dkr.ecr.ap-southeast-2.amazonaws.com/cloud-scientific-raster-sharing-repo:zarr-converter

docker tag cog-generator:latest 123456789101.dkr.ecr.ap-southeast-2.amazonaws.com/cloud-scientific-raster-sharing-repo:cog-generator
docker push 123456789101.dkr.ecr.ap-southeast-2.amazonaws.com/cloud-scientific-raster-sharing-repo:cog-generator

# Get SHA digests
aws ecr describe-images --repository-name cloud-scientific-raster-sharing-repo --image-ids imageTag=zarr-converter
aws ecr describe-images --repository-name cloud-scientific-raster-sharing-repo --image-ids imageTag=cog-generator

# Update terraform/variables.tf with real SHA digests
```

#### Option 2: Use AWS CodeBuild
Create a CodeBuild project to build Lambda images in AWS Linux environment:

```yaml
# buildspec.yml
version: 0.2
phases:
  pre_build:
    commands:
      - aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY
  build:
    commands:
      - docker build -t zarr-converter:latest -f app/lambda/Dockerfile .
      - docker build -t cog-generator:latest -f app/lambda/Dockerfile.cog .
      - docker tag zarr-converter:latest $ECR_REGISTRY/cloud-scientific-raster-sharing-repo:zarr-converter
      - docker tag cog-generator:latest $ECR_REGISTRY/cloud-scientific-raster-sharing-repo:cog-generator
  post_build:
    commands:
      - docker push $ECR_REGISTRY/cloud-scientific-raster-sharing-repo:zarr-converter
      - docker push $ECR_REGISTRY/cloud-scientific-raster-sharing-repo:cog-generator
```

#### Option 3: Use Docker Buildx with Platform Flag
```bash
# Build for Linux AMD64 platform explicitly
docker buildx build --platform linux/amd64 -t zarr-converter:latest -f app/lambda/Dockerfile .
docker buildx build --platform linux/amd64 -t cog-generator:latest -f app/lambda/Dockerfile.cog .
```

### Files to Update After Fix
1. `terraform/variables.tf` - Update `lambda_image_digest` and `cog_image_digest` with real SHA values
2. `terraform/modules/lambda_ingestion/main.tf` - Verify image URIs are correct

### Related Documentation
- [AWS Lambda Container Images](https://docs.aws.amazon.com/lambda/latest/dg/images-create.html)
- [Docker Multi-Platform Builds](https://docs.docker.com/build/building/multi-platform/)

---

## 2. CloudWatch DynamoDB Dashboard - Invalid Metric Format

### Issue
DynamoDB CloudWatch dashboard fails to create with validation errors:

```
InvalidParameterInput: The dashboard body is invalid, there are 22 validation errors:
"Invalid metric field type, only 'String' type is allowed"
```

### Root Cause
- Dashboard JSON uses numeric types in metric definitions
- CloudWatch requires string types for certain metric fields
- Likely in `terraform/modules/monitoring/main.tf` around line 496+

### Impact
- **Severity:** Low
- **Affected Components:** CloudWatch dashboard visualization
- **Workaround:** View metrics directly in CloudWatch console
- **Blocks:** Dashboard creation only (metrics still work)

### Recommended Solution

Update `terraform/modules/monitoring/main.tf` to convert numeric values to strings in metric definitions:

```hcl
# Before (incorrect)
["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", var.dynamodb_table_name, { stat: "Sum", period: 300 }]

# After (correct)
["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", var.dynamodb_table_name, { "stat": "Sum", "period": "300" }]
```

Key changes:
1. Ensure all metric array elements are strings
2. Convert numeric values like `300` to `"300"`
3. Use double quotes for all JSON keys and values

### Files to Update
- `terraform/modules/monitoring/main.tf` - Fix dashboard JSON format (lines 496-600)

### Testing
After fix:
```bash
cd terraform
terraform plan
# Should show dashboard will be created without errors
terraform apply
```

---

## 3. ECS Service Discovery - Deprecated Argument

### Issue
Warning during Terraform operations:

```
Warning: Argument is deprecated
  with module.ecs.aws_service_discovery_service.dask_scheduler,
  on modules\ecs\main.tf line 739, in resource "aws_service_discovery_service" "dask_scheduler":
   739:     failure_threshold = 1

failure_threshold is deprecated. The argument is no longer supported by AWS 
and the value is always set to 1.
```

### Root Cause
- AWS deprecated the `failure_threshold` argument in service discovery
- Value is now always 1 and cannot be changed
- Terraform still accepts it but warns it will be removed

### Impact
- **Severity:** Very Low
- **Affected Components:** Dask scheduler service discovery
- **Workaround:** None needed - still works
- **Blocks:** Nothing (just a warning)

### Recommended Solution

Remove the deprecated argument:

```hcl
# In terraform/modules/ecs/main.tf around line 739
resource "aws_service_discovery_service" "dask_scheduler" {
  name = "scheduler"
  
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.dask.id
    
    dns_records {
      ttl  = 10
      type = "A"
    }
    
    routing_policy = "MULTIVALUE"
  }
  
  health_check_custom_config {
    # Remove this line:
    # failure_threshold = 1
    # It's now always 1 by default
  }
}
```

### Files to Update
- `terraform/modules/ecs/main.tf` - Remove `failure_threshold = 1` from service discovery

---

## 4. CloudWatch Monitoring - Deprecated Region Attribute

### Issue
Multiple warnings during Terraform operations:

```
Warning: Deprecated attribute
  on modules\monitoring\main.tf line 160, in resource "aws_cloudwatch_dashboard" "main":
   160:           region = data.aws_region.current.name

The attribute "name" is deprecated. Refer to the provider documentation for details.
```

### Root Cause
- `data.aws_region.current.name` is deprecated
- Should use `data.aws_region.current.id` instead

### Impact
- **Severity:** Very Low
- **Affected Components:** CloudWatch dashboards
- **Workaround:** None needed - still works
- **Blocks:** Nothing (just a warning)

### Recommended Solution

Update all references in monitoring module:

```hcl
# Before
region = data.aws_region.current.name

# After
region = data.aws_region.current.id
```

### Files to Update
- `terraform/modules/monitoring/main.tf` - Replace all `.name` with `.id` for region data source

---

## 5. Zarr Converter Lambda Timeout - Architecture Issue

### Issue
Zarr converter Lambda times out after 15 minutes when processing NetCDF files:

```
Lambda.Unknown: Task timed out after 900.11 seconds
```

### Root Cause
- Step Functions uses Lambda for Zarr conversion
- Lambda has a hard 15-minute maximum timeout
- Processing 30MB NetCDF files takes longer than 15 minutes
- Lambda is not designed for long-running data processing tasks

### Impact
- **Severity:** High
- **Affected Components:** Ingestion pipeline (Zarr conversion step)
- **Workaround:** None for Lambda-based approach
- **Blocks:** Processing of NetCDF files larger than ~10MB

### Recommended Solution

Change Step Functions to use ECS Fargate for Zarr conversion (like COG generation already does):

**Current (Broken)**:
```hcl
# terraform/modules/ingestion/main.tf
ConvertToZarr = {
  Type     = "Task"
  Resource = "arn:aws:states:::lambda:invoke"  # ❌ 15 min max
  Parameters = {
    FunctionName = var.lambda_zarr_converter_arn
  }
}
```

**Fixed**:
```hcl
ConvertToZarr = {
  Type     = "Task"
  Resource = "arn:aws:states:::ecs:runTask.sync"  # ✅ Hours allowed
  Parameters = {
    LaunchType     = "FARGATE"
    Cluster        = var.ecs_cluster_arn
    TaskDefinition = var.zarr_conversion_task_definition_arn
    NetworkConfiguration = {
      AwsvpcConfiguration = {
        Subnets        = var.private_subnets
        SecurityGroups = [var.ecs_security_group_id]
        AssignPublicIp = "DISABLED"
      }
    }
    Overrides = {
      ContainerOverrides = [{
        Name = "zarr-converter"
        Environment = [
          { Name = "INPUT_BUCKET", Value = "$.bucket" },
          { Name = "INPUT_KEY", Value = "$.key" },
          { Name = "OUTPUT_BUCKET", Value = var.zarr_bucket }
        ]
      }]
    }
  }
}
```

### Files to Update
1. `terraform/modules/ingestion/main.tf` - Update Step Functions state machine definition
2. `terraform/modules/ingestion/variables.tf` - Ensure ECS variables are available
3. Test with large NetCDF file to verify timeout is resolved

### Benefits of ECS Fargate
- No timeout limit (can run for hours)
- More memory available (up to 30GB)
- More CPU available (up to 4 vCPU)
- Better suited for data processing workloads

### Related Documentation
- [AWS Step Functions ECS Integration](https://docs.aws.amazon.com/step-functions/latest/dg/connect-ecs.html)
- [Lambda Limits](https://docs.aws.amazon.com/lambda/latest/dg/gettingstarted-limits.html)

---

## Priority for Fixes

1. **High Priority:** Zarr converter Lambda timeout (blocks ingestion pipeline)
2. **Medium Priority:** Lambda container image issues (RESOLVED ✅)
3. **Medium Priority:** CloudWatch dashboard format (improves monitoring UX)
4. **Low Priority:** Deprecated arguments (cosmetic warnings, no functional impact)

## Notes

- These issues are **not related to the dual backend migration** (Task 10)
- They are pre-existing infrastructure issues
- They should be addressed in separate maintenance tasks
- None of them block the migration from OpenSearch to DynamoDB
