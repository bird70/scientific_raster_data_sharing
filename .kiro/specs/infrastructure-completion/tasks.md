# Implementation Plan

- [x] 1. Fix Terraform data module syntax errors
  - Fix the typo in terraform/modules/data/main.tf (missing 'r' in 'resource')
  - Fix S3 bucket encryption and versioning syntax to use proper nested block structure
  - Add missing variable definitions for vpc_sg_id
  - Add random provider configuration
  - _Requirements: 10.1, 10.2, 10.3, 10.4_

- [x] 2. Add Terraform tagging infrastructure
  - Add project_owner and project_title variables to root variables.tf
  - Add environment variable to root variables.tf
  - Create locals block in root main.tf to define common tags
  - Update all module invocations to pass tag variables
  - _Requirements: 9.6_

- [x] 3. Update network module with tagging and missing resources
  - Add tag variables to network module variables.tf
  - Apply tags to all network resources (VPC, subnets, security groups, IGW)
  - Add missing ECS tasks security group output
  - Add VPC endpoints for S3, ECR, CloudWatch, OpenSearch
  - _Requirements: 6.3, 9.6_

- [x] 4. Update IAM module with tagging and missing roles
  - Add tag variables to IAM module
  - Add ECS execution role (separate from task role)
  - Add Lambda execution role for ingestion pipeline
  - Add Step Functions execution role
  - Fix region variable reference in IAM module
  - Apply tags to all IAM roles
  - _Requirements: 4.5, 6.5, 9.6_

- [x] 5. Update data module with tagging and fixes
  - Add tag variables to data module
  - Apply tags to all S3 buckets, OpenSearch domain, ElastiCache cluster
  - Fix S3 bucket encryption and versioning syntax
  - Add lifecycle rules for S3 buckets
  - Fix OpenSearch and ElastiCache security group references
  - _Requirements: 6.4, 9.3, 9.6_

- [x] 6. Complete ECS module with task definitions and services
- [x] 6.1 Add missing variables to ECS module
  - Add variables.tf with all required inputs (task_role_arn, execution_role_arn, image_uri, environment variables, etc.)
  - Add outputs.tf with ALB DNS name, cluster name, service ARNs
  - _Requirements: 9.1, 9.2_

- [x] 6.2 Create CloudWatch log groups
  - Add log groups for tiles-service, timeseries-service
  - Set 7-day retention policy
  - Apply tags
  - _Requirements: 7.1, 9.6_

- [x] 6.3 Create ECS task definitions
  - Create task definition for tiles service (1 vCPU, 2GB RAM)
  - Create task definition for timeseries service (2 vCPU, 4GB RAM)
  - Configure container definitions with image URI, port mappings, environment variables
  - Configure CloudWatch logging
  - Assign task role and execution role
  - Apply tags
  - _Requirements: 1.1, 1.2, 9.6_

- [x] 6.4 Create ECS services
  - Create tiles service with desired count 2
  - Create timeseries service with desired count 2
  - Configure network (private subnets, security groups)
  - Attach to ALB target groups
  - Configure health check grace period
  - Enable service discovery (optional)
  - Apply tags
  - _Requirements: 1.3, 1.4, 9.6_

- [x] 6.5 Configure autoscaling policies
  - Create autoscaling target for tiles service (min 2, max 10)
  - Create autoscaling target for timeseries service (min 2, max 20)
  - Create target tracking policy for CPU utilization (70% target)
  - Configure scale-out and scale-in cooldowns
  - _Requirements: 2.1, 2.2, 2.3, 2.4_

- [ ]* 6.6 Write property test for autoscaling bounds
  - **Property 1: Autoscaling respects capacity bounds**
  - **Validates: Requirements 2.3**

