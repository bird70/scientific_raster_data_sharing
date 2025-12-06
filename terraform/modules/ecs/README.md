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

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.22.1 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_appautoscaling_policy.dask_workers_cpu](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/appautoscaling_policy) | resource |
| [aws_appautoscaling_policy.tiles_cpu](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/appautoscaling_policy) | resource |
| [aws_appautoscaling_policy.timeseries_cpu](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/appautoscaling_policy) | resource |
| [aws_appautoscaling_target.dask_workers](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/appautoscaling_target) | resource |
| [aws_appautoscaling_target.tiles](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/appautoscaling_target) | resource |
| [aws_appautoscaling_target.timeseries](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/appautoscaling_target) | resource |
| [aws_cloudwatch_log_group.cog_generation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_group.dask_scheduler](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_group.dask_workers](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_group.tiles](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_group.timeseries](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_group.zarr_conversion](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_ecr_repository.repo](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository) | resource |
| [aws_ecs_cluster.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster) | resource |
| [aws_ecs_service.dask_scheduler](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service) | resource |
| [aws_ecs_service.dask_workers](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service) | resource |
| [aws_ecs_service.tiles](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service) | resource |
| [aws_ecs_service.timeseries](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service) | resource |
| [aws_ecs_task_definition.cog_generation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
| [aws_ecs_task_definition.dask_scheduler](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
| [aws_ecs_task_definition.dask_workers](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
| [aws_ecs_task_definition.tiles](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
| [aws_ecs_task_definition.timeseries](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
| [aws_ecs_task_definition.zarr_conversion](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
| [aws_lb.alb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb_listener.http](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener.https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener_rule.api_rule_http](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_rule) | resource |
| [aws_lb_listener_rule.docs_rule_http](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_rule) | resource |
| [aws_lb_listener_rule.health_rule_http](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_rule) | resource |
| [aws_lb_listener_rule.health_rule_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_rule) | resource |
| [aws_lb_listener_rule.metrics_rule_http](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_rule) | resource |
| [aws_lb_listener_rule.openapi_rule_http](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_rule) | resource |
| [aws_lb_listener_rule.root_rule_http](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_rule) | resource |
| [aws_lb_listener_rule.tiles_rule_http](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_rule) | resource |
| [aws_lb_listener_rule.tiles_rule_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_rule) | resource |
| [aws_lb_listener_rule.timeseries_rule_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_rule) | resource |
| [aws_lb_target_group.tiles_tg](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_lb_target_group.timeseries_tg](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_service_discovery_private_dns_namespace.dask](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/service_discovery_private_dns_namespace) | resource |
| [aws_service_discovery_service.dask_scheduler](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/service_discovery_service) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_alb_sg_id"></a> [alb\_sg\_id](#input\_alb\_sg\_id) | n/a | `string` | `""` | no |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region | `string` | `"ap-southeast-2"` | no |
| <a name="input_certificate_arn"></a> [certificate\_arn](#input\_certificate\_arn) | n/a | `string` | `""` | no |
| <a name="input_cognito_client_id"></a> [cognito\_client\_id](#input\_cognito\_client\_id) | Cognito user pool client ID | `string` | n/a | yes |
| <a name="input_cognito_user_pool_id"></a> [cognito\_user\_pool\_id](#input\_cognito\_user\_pool\_id) | n/a | `string` | n/a | yes |
| <a name="input_dask_scheduler_endpoint"></a> [dask\_scheduler\_endpoint](#input\_dask\_scheduler\_endpoint) | Dask scheduler endpoint | `string` | `""` | no |
| <a name="input_dask_sg_id"></a> [dask\_sg\_id](#input\_dask\_sg\_id) | Security group ID for Dask cluster | `string` | `""` | no |
| <a name="input_dask_workers_desired_count"></a> [dask\_workers\_desired\_count](#input\_dask\_workers\_desired\_count) | Desired number of Dask worker tasks | `number` | `2` | no |
| <a name="input_dynamodb_stac_table_name"></a> [dynamodb\_stac\_table\_name](#input\_dynamodb\_stac\_table\_name) | DynamoDB table name for STAC items | `string` | `""` | no |
| <a name="input_ecr_repo_name"></a> [ecr\_repo\_name](#input\_ecr\_repo\_name) | n/a | `string` | n/a | yes |
| <a name="input_ecs_sg_id"></a> [ecs\_sg\_id](#input\_ecs\_sg\_id) | Security group ID for ECS tasks | `string` | n/a | yes |
| <a name="input_execution_role_arn"></a> [execution\_role\_arn](#input\_execution\_role\_arn) | ARN of the IAM role for ECS task execution | `string` | n/a | yes |
| <a name="input_frontend_website_endpoint"></a> [frontend\_website\_endpoint](#input\_frontend\_website\_endpoint) | S3 website endpoint for frontend | `string` | n/a | yes |
| <a name="input_image_uri"></a> [image\_uri](#input\_image\_uri) | URI of the Docker image in ECR | `string` | n/a | yes |
| <a name="input_private_subnets"></a> [private\_subnets](#input\_private\_subnets) | n/a | `list(string)` | n/a | yes |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | n/a | `string` | n/a | yes |
| <a name="input_public_subnets"></a> [public\_subnets](#input\_public\_subnets) | n/a | `list(string)` | n/a | yes |
| <a name="input_redis_endpoint"></a> [redis\_endpoint](#input\_redis\_endpoint) | n/a | `string` | n/a | yes |
| <a name="input_s3_cog_bucket"></a> [s3\_cog\_bucket](#input\_s3\_cog\_bucket) | S3 bucket name for COG files | `string` | n/a | yes |
| <a name="input_s3_zarr_bucket"></a> [s3\_zarr\_bucket](#input\_s3\_zarr\_bucket) | n/a | `string` | n/a | yes |
| <a name="input_short_name"></a> [short\_name](#input\_short\_name) | Short name for AWS resources with length limits | `string` | `"dp-sci-raster"` | no |
| <a name="input_stac_backend"></a> [stac\_backend](#input\_stac\_backend) | STAC backend mode: dynamodb, opensearch, or dual | `string` | `"opensearch"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Common tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_task_role_arn"></a> [task\_role\_arn](#input\_task\_role\_arn) | ARN of the IAM role for ECS tasks | `string` | n/a | yes |
| <a name="input_tiles_desired_count"></a> [tiles\_desired\_count](#input\_tiles\_desired\_count) | Desired number of tiles service tasks | `number` | `2` | no |
| <a name="input_timeseries_desired_count"></a> [timeseries\_desired\_count](#input\_timeseries\_desired\_count) | Desired number of timeseries service tasks | `number` | `2` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | n/a | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_alb_arn"></a> [alb\_arn](#output\_alb\_arn) | ARN of the Application Load Balancer |
| <a name="output_alb_arn_suffix"></a> [alb\_arn\_suffix](#output\_alb\_arn\_suffix) | ARN suffix of the Application Load Balancer for CloudWatch metrics |
| <a name="output_alb_dns_name"></a> [alb\_dns\_name](#output\_alb\_dns\_name) | DNS name of the Application Load Balancer |
| <a name="output_cluster_arn"></a> [cluster\_arn](#output\_cluster\_arn) | ARN of the ECS cluster |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | Name of the ECS cluster |
| <a name="output_cog_generation_task_definition_arn"></a> [cog\_generation\_task\_definition\_arn](#output\_cog\_generation\_task\_definition\_arn) | ARN of the COG generation task definition |
| <a name="output_dask_scheduler_endpoint"></a> [dask\_scheduler\_endpoint](#output\_dask\_scheduler\_endpoint) | DNS name of the Dask scheduler for service discovery |
| <a name="output_dask_scheduler_service_arn"></a> [dask\_scheduler\_service\_arn](#output\_dask\_scheduler\_service\_arn) | ARN of the Dask scheduler ECS service |
| <a name="output_dask_scheduler_service_name"></a> [dask\_scheduler\_service\_name](#output\_dask\_scheduler\_service\_name) | Name of the Dask scheduler ECS service |
| <a name="output_dask_workers_service_arn"></a> [dask\_workers\_service\_arn](#output\_dask\_workers\_service\_arn) | ARN of the Dask workers ECS service |
| <a name="output_dask_workers_service_name"></a> [dask\_workers\_service\_name](#output\_dask\_workers\_service\_name) | Name of the Dask workers ECS service |
| <a name="output_ecr_repository_url"></a> [ecr\_repository\_url](#output\_ecr\_repository\_url) | URL of the ECR repository |
| <a name="output_tiles_service_arn"></a> [tiles\_service\_arn](#output\_tiles\_service\_arn) | ARN of the tiles ECS service |
| <a name="output_tiles_service_name"></a> [tiles\_service\_name](#output\_tiles\_service\_name) | Name of the tiles ECS service |
| <a name="output_tiles_target_group_arn_suffix"></a> [tiles\_target\_group\_arn\_suffix](#output\_tiles\_target\_group\_arn\_suffix) | ARN suffix of the tiles target group for CloudWatch metrics |
| <a name="output_timeseries_service_arn"></a> [timeseries\_service\_arn](#output\_timeseries\_service\_arn) | ARN of the timeseries ECS service |
| <a name="output_timeseries_service_name"></a> [timeseries\_service\_name](#output\_timeseries\_service\_name) | Name of the timeseries ECS service |
| <a name="output_timeseries_target_group_arn_suffix"></a> [timeseries\_target\_group\_arn\_suffix](#output\_timeseries\_target\_group\_arn\_suffix) | ARN suffix of the timeseries target group for CloudWatch metrics |
| <a name="output_zarr_conversion_task_definition_arn"></a> [zarr\_conversion\_task\_definition\_arn](#output\_zarr\_conversion\_task\_definition\_arn) | ARN of the Zarr conversion task definition |
<!-- END_TF_DOCS -->