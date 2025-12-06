# Design Document

## Overview

This design document describes the completion of the Raster Time-series Access Web Service infrastructure. The system provides performant web/API access to large raster datasets through map tiles and timeseries extraction APIs. The existing codebase includes a FastAPI application with core business logic and partial Terraform infrastructure. This design focuses on completing the missing infrastructure components to enable production deployment.

The architecture follows AWS best practices with containerized services running on ECS Fargate, CloudFront CDN for edge caching, automated ingestion pipelines, distributed computing with Dask, and comprehensive monitoring. All infrastructure is defined as code using Terraform with proper tagging, documentation, and CI/CD automation.

## Architecture

### High-Level Architecture

```
┌─────────────┐
│   Users     │
└──────┬──────┘
       │
       ▼
┌─────────────────┐
│  CloudFront CDN │ (Tile caching, HTTPS)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│      ALB        │ (HTTPS listener, path routing)
└────────┬────────┘
         │
    ┌────┴────┐
    │         │
    ▼         ▼
┌────────┐ ┌──────────┐
- Mock DynamoDB client/table responses
│ Tiles  │ │Timeseries│ (ECS Fargate services)
│Service │ │ Service  │
└───┬────┘ └────┬─────┘
    │           │
    │           ▼
    │      ┌─────────┐
    │      │  Dask   │ (Scheduler + Workers)
    │      │ Cluster │
    │      └────┬────┘
    │           │
    └───────┬───┴──────┐
            │          │
            ▼          ▼
      ┌────────┐  ┌──────────┐
      │   S3   │  │DynamoDB  │
      │ Zarr/  │  │  (STAC)  │
      │  COG   │  └──────────┘
       └────────┘
            ▲
            │
    ┌───────┴────────┐
    │   Ingestion    │
    │    Pipeline    │
    │ (Lambda + Step │
    │   Functions)   │
    └───────▲────────┘
            │
       ┌────┴────┐
       │   S3    │
       │  Raw    │
       │ NetCDF  │
       └─────────┘
```

### Component Interaction Flow

**Tile Request Flow:**
1. User requests tile → CloudFront (cache check)
2. Cache miss → ALB → Tiles ECS Service
3. Service queries DynamoDB (STAC table) for COG location
4. Service reads COG from S3, renders tile
5. Response cached at CloudFront edge

**Timeseries Request Flow:**
1. User requests timeseries → CloudFront (no cache) → ALB → Timeseries ECS Service
2. Service queries DynamoDB (STAC table) for overlapping datasets
3. Service submits Dask tasks to read Zarr from S3
4. Dask workers process in parallel, aggregate results
5. Service caches result in Redis, returns to user

**Ingestion Flow:**
1. NetCDF uploaded to S3 raw bucket
2. S3 event triggers Lambda
3. Lambda starts Step Functions workflow
4. Workflow orchestrates: NetCDF→Zarr conversion, COG generation, STAC item creation
5. STAC item upserted into DynamoDB STAC table (with GSIs for spatial/temporal)

## Components and Interfaces

### 1. ECS Task Definitions and Services

**Purpose:** Define how containers run and maintain desired task counts

**Task Definition Configuration:**
- **Launch Type:** Fargate (serverless)
- **CPU/Memory:** 1 vCPU / 2GB RAM (tiles), 2 vCPU / 4GB RAM (timeseries)
- **Container Image:** From ECR repository
- **Port Mappings:** Container port 8080
- **Environment Variables:**
  - `AWS_REGION`: ap-southeast-2
  - `S3_ZARR_PREFIX`: s3://{zarr-bucket}/
  - `S3_COG_PREFIX`: s3://{cog-bucket}/
  - `STAC_TABLE_NAME`: {dynamodb-table}
  - `STAC_GSI_NAME`: {gsi-name-for-spatial-temporal}
  - `REDIS_URL`: redis://{redis-endpoint}:6379
  - `COGNITO_JWKS_URL`: https://cognito-idp.{region}.amazonaws.com/{pool-id}/.well-known/jwks.json
  - `COGNITO_USERPOOL_AUD`: {client-id}
  - `DASK_SCHEDULER`: {dask-scheduler-endpoint}:8786
- **Logging:** CloudWatch Logs with 7-day retention
- **IAM Role:** Task role with S3, DynamoDB (table + GSI), and Secrets Manager permissions

