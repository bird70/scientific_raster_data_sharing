# Requirements Document

## Introduction

This document specifies the requirements for completing the Raster Time-series Access Web Service infrastructure and application deployment. The system provides performant web/API access to large raster datasets (NetCDF converted to Zarr and COG), including interactive map tiles and point-based timeseries extraction. The existing codebase has application logic and partial infrastructure, but is missing critical deployment components including ECS task definitions, ingestion pipeline, CDN, and autoscaling.

## Glossary

- **ECS (Elastic Container Service)**: AWS container orchestration service for running Docker containers
- **Task Definition**: ECS blueprint that describes how a Docker container should run
- **Service**: ECS component that maintains a desired count of task instances
- **ALB (Application Load Balancer)**: AWS load balancer that routes HTTP/HTTPS traffic to targets
- **Target Group**: Collection of targets (ECS tasks) that receive traffic from a load balancer
- **CloudFront**: AWS CDN service for caching and distributing content globally
- **Fargate**: AWS serverless compute engine for containers
- **Autoscaling**: Automatic adjustment of compute resources based on demand
- **COG (Cloud-Optimized GeoTIFF)**: Raster format optimized for cloud storage and partial reads
- **Zarr**: Chunked, compressed array storage format for cloud-native data access
- **STAC (SpatioTemporal Asset Catalog)**: Specification for describing geospatial data
- **OpenSearch**: Distributed search and analytics engine (AWS managed)
- **Redis**: In-memory data store used for caching
- **Dask**: Distributed computing framework for parallel processing
- **Lambda**: AWS serverless compute service for running code without managing servers
- **Step Functions**: AWS service for orchestrating workflows
- **Cognito**: AWS service for user authentication and authorization
- **WAF (Web Application Firewall)**: AWS service for protecting web applications from attacks

## Requirements

### Requirement 1

**User Story:** As a platform operator, I want ECS task definitions and services configured, so that the containerized application can run on AWS with proper resource allocation and health monitoring.

#### Acceptance Criteria

1. WHEN the Terraform configuration is applied THEN the system SHALL create ECS task definitions for the tiles and timeseries services with appropriate CPU, memory, and container configurations
2. WHEN the ECS task definition is created THEN the system SHALL reference the ECR repository, configure environment variables for OpenSearch, Redis, S3, and Cognito, and assign the IAM task role
3. WHEN the ECS services are created THEN the system SHALL launch tasks in private subnets, register them with the appropriate ALB target groups, and configure health checks
4. WHEN the ECS services are running THEN the system SHALL maintain the desired count of tasks and automatically replace unhealthy tasks
5. WHEN the ALB health check endpoint is queried THEN the system SHALL return a 200 status code indicating service health

### Requirement 2

**User Story:** As a platform operator, I want autoscaling policies configured for ECS services, so that the system can handle variable load while controlling costs.

#### Acceptance Criteria

1. WHEN CPU utilization exceeds 70% for 2 consecutive minutes THEN the system SHALL scale out by adding one task instance
2. WHEN CPU utilization falls below 30% for 5 consecutive minutes THEN the system SHALL scale in by removing one task instance
3. WHEN scaling actions occur THEN the system SHALL respect minimum and maximum task count limits
4. WHEN the system scales THEN the system SHALL emit CloudWatch metrics tracking scaling events and current task counts

### Requirement 3

**User Story:** As a platform operator, I want CloudFront CDN configured in front of the ALB, so that tile requests are cached at edge locations for improved performance.

#### Acceptance Criteria

1. WHEN a CloudFront distribution is created THEN the system SHALL configure the ALB as the origin with HTTPS-only communication
2. WHEN tile requests match the path pattern "/tiles/*" THEN the system SHALL cache responses for 24 hours with query string forwarding
3. WHEN API requests match the path pattern "/api/*" THEN the system SHALL forward requests without caching
4. WHEN CloudFront receives requests THEN the system SHALL enforce HTTPS and redirect HTTP to HTTPS
5. WHERE a custom domain is provided THEN the system SHALL configure the CloudFront distribution with the SSL certificate and domain alias

### Requirement 4

**User Story:** As a platform operator, I want the ingestion pipeline infrastructure defined, so that uploaded NetCDF files can be automatically converted to Zarr and COG formats.

#### Acceptance Criteria

1. WHEN a NetCDF file is uploaded to the raw S3 bucket with the ingestion prefix THEN the system SHALL trigger a Lambda function to initiate conversion
2. WHEN the conversion Lambda is invoked THEN the system SHALL start a Step Functions workflow that orchestrates the conversion process
3. WHEN the Step Functions workflow executes THEN the system SHALL invoke Lambda functions or ECS tasks to convert NetCDF to Zarr and generate COG with overviews
4. WHEN conversion completes successfully THEN the system SHALL create a STAC item with metadata and index it in OpenSearch
5. WHEN conversion fails THEN the system SHALL log errors to CloudWatch and send notifications via SNS