- [x] 7. Create CloudFront module
  - Create terraform/modules/cloudfront directory
  - Create main.tf with CloudFront distribution resource
  - Configure ALB as origin with HTTPS-only
  - Create cache behavior for /tiles/* (24-hour TTL, query string forwarding)
  - Create cache behavior for /api/* (no caching)
  - Configure HTTPS enforcement and HTTP to HTTPS redirect
  - Add conditional SSL certificate and domain alias configuration
  - Add WAF association (conditional)
  - Create variables.tf and outputs.tf
  - Apply tags
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 6.1, 9.6_

- [ ]* 7.1 Write property test for HTTPS enforcement
  - **Property 2: HTTPS enforcement**
  - **Validates: Requirements 3.4**

- [x] 8. Create Dask cluster infrastructure
- [x] 8.1 Create Dask task definitions
  - Create task definition for Dask scheduler (1 vCPU, 2GB RAM)
  - Create task definition for Dask workers (2 vCPU, 4GB RAM)
  - Configure environment variables (DASK_SCHEDULER_ADDRESS for workers)
  - Configure CloudWatch logging
  - Apply tags
  - _Requirements: 5.1, 9.6_

- [x] 8.2 Create Dask services
  - Create Cloud Map namespace for service discovery
  - Create Dask scheduler service with service discovery
  - Create Dask worker service
  - Configure network and security groups
  - Apply tags
  - _Requirements: 5.2, 9.6_

- [x] 8.3 Configure Dask worker autoscaling
  - Create autoscaling target for workers (min 2, max 10)
  - Create target tracking policy based on CPU utilization
  - _Requirements: 5.3_

- [ ] 9. Create ingestion pipeline module
- [ ] 9.1 Create Lambda functions
  - Create terraform/modules/ingestion directory
  - Create trigger Lambda function (Python 3.12, 256MB, 60s timeout)
  - Create STAC creation Lambda function
  - Create STAC indexing Lambda function
  - Package Lambda code as zip files
  - Configure environment variables
  - Assign IAM roles
  - Apply tags
  - _Requirements: 4.1, 4.2, 4.4, 9.6_

- [ ] 9.2 Create Step Functions state machine
  - Define state machine with validation, conversion, COG generation, STAC creation, and indexing states
  - Configure error handling and retry logic
  - Assign IAM role
  - Apply tags
  - _Requirements: 4.2, 4.3, 4.5, 9.6_

- [ ] 9.3 Create S3 event notification
  - Configure S3 bucket notification for raw bucket
  - Set prefix filter to "ingestion/"
  - Set event type to s3:ObjectCreated:*
  - Target trigger Lambda function
  - _Requirements: 4.1_

- [ ] 9.4 Create SNS topic for notifications
  - Create SNS topic for ingestion failures
  - Configure Step Functions to publish to topic on error
  - Apply tags
  - _Requirements: 4.5, 9.6_

- [ ] 10. Create monitoring module
- [ ] 10.1 Create CloudWatch alarms
  - Create terraform/modules/monitoring directory
  - Create alarm for high error rate (5xx > 5% for 5 minutes)
  - Create alarm for high latency (p95 > 2s for 5 minutes)
  - Create alarm for service unavailability (HealthyHostCount < 1 for 2 minutes)
  - Create alarm for Dask scheduler health
  - Configure SNS topic for alarm notifications
  - Apply tags
  - _Requirements: 7.4, 9.6_

- [ ] 10.2 Create CloudWatch dashboard
  - Create dashboard with widgets for request rate, latency, error rate
  - Add widgets for ECS service health and task counts
  - Add widgets for cache hit ratios
  - Add widgets for Dask cluster utilization
  - _Requirements: 7.5_

- [ ] 11. Update root Terraform configuration
  - Add CloudFront module invocation to main.tf
  - Add monitoring module invocation to main.tf
  - Add ingestion module invocation to main.tf
  - Update ECS module invocation with all required variables
  - Pass common tags to all modules
  - Update outputs.tf with CloudFront domain, ECS cluster name
  - _Requirements: 9.4, 9.5_

- [ ]* 11.1 Write property test for S3 bucket security
  - **Property 3: S3 bucket security configuration**
  - **Validates: Requirements 6.4**

- [ ]* 11.2 Write property test for module references
  - **Property 4: Module reference consistency**
  - **Validates: Requirements 9.4**

- [ ]* 11.3 Write property test for resource tagging
  - **Property 5: Resource tagging completeness**
  - **Validates: Requirements 9.6**

- [ ] 12. Create GitHub Actions CI/CD workflow
- [ ] 12.1 Create workflow file
  - Create .github/workflows/deploy.yml
  - Configure triggers (push to main, pull request)
  - Set up AWS credentials from secrets
  - _Requirements: 8.1_

- [ ] 12.2 Add test job
  - Set up Python 3.12
  - Install dependencies from requirements.txt
  - Run pytest with coverage
  - Upload coverage report
  - _Requirements: 8.2_

- [ ] 12.3 Add build job
  - Configure AWS credentials
  - Login to ECR
  - Build Docker image
  - Tag with commit SHA and 'latest'
  - Push to ECR
  - _Requirements: 8.2, 8.3_

- [ ] 12.4 Add Terraform documentation and security job
  - Install terraform-docs
  - Generate documentation for all modules
  - Install checkov
  - Run checkov security scan on all Terraform modules
  - Fail if critical security issues found
  - Commit and push documentation changes
  - _Requirements: 8.6, 8.7_

- [ ] 12.5 Add deploy job
  - Download current task definition from ECS
  - Update image tag to new commit SHA
  - Register new task definition
  - Update ECS services (tiles and timeseries)
  - Wait for deployment to stabilize
  - _Requirements: 8.3, 8.4_

- [ ] 12.6 Add smoke test job
  - Wait 60 seconds for service stabilization
  - Test /health endpoint returns 200
  - Test sample /tiles request returns PNG
  - Test sample /api/timeseries request returns JSON
  - Test /metrics endpoint returns Prometheus format
  - Fail deployment if any test fails
  - _Requirements: 8.5_

- [ ] 13. Create Lambda function code for ingestion pipeline
- [ ] 13.1 Create trigger Lambda code
  - Create app/lambda/trigger/handler.py
  - Parse S3 event and extract bucket/key
  - Validate file extension is .nc
  - Start Step Functions execution with file metadata
  - Handle errors and log to CloudWatch
  - _Requirements: 4.1, 4.2_

- [ ] 13.2 Create STAC creation Lambda code
  - Create app/lambda/stac_creator/handler.py
  - Read Zarr metadata from S3
  - Extract bbox, datetime, variables
  - Generate STAC item JSON
  - Write to S3 STAC bucket
  - _Requirements: 4.4_

- [ ] 13.3 Create STAC indexing Lambda code
  - Create app/lambda/stac_indexer/handler.py
  - Read STAC item from S3
  - Connect to OpenSearch
  - Index STAC item
  - Verify indexing success
  - Handle errors and send SNS notification on failure
  - _Requirements: 4.4, 4.5_

- [ ] 14. Update application configuration
  - Update app/app/config.py to handle optional DASK_SCHEDULER
  - Update app/app/timeseries.py to gracefully handle Dask unavailability
  - Ensure all environment variables have sensible defaults
  - _Requirements: 5.4_

- [ ] 15. Create Terraform documentation
  - Create README.md for each Terraform module
  - Document variables, outputs, and usage examples
  - Create root README.md with architecture overview
  - _Requirements: 8.6_

- [ ] 16. Checkpoint - Validate Terraform configuration
  - Run terraform init in root directory
  - Run terraform validate
  - Run terraform plan with sample variables
  - Ensure no errors
  - _Requirements: 10.3_

- [ ]* 17. Write infrastructure tests
  - Create tests/terraform directory
  - Write tests for module variable validation
  - Write tests for module output validation
  - Write tests for resource tagging
  - Write tests for security group rules
  - _Requirements: 9.1, 9.2, 9.3, 9.6_

- [ ]* 18. Write integration tests for ingestion pipeline
  - Create tests/integration/test_ingestion.py
  - Test S3 upload triggers Lambda
  - Test Step Functions execution completes
  - Test STAC item is indexed in OpenSearch
  - Test error handling and notifications
  - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_

- [ ]* 19. Write integration tests for Dask cluster
  - Create tests/integration/test_dask.py
  - Test Dask scheduler is reachable
  - Test workers connect to scheduler
  - Test timeseries API uses Dask for computation
  - Test IAM permissions for S3 access
  - _Requirements: 5.1, 5.2, 5.4, 5.5_

- [ ] 20. Final checkpoint - End-to-end validation
  - Ensure all tests pass, ask the user if questions arise
