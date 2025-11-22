# ECS Module

This module creates the ECS cluster, task definitions, services, Application Load Balancer, and Dask cluster for the Raster Time-series Access Web Service.

## Architecture

The module deploys containerized services on AWS Fargate:
- **Tiles Service**: Serves map tiles from COG files (2 tasks, scales to 10)
- **Timeseries Service**: Extracts timeseries from Zarr data (2 tasks, scales to 20)
- **Dask Scheduler**: Coordinates distributed computation (1 task, stable)
- **Dask Workers**: Execute parallel tasks (2 tasks, scales to 10)

All services are fronted by an Application Load Balancer with path-based routing.

## Components

### ECR Repository

Private Docker registry for application images:
- Mutable tags for development workflow
- Stores tiles and timeseries service images

### Application Load Balancer

HTTPS load balancer with path-based routing:
- **Port 443**: HTTPS listener with ACM certificate
- **Path `/tiles/*`**: Routes to tiles service
- **Path `/api/*`**: Routes to timeseries service
- **Default**: Returns 404

Health checks on `/health` endpoint with 200-399 matcher.

### ECS Cluster

Fargate cluster hosting all services:
- Serverless compute (no EC2 management)
- Automatic scaling based on CPU utilization
- CloudWatch Container Insights enabled

### Task Definitions

#### Tiles Service
- **CPU**: 1 vCPU (1024)
- **Memory**: 2GB (2048)
- **Port**: 8080
- **Environment**: S3 COG bucket, OpenSearch, Redis, Cognito
- **Logging**: CloudWatch Logs (7-day retention)

#### Timeseries Service
- **CPU**: 2 vCPU (2048)
- **Memory**: 4GB (4096)
- **Port**: 8080
- **Environment**: S3 Zarr bucket, OpenSearch, Redis, Cognito, Dask
- **Logging**: CloudWatch Logs (7-day retention)

#### Dask Scheduler
- **CPU**: 1 vCPU (1024)
- **Memory**: 2GB (2048)
- **Ports**: 8786 (scheduler), 8787 (dashboard)
- **Image**: daskdev/dask:latest
- **Service Discovery**: AWS Cloud Map (scheduler.dask.local)

#### Dask Workers
- **CPU**: 2 vCPU (2048)
- **Memory**: 4GB (4096)
- **Image**: daskdev/dask:latest
- **Environment**: DASK_SCHEDULER_ADDRESS

### ECS Services

All services use Fargate launch type with:
- Private subnet deployment
- Security group isolation
- Rolling deployment strategy (50% minimum healthy)
- Health check grace period (60 seconds)

### Autoscaling

Target tracking autoscaling based on CPU utilization:

| Service | Min | Max | Target CPU | Scale-out | Scale-in |
|---------|-----|-----|------------|-----------|----------|
| Tiles | 2 | 10 | 70% | 60s | 300s |
| Timeseries | 2 | 20 | 70% | 60s | 300s |
| Dask Workers | 2 | 10 | 70% | 60s | 300s |

### Service Discovery

AWS Cloud Map provides DNS-based service discovery:
- **Namespace**: dask.local (private DNS)
- **Service**: scheduler.dask.local
- **TTL**: 10 seconds
- **Health Check**: Custom config with failure threshold 1

## Usage

```hcl
module "ecs" {
  source = "./modules/ecs"
  
  name                    = "raster-platform"
  vpc_id                  = module.network.vpc_id
  public_subnets          = module.network.public_subnet_ids
  private_subnets         = module.network.private_subnet_ids
  ecr_repo_name           = "raster-platform-repo"
  s3_zarr_bucket          = module.data.s3_zarr_bucket_id
  s3_cog_bucket           = module.data.s3_cog_bucket_id
  opensearch_endpoint     = module.data.opensearch_domain_endpoint
  opensearch_index        = "stac"
  redis_endpoint          = module.data.redis_primary_endpoint_address
  cognito_user_pool_id    = "ap-southeast-2_abc123"
  cognito_client_id       = "abc123xyz"
  alb_sg_id               = module.network.alb_security_group_id
  ecs_sg_id               = module.network.ecs_tasks_security_group_id
  dask_sg_id              = module.network.dask_security_group_id
  certificate_arn         = "arn:aws:acm:ap-southeast-2:123456789012:certificate/abc-123"
  task_role_arn           = module.iam.ecs_task_role_arn
  execution_role_arn      = module.iam.ecs_execution_role_arn
  image_uri               = "123456789012.dkr.ecr.ap-southeast-2.amazonaws.com/raster-platform-repo:latest"
  aws_region              = "ap-southeast-2"
  dask_scheduler_endpoint = "scheduler.dask.local"
  
  tags = {
    project_owner = "platform-team"
    project_title = "raster-platform"
    environment   = "production"
  }
}
```

## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name prefix for resources | string | - | yes |
| vpc_id | VPC ID | string | - | yes |
| public_subnets | Public subnet IDs for ALB | list(string) | - | yes |
| private_subnets | Private subnet IDs for ECS tasks | list(string) | - | yes |
| ecr_repo_name | ECR repository name | string | - | yes |
| s3_zarr_bucket | S3 bucket name for Zarr files | string | - | yes |
| s3_cog_bucket | S3 bucket name for COG files | string | - | yes |
| opensearch_endpoint | OpenSearch endpoint | string | - | yes |
| opensearch_index | OpenSearch index name | string | stac | no |
| redis_endpoint | Redis endpoint address | string | - | yes |
| cognito_user_pool_id | Cognito user pool ID | string | - | yes |
| cognito_client_id | Cognito client ID | string | - | yes |
| alb_sg_id | ALB security group ID | string | "" | no |
| ecs_sg_id | ECS tasks security group ID | string | - | yes |
| dask_sg_id | Dask cluster security group ID | string | "" | no |
| certificate_arn | ACM certificate ARN for HTTPS | string | "" | no |
| task_role_arn | ECS task role ARN | string | - | yes |
| execution_role_arn | ECS execution role ARN | string | - | yes |
| image_uri | Docker image URI | string | - | yes |
| aws_region | AWS region | string | ap-southeast-2 | no |
| dask_scheduler_endpoint | Dask scheduler endpoint | string | "" | no |
| tags | Common tags | map(string) | {} | no |

## Outputs

| Name | Description |
|------|-------------|
| alb_dns_name | DNS name of the ALB |
| cluster_name | Name of the ECS cluster |
| cluster_arn | ARN of the ECS cluster |
| tiles_service_arn | ARN of the tiles service |
| timeseries_service_arn | ARN of the timeseries service |
| tiles_service_name | Name of the tiles service |
| timeseries_service_name | Name of the timeseries service |
| alb_arn | ARN of the ALB |
| ecr_repository_url | URL of the ECR repository |
| dask_scheduler_endpoint | DNS name of Dask scheduler |
| dask_scheduler_service_arn | ARN of Dask scheduler service |
| dask_workers_service_arn | ARN of Dask workers service |
| dask_scheduler_service_name | Name of Dask scheduler service |
| dask_workers_service_name | Name of Dask workers service |
| tiles_target_group_arn_suffix | ARN suffix for CloudWatch metrics |
| timeseries_target_group_arn_suffix | ARN suffix for CloudWatch metrics |
| alb_arn_suffix | ARN suffix for CloudWatch metrics |

## Deployment Strategy

### Rolling Deployment
- Minimum healthy: 50%
- Maximum: 200%
- Ensures zero-downtime deployments

### Health Checks
- Endpoint: `/health`
- Interval: 30 seconds
- Timeout: 5 seconds
- Healthy threshold: 2
- Unhealthy threshold: 3

### Autoscaling Behavior
1. CPU exceeds 70% → Add task (60s cooldown)
2. CPU below 70% → Wait 300s, then remove task
3. Respects min/max capacity limits

## Monitoring

### CloudWatch Logs
- Log group per service
- 7-day retention
- Structured JSON logging recommended

### CloudWatch Metrics
- CPU utilization
- Memory utilization
- Request count
- Target response time
- Healthy/unhealthy host count

## Requirements

- Requirements 1.1-1.4: ECS task definitions and services
- Requirements 2.1-2.4: Autoscaling policies
- Requirements 5.1-5.3: Dask cluster infrastructure
- Requirements 7.1: CloudWatch log groups
- Requirements 9.1-9.2: Module variables and outputs
- Requirements 9.6: Resource tagging
