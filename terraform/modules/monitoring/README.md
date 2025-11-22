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
| [aws_cloudwatch_dashboard.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_dashboard) | resource |
| [aws_cloudwatch_metric_alarm.dask_scheduler_health](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.high_error_rate](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.high_latency](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.tiles_service_unavailable](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.timeseries_service_unavailable](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_sns_topic.alarms](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic) | resource |
| [aws_sns_topic_subscription.alarm_email](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription) | resource |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_alarm_email"></a> [alarm\_email](#input\_alarm\_email) | Email address for alarm notifications (optional) | `string` | `""` | no |
| <a name="input_alb_arn_suffix"></a> [alb\_arn\_suffix](#input\_alb\_arn\_suffix) | ARN suffix of the Application Load Balancer for CloudWatch metrics | `string` | n/a | yes |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the ECS cluster | `string` | n/a | yes |
| <a name="input_dask_scheduler_service_name"></a> [dask\_scheduler\_service\_name](#input\_dask\_scheduler\_service\_name) | Name of the Dask scheduler ECS service | `string` | n/a | yes |
| <a name="input_dask_workers_service_name"></a> [dask\_workers\_service\_name](#input\_dask\_workers\_service\_name) | Name of the Dask workers ECS service | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Name prefix for monitoring resources | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Common tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_tiles_service_name"></a> [tiles\_service\_name](#input\_tiles\_service\_name) | Name of the tiles ECS service | `string` | n/a | yes |
| <a name="input_tiles_target_group_arn_suffix"></a> [tiles\_target\_group\_arn\_suffix](#input\_tiles\_target\_group\_arn\_suffix) | ARN suffix of the tiles target group for CloudWatch metrics | `string` | n/a | yes |
| <a name="input_timeseries_service_name"></a> [timeseries\_service\_name](#input\_timeseries\_service\_name) | Name of the timeseries ECS service | `string` | n/a | yes |
| <a name="input_timeseries_target_group_arn_suffix"></a> [timeseries\_target\_group\_arn\_suffix](#input\_timeseries\_target\_group\_arn\_suffix) | ARN suffix of the timeseries target group for CloudWatch metrics | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_dashboard_name"></a> [dashboard\_name](#output\_dashboard\_name) | Name of the CloudWatch dashboard |
| <a name="output_dask_scheduler_health_alarm_arn"></a> [dask\_scheduler\_health\_alarm\_arn](#output\_dask\_scheduler\_health\_alarm\_arn) | ARN of the Dask scheduler health alarm |
| <a name="output_high_error_rate_alarm_arn"></a> [high\_error\_rate\_alarm\_arn](#output\_high\_error\_rate\_alarm\_arn) | ARN of the high error rate alarm |
| <a name="output_high_latency_alarm_arn"></a> [high\_latency\_alarm\_arn](#output\_high\_latency\_alarm\_arn) | ARN of the high latency alarm |
| <a name="output_sns_topic_arn"></a> [sns\_topic\_arn](#output\_sns\_topic\_arn) | ARN of the SNS topic for alarm notifications |
| <a name="output_tiles_service_unavailable_alarm_arn"></a> [tiles\_service\_unavailable\_alarm\_arn](#output\_tiles\_service\_unavailable\_alarm\_arn) | ARN of the tiles service unavailability alarm |
| <a name="output_timeseries_service_unavailable_alarm_arn"></a> [timeseries\_service\_unavailable\_alarm\_arn](#output\_timeseries\_service\_unavailable\_alarm\_arn) | ARN of the timeseries service unavailability alarm |
<!-- END_TF_DOCS -->