**Service Configuration:**
- **Desired Count:** 2 (tiles), 2 (timeseries)
- **Deployment:** Rolling update with 50% minimum healthy
- **Network:** Private subnets, ECS security group
- **Load Balancer:** Attached to appropriate target group
- **Health Check Grace Period:** 60 seconds

**Interface:**
- Input: Terraform variables (vpc_id, subnets, security_groups, image_uri, environment_vars)
- Output: Service ARNs, task definition ARNs

### 2. Application Load Balancer Configuration

**Purpose:** Route HTTPS traffic to appropriate ECS services

**Configuration:**
- **Listener:** Port 443, HTTPS with ACM certificate
- **Target Groups:**
  - tiles-tg: Port 8080, health check /health
  - timeseries-tg: Port 8080, health check /health
- **Listener Rules:**
  - Priority 10: /tiles/* → tiles-tg
  - Priority 20: /api/* → timeseries-tg
  - Priority 30: /metrics → tiles-tg (or dedicated metrics service)
  - Default: 404 response
- **Deregistration Delay:** 30 seconds
- **Stickiness:** Disabled (stateless services)

**Interface:**
- Input: VPC ID, public subnets, security group, certificate ARN
- Output: ALB DNS name, ARN, listener ARN

### 3. ECS Autoscaling Policies

**Purpose:** Automatically adjust task counts based on load

**Target Tracking Policies:**
- **Tiles Service:**
  - Metric: Average CPU utilization
  - Target: 70%
  - Scale-out cooldown: 60 seconds
  - Scale-in cooldown: 300 seconds
  - Min tasks: 2, Max tasks: 10
- **Timeseries Service:**
  - Metric: Average CPU utilization
  - Target: 70%
  - Scale-out cooldown: 60 seconds
  - Scale-in cooldown: 300 seconds
  - Min tasks: 2, Max tasks: 20

**Step Scaling (Optional Enhancement):**
- If CPU > 80% for 2 minutes: Add 2 tasks
- If CPU < 30% for 5 minutes: Remove 1 task

**Interface:**
- Input: Service ARN, min/max capacity, target metrics
- Output: Autoscaling policy ARNs

### 4. CloudFront Distribution

**Purpose:** Cache tiles at edge locations, provide HTTPS endpoint

**Configuration:**
- **Origin:** ALB with HTTPS-only, custom origin headers
- **Cache Behaviors:**
  - Path: /tiles/*
    - Cache policy: 24-hour TTL
    - Query strings: All (for resampling parameter)
    - Compress: Yes
  - Path: /api/*
    - Cache policy: None (forward all)
  - Path: /metrics
    - Cache policy: None
- **SSL Certificate:** ACM certificate for custom domain (if provided)
- **Price Class:** PriceClass_All (or PriceClass_100 for cost optimization)
- **WAF:** Associate Web ACL if provided
- **Logging:** S3 bucket for access logs (optional)

**Interface:**
- Input: ALB DNS name, certificate ARN, domain name, WAF ACL ID
- Output: CloudFront distribution ID, domain name

### 5. Ingestion Pipeline

**Purpose:** Automatically convert uploaded NetCDF files to Zarr and COG and persist STAC metadata in DynamoDB

**Components:**

**S3 Event Trigger:**
- Bucket: raw-bucket
- Prefix: ingestion/
- Event: s3:ObjectCreated:*
- Target: Lambda function

**Trigger Lambda:**
- Runtime: Python 3.12
- Memory: 256 MB
- Timeout: 60 seconds
- Function: Parse S3 event, validate file, start Step Functions execution

**Step Functions State Machine:**
```
StartAt: ValidateInput
States:
  ValidateInput:
    Type: Task
    Resource: ValidateLambdaArn
    Next: ConvertToZarr
  ConvertToZarr:
    Type: Task
    Resource: ECS Task (or Lambda)
    Next: GenerateCOG
  GenerateCOG:
    Type: Task
    Resource: ECS Task (or Lambda)
    Next: CreateSTAC
  CreateSTAC:
    Type: Task
    Resource: CreateSTACLambdaArn
    Next: IndexSTAC
  IndexSTAC:
    Type: Task
    Resource: IndexSTACLambdaArn
    End: true
  ErrorHandler:
    Type: Fail
    Error: ConversionFailed
```

**Conversion Tasks:**
- **Zarr Conversion:**
  - ECS Task: 4 vCPU, 8GB RAM
  - Container: Python with xarray, zarr, dask
  - Process: Read NetCDF, rechunk, write to S3 Zarr store
- **COG Generation:**
  - ECS Task: 2 vCPU, 4GB RAM
  - Container: Python with rasterio, rio-cogeo
  - Process: Read variable, create overviews, write COG to S3

**STAC Creation Lambda:**
- Extract metadata (bbox, datetime, variables)
- Generate STAC item JSON
- Write to S3 STAC bucket

**STAC Indexing Lambda:**
- Read STAC item from S3
- Upsert item into DynamoDB STAC table (PK/SK + GSIs for spatial/temporal queries)
- Verify indexing success

**Error Handling:**
- CloudWatch Logs for all components
- SNS topic for failure notifications
- Dead letter queue for failed Lambda invocations

**Interface:**
- Input: S3 bucket names, ECS cluster ARN, SNS topic ARN
- Output: Step Functions ARN, Lambda ARNs

### 6. Dask Cluster

**Purpose:** Distributed computing for parallel timeseries processing

**Components:**

**Dask Scheduler:**
- ECS Service: 1 task (stable)
- CPU/Memory: 1 vCPU / 2GB RAM
- Port: 8786 (scheduler), 8787 (dashboard)
- Service Discovery: AWS Cloud Map for stable DNS
- Health Check: TCP port 8786

**Dask Workers:**
- ECS Service: 2-10 tasks (autoscaling)
- CPU/Memory: 2 vCPU / 4GB RAM per worker
- Environment: DASK_SCHEDULER_ADDRESS=tcp://{scheduler}:8786
- Autoscaling: Based on scheduler queue depth (custom metric)

**Network Configuration:**
- Private subnets
- Security group allowing scheduler ↔ worker communication
- Security group allowing timeseries service → scheduler

**Interface:**
- Input: VPC ID, subnets, security groups, ECS cluster ARN
- Output: Scheduler endpoint, worker service ARN

### 7. Security Infrastructure

**VPC Endpoints:**
- S3 Gateway Endpoint (no cost)
- DynamoDB Gateway Endpoint (no cost)
- ECR API and DKR endpoints
- CloudWatch Logs endpoint
- Secrets Manager endpoint (if using)

**Security Groups:**
- **ALB SG:** Ingress 443 from 0.0.0.0/0, egress to ECS SG
- **ECS SG:** Ingress 8080 from ALB SG, egress to all (for AWS services)
- **Dask SG:** Ingress 8786-8787 from ECS SG, egress to all
- **Redis SG:** Ingress 6379 from ECS SG

**IAM Policies:**
- **ECS Task Role:**
  - S3: GetObject, ListBucket on data buckets
  - DynamoDB: GetItem, Query, Scan, BatchGetItem, PutItem on STAC table + GSIs
  - CloudWatch: PutMetricData, CreateLogStream, PutLogEvents
- **Lambda Execution Role:**
  - S3: GetObject, PutObject
  - DynamoDB: PutItem, UpdateItem for STAC indexer Lambda
  - Step Functions: StartExecution
  - CloudWatch Logs: CreateLogGroup, CreateLogStream, PutLogEvents
- **Step Functions Role:**
  - Lambda: InvokeFunction
  - ECS: RunTask
  - SNS: Publish

**Encryption:**
- S3: SSE-S3 (AES-256) on all buckets
- DynamoDB: Encryption at rest (AWS-managed KMS)
- Redis: Encryption in transit enabled
- ALB: TLS 1.2+ only

**Interface:**
- Input: VPC ID, CIDR blocks, resource ARNs
- Output: Security group IDs, IAM role ARNs

### 8. CloudWatch Monitoring

**Log Groups:**
- /ecs/tiles-service (7-day retention)
- /ecs/timeseries-service (7-day retention)
- /ecs/dask-scheduler (7-day retention)
- /ecs/dask-workers (7-day retention)
- /aws/lambda/ingestion-trigger (7-day retention)
- /aws/lambda/stac-indexer (7-day retention)

**Metrics:**
- **Application Metrics (via Prometheus /metrics):**
  - raster_http_requests_total (counter)
  - raster_request_latency_seconds (histogram)
  - raster_uptime_seconds (gauge)
- **ECS Metrics:**
  - CPUUtilization
  - MemoryUtilization
  - TargetResponseTime (from ALB)
- **Custom Metrics:**
  - Cache hit ratio (Redis)
  - Dask queue depth
  - Ingestion pipeline success/failure rate

**Alarms:**
- High error rate (5xx > 5% for 5 minutes)
- High latency (p95 > 2s for 5 minutes)
- Service unavailable (HealthyHostCount < 1 for 2 minutes)
- Dask scheduler down (TCP check fails for 2 minutes)

**Dashboard:**
- Request rate and latency by endpoint
- ECS service health and task counts
- Cache hit ratios
- Error rates and types
- Dask cluster utilization

**Interface:**
- Input: Service names, alarm SNS topic ARN
- Output: Log group ARNs, alarm ARNs, dashboard URL

### 9. CI/CD Pipeline

**GitHub Actions Workflow:**

**Trigger:** Push to main branch, pull request

**Jobs:**

1. **Test:**
   - Checkout code
   - Set up Python 3.12
   - Install dependencies
   - Run pytest (unit tests and property-based tests)
   - Upload coverage report

2. **Build:**
   - Checkout code
   - Configure AWS credentials
   - Login to ECR
   - Build Docker image
   - Tag with commit SHA and 'latest'
   - Push to ECR

3. **Terraform Docs and Security:**
   - Checkout code
   - Install terraform-docs
   - Generate documentation for each module
   - Install checkov
   - Run checkov security scan on all Terraform modules
   - Fail if critical security issues found
   - Commit and push documentation if changes detected

4. **Deploy (on main branch only):**
   - Download task definition from ECS
   - Update image tag to new SHA
   - Register new task definition
   - Update ECS service
   - Wait for deployment to stabilize

5. **Smoke Tests:**
   - Wait 60 seconds for service to stabilize
   - Test /health endpoint
   - Test sample /tiles request
   - Test sample /api/timeseries request
   - Fail deployment if tests fail

**Secrets:**
- AWS_ACCESS_KEY_ID
- AWS_SECRET_ACCESS_KEY
- AWS_REGION
- ECR_REPOSITORY
- ECS_CLUSTER
- ECS_SERVICE_TILES
- ECS_SERVICE_TIMESERIES

**Interface:**
- Input: GitHub repository, AWS credentials
- Output: Deployed services, test results

### 10. Terraform Module Structure

**Root Module (terraform/):**
- Orchestrates all child modules
- Defines variables and outputs
- Manages state backend

**Network Module (terraform/modules/network/):**
- VPC, subnets, route tables, internet gateway
- Security groups for ALB, ECS, Dask, Redis
- VPC endpoints (S3, DynamoDB gateway; ECR; CloudWatch Logs)
- Outputs: VPC ID, subnet IDs, security group IDs

**IAM Module (terraform/modules/iam/):**
- ECS task role and execution role
- Lambda execution roles
- Step Functions role
- Policies for S3, DynamoDB (STAC table/GSI), CloudWatch
- Outputs: Role ARNs

**Data Module (terraform/modules/data/):**
- S3 buckets (raw, zarr, cog, stac)
- DynamoDB STAC table (PK/SK + GSIs for spatial/temporal)
- ElastiCache Redis cluster
- Optional RDS PostgreSQL
- Outputs: Bucket names, DynamoDB table/GSIs, endpoints

**ECS Module (terraform/modules/ecs/):**
- ECR repository
- ECS cluster
- Task definitions (tiles, timeseries, dask-scheduler, dask-workers)
- ECS services
- ALB, target groups, listeners
- Autoscaling policies
- Outputs: ALB DNS, service ARNs

**CloudFront Module (terraform/modules/cloudfront/):**
- CloudFront distribution
- Origin configuration
- Cache behaviors
- WAF association
- Outputs: Distribution ID, domain name

**Ingestion Module (terraform/modules/ingestion/):**
- Lambda functions
- Step Functions state machine
- S3 event notifications
- SNS topics
- Outputs: State machine ARN

**Monitoring Module (terraform/modules/monitoring/):**
- CloudWatch log groups
- CloudWatch alarms
- CloudWatch dashboard
- SNS topics for alerts
- Outputs: Log group ARNs, alarm ARNs

**Tagging Strategy:**
- All resources tagged with:
  - project_owner: {owner-name}
  - project_title: {project-name}
  - environment: {dev|staging|prod}
  - managed_by: terraform

## Data Models

### ECS Task Definition

```hcl
{
  family: "tiles-service"
  network_mode: "awsvpc"
  requires_compatibilities: ["FARGATE"]
  cpu: "1024"
  memory: "2048"
  execution_role_arn: "{execution-role-arn}"
  task_role_arn: "{task-role-arn}"
  container_definitions: [
    {
      name: "tiles"
      image: "{ecr-repo}:latest"
      port_mappings: [{ container_port: 8080, protocol: "tcp" }]
      environment: [
        { name: "AWS_REGION", value: "ap-southeast-2" },
        { name: "S3_COG_PREFIX", value: "s3://{cog-bucket}/" },
        ...
      ]
      log_configuration: {
        log_driver: "awslogs"
        options: {
          "awslogs-group": "/ecs/tiles-service"
          "awslogs-region": "ap-southeast-2"
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]
}
```

### CloudFront Cache Policy

```json
{
  "Name": "TileCachePolicy",
  "MinTTL": 3600,
  "MaxTTL": 86400,
  "DefaultTTL": 86400,
  "ParametersInCacheKeyAndForwardedToOrigin": {
    "EnableAcceptEncodingGzip": true,
    "QueryStringsConfig": {
      "QueryStringBehavior": "all"
    },
    "HeadersConfig": {
      "HeaderBehavior": "none"
    },
    "CookiesConfig": {
      "CookieBehavior": "none"
    }
  }
}
```

### Step Functions State Machine Input

```json
{
  "bucket": "raw-bucket",
  "key": "ingestion/dataset-2024-01-01.nc",
  "variable": "temperature",
  "metadata": {
    "source": "weather-station-1",
    "datetime": "2024-01-01T00:00:00Z"
  }
}
```

### Terraform Variables

```hcl
variable "project_owner" {
  type        = string
  description = "Owner of the project for resource tagging"
}

variable "project_title" {
  type        = string
  description = "Title of the project for resource tagging"
}

variable "environment" {
  type        = string
  description = "Environment name (dev, staging, prod)"
  default     = "dev"
}
```

## Error Handling

### ECS Service Failures

**Scenario:** Task fails health checks or crashes

**Handling:**
- ECS automatically replaces failed tasks
- CloudWatch alarm triggers if HealthyHostCount < minimum
- SNS notification sent to operators
- Logs available in CloudWatch for debugging

**Recovery:**
- Review logs to identify root cause
- Fix code or configuration issue
- Deploy new task definition
- Monitor health checks

### Ingestion Pipeline Failures

**Scenario:** NetCDF conversion fails

**Handling:**
- Step Functions catches error in state machine
- Transitions to error handler state
- Logs error details to CloudWatch
- Publishes failure notification to SNS
- Original file remains in S3 for retry

**Recovery:**
- Review CloudWatch logs for error details
- Fix conversion logic or input validation
- Manually trigger Step Functions execution for failed file
- Monitor execution progress

### Dask Cluster Failures

**Scenario:** Dask scheduler becomes unavailable

**Handling:**
- Timeseries API falls back to local processing (if configured)
- CloudWatch alarm triggers on scheduler health check failure
- ECS automatically restarts scheduler task
- Workers reconnect when scheduler is available

**Recovery:**
- Verify scheduler task is running
- Check scheduler logs for errors
- Restart worker tasks if needed
- Test timeseries API functionality

### DynamoDB Unavailability

**Scenario:** DynamoDB STAC table or endpoint is unreachable (API throttling or regional outage)

**Handling:**
- Application retries with exponential backoff (tenacity library)
- After max retries, returns 503 Service Unavailable
- CloudWatch alarm triggers on high error rate
- Logs connection errors

**Recovery:**
- Check DynamoDB service status / AWS Health
- Verify IAM permissions and VPC endpoint configuration
- Inspect throttle metrics (ConsumedCapacity) and increase RCUs/WCUs or add backoff
- Fallback: reprocess recent ingestion items once connectivity is restored

### Cache Failures

**Scenario:** Redis becomes unavailable

**Handling:**
- Application catches Redis connection errors
- Falls back to direct computation without caching
- Logs warning but continues processing
- CloudWatch metric tracks cache miss rate

**Recovery:**
- Check ElastiCache cluster status
- Verify security group rules
- Restart Redis cluster if needed
- Monitor cache hit rate after recovery

### Autoscaling Issues

**Scenario:** Service cannot scale out due to resource limits

**Handling:**
- ECS logs scaling failures
- CloudWatch alarm triggers on sustained high CPU
- Service continues with current capacity
- Requests may experience higher latency

**Recovery:**
- Review service quotas in AWS console
- Request quota increase if needed
- Optimize application code to reduce resource usage
- Consider larger task sizes

## Testing Strategy

### Unit Testing

**Framework:** pytest with pytest-asyncio

**Coverage:**
- **Tiles Module:**
  - Test COG lookup from DynamoDB (STAC table) with hash/range keys
  - Test tile rendering with various resampling methods
  - Test nodata handling
  - Test error cases (collection not found, invalid coordinates)
- **Timeseries Module:**
  - Test STAC search with various parameters (GSI queries)
  - Test Zarr reading and aggregation
  - Test cache key generation
  - Test error cases (no data found, invalid coordinates)
- **Auth Module:**
  - Test JWT validation with valid token
  - Test JWT validation with expired token
  - Test JWT validation with invalid signature
  - Test missing authorization header
- **Cache Module:**
  - Test cache get/set operations
  - Test TTL expiration
  - Test JSON serialization

**Mocking:**
- Mock DynamoDB client/table responses
- Mock S3/Zarr file access
- Mock Redis operations
- Mock Cognito JWKS endpoint

**Example:**
```python
def test_tile_generation_success(mock_dynamodb_table, mock_cog):
  # Arrange
  mock_dynamodb_table.query.return_value = {
    "Items": [{"assets": {"cog": {"href": "s3://..."}}}]
  }
  # Act
  response = client.get("/tiles/collection1/10/512/512.png")
  # Assert
  assert response.status_code == 200
  assert response.headers["content-type"] == "image/png"
```

### Property-Based Testing

**Framework:** Hypothesis

**Properties to Test:**
- Tile coordinates: For any valid z/x/y, tile generation should succeed or return 404
- Timeseries aggregation: For any lon/lat within dataset bounds, result should be sorted by time
- Cache consistency: For any cache key, get(set(key, value)) should return value
- STAC search: For any bounding box, all results should intersect the box

**Generators:**
- Valid tile coordinates (z: 0-20, x/y within bounds for z)
- Geographic coordinates (lon: -180 to 180, lat: -90 to 90)
- ISO datetime strings
- Variable names from known list

**Example:**
```python
from hypothesis import given, strategies as st

@given(
    lon=st.floats(min_value=-180, max_value=180),
    lat=st.floats(min_value=-90, max_value=90),
    start=st.datetimes(),
    end=st.datetimes()
)
def test_timeseries_sorted(lon, lat, start, end):
    # Assume start < end
    if start >= end:
        start, end = end, start
    
    result = get_timeseries(lon, lat, start.isoformat(), end.isoformat(), "temp")
    times = result["times"]
    
    # Property: times should be sorted
    assert times == sorted(times)
```

### Integration Testing

**Scope:** Test interactions between components

**Tests:**
- **End-to-End Tile Request:**
  - Start services with test DynamoDB (STAC table) and S3
  - Upload test COG to S3
  - Index test STAC item (DynamoDB put)
  - Request tile via API
  - Verify PNG response
- **End-to-End Timeseries Request:**
  - Upload test Zarr to S3
  - Index test STAC items (DynamoDB put)
  - Request timeseries via API
  - Verify JSON response with expected values
- **Ingestion Pipeline:**
  - Upload test NetCDF to S3
  - Trigger Lambda
  - Wait for Step Functions completion
  - Verify Zarr and COG created
  - Verify STAC item indexed in DynamoDB

**Environment:**
- LocalStack for AWS services (S3, Lambda, Step Functions, DynamoDB)
- Docker Compose for Redis, Dask
- Test data fixtures

### Infrastructure Testing

**Framework:** Terratest (Go) or pytest-terraform

**Tests:**
- **Terraform Validation:**
  - terraform validate passes
  - terraform plan succeeds
  - No syntax errors
- **Module Outputs:**
  - ECS module outputs ALB DNS name
  - Data module outputs bucket names
  - IAM module outputs role ARNs
- **Resource Tagging:**
  - All resources have required tags
  - Tag values match input variables
- **Security:**
  - Security groups have no overly permissive rules
  - S3 buckets have encryption enabled
  - IAM policies follow least privilege

**Example:**
```go
func TestECSModule(t *testing.T) {
    terraformOptions := &terraform.Options{
        TerraformDir: "../modules/ecs",
        Vars: map[string]interface{}{
            "name": "test",
            "vpc_id": "vpc-12345",
            ...
        },
    }
    
    defer terraform.Destroy(t, terraformOptions)
    terraform.InitAndApply(t, terraformOptions)
    
    albDns := terraform.Output(t, terraformOptions, "alb_dns_name")
    assert.NotEmpty(t, albDns)
}
```

### Smoke Testing (CI/CD)

**Purpose:** Verify deployment succeeded

**Tests:**
- Health endpoint returns 200
- Sample tile request returns 200 with PNG
- Sample timeseries request returns 200 with JSON
- Metrics endpoint returns Prometheus format

**Execution:**
- Run after ECS service update
- Fail deployment if any test fails
- Retry up to 3 times with backoff

**Example:**
```bash
#!/bin/bash
set -e

ALB_URL="https://api.example.com"

# Test health
curl -f "$ALB_URL/health"

# Test tile
curl -f "$ALB_URL/tiles/test-collection/10/512/512.png" -o /tmp/tile.png
file /tmp/tile.png | grep PNG

# Test timeseries
curl -f "$ALB_URL/api/timeseries?lon=150&lat=-33&start=2024-01-01&end=2024-01-31&variable=temp"

echo "All smoke tests passed"
```


## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system—essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property Reflection

After analyzing all acceptance criteria, I identified several properties that apply universally across resources rather than to specific examples. Many acceptance criteria are specific configuration checks (examples) rather than universal properties. The key universal properties are:

1. **Autoscaling bounds** - Task counts must stay within min/max limits for all scaling events
2. **HTTPS enforcement** - All HTTP requests must be redirected to HTTPS
3. **S3 encryption and versioning** - All S3 buckets must have these features enabled
4. **Module reference consistency** - All module references must use outputs, not hardcoded values
5. **Resource tagging** - All resources must have required tags

These properties are not redundant with each other as they cover different aspects: autoscaling behavior, security enforcement, storage configuration, infrastructure code quality, and resource management.

### Properties

**Property 1: Autoscaling respects capacity bounds**

*For any* autoscaling event triggered by CPU utilization or other metrics, the resulting task count must be greater than or equal to the minimum capacity and less than or equal to the maximum capacity.

**Validates: Requirements 2.3**

---

**Property 2: HTTPS enforcement**

*For any* HTTP request to the CloudFront distribution, the system must redirect to the HTTPS equivalent URL with a 301 or 302 status code.

**Validates: Requirements 3.4**

---

**Property 3: S3 bucket security configuration**

*For any* S3 bucket created by the Terraform configuration, the bucket must have server-side encryption enabled and versioning enabled.

**Validates: Requirements 6.4**

---

**Property 4: Module reference consistency**

*For any* Terraform module reference to another module's resource, the reference must use the module's output value rather than a hardcoded resource identifier.

**Validates: Requirements 9.4**

---

**Property 5: Resource tagging completeness**

*For any* AWS resource created by Terraform that supports tagging, the resource must have tags for project_owner and project_title with non-empty values.

**Validates: Requirements 9.6**

---

### Example-Based Tests

The following acceptance criteria are best validated through specific example tests rather than universal properties:

- Infrastructure creation tests (1.1-1.5, 5.1-5.3, 7.1, 9.1-9.3, 10.1-10.4)
- Specific configuration tests (3.1-3.3, 3.5, 6.1-6.3, 6.5)
- Behavioral tests (2.1-2.2, 2.4, 4.1-4.5, 5.4-5.5, 7.2-7.5, 8.1-8.6)

These will be covered by unit tests, integration tests, and infrastructure tests as described in the Testing Strategy section.
