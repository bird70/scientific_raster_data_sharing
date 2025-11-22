# Monitoring Module

This module creates CloudWatch alarms and dashboards for monitoring the Raster Time-series Access Web Service infrastructure.

## Features

- CloudWatch alarms for critical metrics
- SNS topic for alarm notifications
- Comprehensive CloudWatch dashboard

## Alarms

The module creates the following alarms:

1. **High Error Rate**: Triggers when 5xx error rate exceeds 5% for 5 minutes
2. **High Latency**: Triggers when p95 latency exceeds 2 seconds for 5 minutes
3. **Tiles Service Unavailable**: Triggers when tiles service has less than 1 healthy host for 2 minutes
4. **Timeseries Service Unavailable**: Triggers when timeseries service has less than 1 healthy host for 2 minutes
5. **Dask Scheduler Health**: Triggers when Dask scheduler has no running tasks for 2 minutes

All alarms send notifications to the SNS topic created by this module.

## Dashboard

The CloudWatch dashboard includes widgets for:

- Request rate and latency metrics
- Error rates (4xx and 5xx)
- ECS service health (CPU and memory utilization)
- ECS task counts (running vs desired)
- Dask cluster utilization

## Usage

```hcl
module "monitoring" {
  source = "./modules/monitoring"

  name                                = "raster-service"
  alb_arn_suffix                      = module.ecs.alb_arn_suffix
  tiles_target_group_arn_suffix       = module.ecs.tiles_target_group_arn_suffix
  timeseries_target_group_arn_suffix  = module.ecs.timeseries_target_group_arn_suffix
  cluster_name                        = module.ecs.cluster_name
  tiles_service_name                  = module.ecs.tiles_service_name
  timeseries_service_name             = module.ecs.timeseries_service_name
  dask_scheduler_service_name         = module.ecs.dask_scheduler_service_name
  dask_workers_service_name           = module.ecs.dask_workers_service_name
  alarm_email                         = "ops@example.com"

  tags = {
    project_owner = "platform-team"
    project_title = "raster-timeseries-service"
    environment   = "production"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name prefix for monitoring resources | string | - | yes |
| alb_arn_suffix | ARN suffix of the Application Load Balancer | string | - | yes |
| tiles_target_group_arn_suffix | ARN suffix of the tiles target group | string | - | yes |
| timeseries_target_group_arn_suffix | ARN suffix of the timeseries target group | string | - | yes |
| cluster_name | Name of the ECS cluster | string | - | yes |
| tiles_service_name | Name of the tiles ECS service | string | - | yes |
| timeseries_service_name | Name of the timeseries ECS service | string | - | yes |
| dask_scheduler_service_name | Name of the Dask scheduler ECS service | string | - | yes |
| dask_workers_service_name | Name of the Dask workers ECS service | string | - | yes |
| alarm_email | Email address for alarm notifications (optional) | string | "" | no |
| tags | Common tags to apply to all resources | map(string) | {} | no |

## Outputs

| Name | Description |
|------|-------------|
| sns_topic_arn | ARN of the SNS topic for alarm notifications |
| high_error_rate_alarm_arn | ARN of the high error rate alarm |
| high_latency_alarm_arn | ARN of the high latency alarm |
| tiles_service_unavailable_alarm_arn | ARN of the tiles service unavailability alarm |
| timeseries_service_unavailable_alarm_arn | ARN of the timeseries service unavailability alarm |
| dask_scheduler_health_alarm_arn | ARN of the Dask scheduler health alarm |
| dashboard_name | Name of the CloudWatch dashboard |

## Requirements

- Terraform >= 1.0
- AWS Provider >= 4.0

## Notes

- The alarm email subscription requires manual confirmation via email
- CloudWatch Container Insights must be enabled on the ECS cluster for task count metrics
- The dashboard uses the current AWS region automatically