### Requirement 5

**User Story:** As a platform operator, I want Dask cluster infrastructure defined, so that timeseries queries can be processed in parallel across multiple workers.

#### Acceptance Criteria

1. WHEN the Terraform configuration is applied THEN the system SHALL create an ECS service for the Dask scheduler with a stable endpoint
2. WHEN the Dask scheduler is running THEN the system SHALL create an ECS service for Dask workers that connect to the scheduler
3. WHEN the Dask worker service is created THEN the system SHALL configure autoscaling based on scheduler queue depth or CPU utilization
4. WHEN the timeseries API receives requests THEN the system SHALL connect to the Dask scheduler for distributed computation
5. WHEN Dask workers process tasks THEN the system SHALL have IAM permissions to read from S3 Zarr buckets

### Requirement 6

**User Story:** As a platform operator, I want security infrastructure configured, so that the application is protected from common web attacks and unauthorized access.

#### Acceptance Criteria

1. WHERE a WAF web ACL ID is provided THEN the system SHALL associate it with the CloudFront distribution
2. WHEN the ECS tasks are created THEN the system SHALL run them in private subnets with no direct internet access
3. WHEN the ECS tasks need to access AWS services THEN the system SHALL use VPC endpoints for S3, OpenSearch, and other services to avoid internet routing
4. WHEN S3 buckets are created THEN the system SHALL enable server-side encryption and versioning
5. WHEN IAM roles are created THEN the system SHALL follow least-privilege principles with specific resource ARNs

### Requirement 7

**User Story:** As a platform operator, I want CloudWatch logging and monitoring configured, so that I can troubleshoot issues and track system performance.

#### Acceptance Criteria

1. WHEN ECS tasks are created THEN the system SHALL configure CloudWatch log groups with retention policies
2. WHEN the application logs messages THEN the system SHALL send structured logs to CloudWatch with appropriate log levels
3. WHEN the system is running THEN the system SHALL emit CloudWatch metrics for request counts, latencies, error rates, and cache hit ratios
4. WHEN CloudWatch alarms are configured THEN the system SHALL trigger notifications for high error rates, elevated latencies, or service unavailability
5. WHEN operators need to investigate issues THEN the system SHALL provide CloudWatch dashboards showing key metrics and logs

### Requirement 8

**User Story:** As a developer, I want CI/CD pipeline configuration, so that code changes can be automatically built, tested, and deployed.

#### Acceptance Criteria

1. WHEN code is pushed to the main branch THEN the system SHALL trigger a GitHub Actions workflow to build the Docker image
2. WHEN the Docker image is built THEN the system SHALL run unit tests and property-based tests before pushing to ECR
3. WHEN tests pass and the image is pushed to ECR THEN the system SHALL update the ECS task definition with the new image tag
4. WHEN the ECS task definition is updated THEN the system SHALL trigger a rolling deployment of the ECS services
5. WHEN deployment completes THEN the system SHALL run smoke tests against the health endpoint and sample API endpoints
6. WHEN Terraform configuration changes are pushed THEN the system SHALL run terraform-docs to automatically generate documentation for all modules
7. WHEN Terraform configuration changes are pushed THEN the system SHALL run checkov security scanning and fail the build if critical security issues are detected

### Requirement 9

**User Story:** As a platform operator, I want missing Terraform variables and outputs defined, so that modules can properly reference each other and external values can be provided.

#### Acceptance Criteria

1. WHEN the ECS module is invoked THEN the system SHALL accept variables for VPC ID, subnet IDs, security group IDs, IAM role ARN, certificate ARN, and service configuration
2. WHEN the ECS module completes THEN the system SHALL output the ALB DNS name, CloudFront distribution ID, and ECS cluster name
3. WHEN the data module is invoked THEN the system SHALL accept variables for VPC security group IDs
4. WHEN modules reference each other THEN the system SHALL use output values rather than hardcoded strings
5. WHEN the root Terraform configuration is applied THEN the system SHALL validate that all required variables are provided
6. WHEN Terraform resources are created THEN the system SHALL tag all resources with project_owner and project_title tags for resource management and cost tracking

### Requirement 10

**User Story:** As a platform operator, I want the data module Terraform syntax errors fixed, so that the infrastructure can be successfully deployed.

#### Acceptance Criteria

1. WHEN the data module main.tf is parsed THEN the system SHALL not encounter syntax errors
2. WHEN S3 bucket resources are defined THEN the system SHALL use valid HCL syntax for nested blocks
3. WHEN the Terraform configuration is validated THEN the system SHALL pass validation without errors
4. WHEN the Terraform configuration is applied THEN the system SHALL successfully create all data resources
