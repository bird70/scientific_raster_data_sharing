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
  value       = aws_cloudwatch_dashboard.main.dashboard_name
}
