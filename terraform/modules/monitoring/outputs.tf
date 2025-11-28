output "sns_topic_arn" {
  description = "ARN of the SNS topic for alarm notifications"
  value       = aws_sns_topic.alarms.arn
}

output "high_error_rate_alarm_arn" {
  description = "ARN of the high error rate alarm"
  value       = aws_cloudwatch_metric_alarm.high_error_rate.arn
}

output "high_latency_alarm_arn" {
  description = "ARN of the high latency alarm"
  value       = aws_cloudwatch_metric_alarm.high_latency.arn
}

output "tiles_service_unavailable_alarm_arn" {
  description = "ARN of the tiles service unavailability alarm"
  value       = aws_cloudwatch_metric_alarm.tiles_service_unavailable.arn
}

output "timeseries_service_unavailable_alarm_arn" {
  description = "ARN of the timeseries service unavailability alarm"
  value       = aws_cloudwatch_metric_alarm.timeseries_service_unavailable.arn
}

output "dask_scheduler_health_alarm_arn" {
  description = "ARN of the Dask scheduler health alarm"
  value       = aws_cloudwatch_metric_alarm.dask_scheduler_health.arn
}

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = length(aws_cloudwatch_dashboard.main) > 0 ? aws_cloudwatch_dashboard.main[0].dashboard_name : "N/A - Dashboard disabled"
}


# Ingestion Pipeline Monitoring Outputs
output "step_functions_high_failure_rate_alarm_arn" {
  description = "ARN of the Step Functions high failure rate alarm"
  value       = length(aws_cloudwatch_metric_alarm.step_functions_high_failure_rate) > 0 ? aws_cloudwatch_metric_alarm.step_functions_high_failure_rate[0].arn : "N/A - Alarm not created"
}

output "step_functions_long_execution_alarm_arn" {
  description = "ARN of the Step Functions long execution alarm"
  value       = length(aws_cloudwatch_metric_alarm.step_functions_long_execution) > 0 ? aws_cloudwatch_metric_alarm.step_functions_long_execution[0].arn : "N/A - Alarm not created"
}

output "zarr_task_failure_alarm_arn" {
  description = "ARN of the Zarr conversion task failure alarm"
  value       = length(aws_cloudwatch_metric_alarm.zarr_task_failure) > 0 ? aws_cloudwatch_metric_alarm.zarr_task_failure[0].arn : "N/A - Alarm not created"
}

output "cog_task_failure_alarm_arn" {
  description = "ARN of the COG generation task failure alarm"
  value       = length(aws_cloudwatch_metric_alarm.cog_task_failure) > 0 ? aws_cloudwatch_metric_alarm.cog_task_failure[0].arn : "N/A - Alarm not created"
}

output "zarr_high_memory_alarm_arn" {
  description = "ARN of the Zarr conversion high memory alarm"
  value       = length(aws_cloudwatch_metric_alarm.zarr_high_memory) > 0 ? aws_cloudwatch_metric_alarm.zarr_high_memory[0].arn : "N/A - Alarm not created"
}

output "cog_high_memory_alarm_arn" {
  description = "ARN of the COG generation high memory alarm"
  value       = length(aws_cloudwatch_metric_alarm.cog_high_memory) > 0 ? aws_cloudwatch_metric_alarm.cog_high_memory[0].arn : "N/A - Alarm not created"
}

output "ingestion_pipeline_dashboard_name" {
  description = "Name of the ingestion pipeline CloudWatch dashboard"
  value       = length(aws_cloudwatch_dashboard.ingestion_pipeline) > 0 ? aws_cloudwatch_dashboard.ingestion_pipeline[0].dashboard_name : "N/A - Dashboard not created"
}
