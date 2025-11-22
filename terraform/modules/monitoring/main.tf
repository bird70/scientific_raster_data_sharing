# SNS Topic for alarm notifications
resource "aws_sns_topic" "alarms" {
  name = "${var.name}-alarms"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "alarm_email" {
  count     = var.alarm_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# CloudWatch Alarms

# High error rate alarm (5xx > 5% for 5 minutes)
resource "aws_cloudwatch_metric_alarm" "high_error_rate" {
  alarm_name          = "${var.name}-high-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 5
  alarm_description   = "Alert when 5xx error rate exceeds 5% for 5 minutes"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"
  tags                = var.tags

  metric_query {
    id          = "error_rate"
    expression  = "(m2/m1)*100"
    label       = "Error Rate"
    return_data = true
  }

  metric_query {
    id = "m1"
    metric {
      metric_name = "RequestCount"
      namespace   = "AWS/ApplicationELB"
      period      = 300
      stat        = "Sum"
      dimensions = {
        LoadBalancer = var.alb_arn_suffix
      }
    }
  }

  metric_query {
    id = "m2"
    metric {
      metric_name = "HTTPCode_Target_5XX_Count"
      namespace   = "AWS/ApplicationELB"
      period      = 300
      stat        = "Sum"
      dimensions = {
        LoadBalancer = var.alb_arn_suffix
      }
    }
  }
}

# High latency alarm (p95 > 2s for 5 minutes)
resource "aws_cloudwatch_metric_alarm" "high_latency" {
  alarm_name          = "${var.name}-high-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Average"
  threshold           = 2
  alarm_description   = "Alert when p95 latency exceeds 2 seconds for 5 minutes"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"
  tags                = var.tags

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }
}

# Service unavailability alarm for tiles service (HealthyHostCount < 1 for 2 minutes)
resource "aws_cloudwatch_metric_alarm" "tiles_service_unavailable" {
  alarm_name          = "${var.name}-tiles-service-unavailable"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 120
  statistic           = "Average"
  threshold           = 1
  alarm_description   = "Alert when tiles service has less than 1 healthy host for 2 minutes"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "breaching"
  tags                = var.tags

  dimensions = {
    TargetGroup  = var.tiles_target_group_arn_suffix
    LoadBalancer = var.alb_arn_suffix
  }
}

# Service unavailability alarm for timeseries service (HealthyHostCount < 1 for 2 minutes)
resource "aws_cloudwatch_metric_alarm" "timeseries_service_unavailable" {
  alarm_name          = "${var.name}-timeseries-service-unavailable"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 120
  statistic           = "Average"
  threshold           = 1
  alarm_description   = "Alert when timeseries service has less than 1 healthy host for 2 minutes"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "breaching"
  tags                = var.tags

  dimensions = {
    TargetGroup  = var.timeseries_target_group_arn_suffix
    LoadBalancer = var.alb_arn_suffix
  }
}

# Dask scheduler health alarm
resource "aws_cloudwatch_metric_alarm" "dask_scheduler_health" {
  alarm_name          = "${var.name}-dask-scheduler-health"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "RunningTaskCount"
  namespace           = "ECS/ContainerInsights"
  period              = 120
  statistic           = "Average"
  threshold           = 1
  alarm_description   = "Alert when Dask scheduler has no running tasks for 2 minutes"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "breaching"
  tags                = var.tags

  dimensions = {
    ServiceName = var.dask_scheduler_service_name
    ClusterName = var.cluster_name
  }
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "main" {
  count          = 0  # Temporarily disabled due to JSON format issues
  dashboard_name = "${var.name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      # Request rate widget
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", { stat = "Sum", label = "Total Requests" }]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Request Rate"
          yAxis = {
            left = {
              label = "Count"
            }
          }
        }
        x      = 0
        y      = 0
        width  = 12
        height = 6
      },
      # Latency widget
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", { stat = "Average", label = "Average Latency" }],
            ["...", { stat = "p95", label = "P95 Latency" }],
            ["...", { stat = "p99", label = "P99 Latency" }]
          ]
          period = 300
          region = data.aws_region.current.name
          title  = "Response Time"
          yAxis = {
            left = {
              label = "Seconds"
            }
          }
        }
        x      = 12
        y      = 0
        width  = 12
        height = 6
      },
      # Error rate widget
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count", { stat = "Sum", label = "4xx Errors" }],
            [".", "HTTPCode_Target_5XX_Count", { stat = "Sum", label = "5xx Errors" }]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Error Rate"
          yAxis = {
            left = {
              label = "Count"
            }
          }
        }
        x      = 0
        y      = 6
        width  = 12
        height = 6
      },
      # Tiles service health widget
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ECS", "CPUUtilization", { stat = "Average", label = "CPU Utilization" }, { ServiceName = var.tiles_service_name, ClusterName = var.cluster_name }],
            [".", "MemoryUtilization", { stat = "Average", label = "Memory Utilization" }, { ServiceName = var.tiles_service_name, ClusterName = var.cluster_name }]
          ]
          period = 300
          region = data.aws_region.current.name
          title  = "Tiles Service - Resource Utilization"
          yAxis = {
            left = {
              label = "Percent"
            }
          }
        }
        x      = 12
        y      = 6
        width  = 12
        height = 6
      },
      # Tiles service task count widget
      {
        type = "metric"
        properties = {
          metrics = [
            ["ECS/ContainerInsights", "RunningTaskCount", { ServiceName = var.tiles_service_name, ClusterName = var.cluster_name, stat = "Average", label = "Running Tasks" }],
            [".", "DesiredTaskCount", { ServiceName = var.tiles_service_name, ClusterName = var.cluster_name, stat = "Average", label = "Desired Tasks" }]
          ]
          period = 300
          region = data.aws_region.current.name
          title  = "Tiles Service - Task Count"
          yAxis = {
            left = {
              label = "Count"
            }
          }
        }
        x      = 0
        y      = 12
        width  = 12
        height = 6
      },
      # Timeseries service health widget
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ECS", "CPUUtilization", { stat = "Average", label = "CPU Utilization" }, { ServiceName = var.timeseries_service_name, ClusterName = var.cluster_name }],
            [".", "MemoryUtilization", { stat = "Average", label = "Memory Utilization" }, { ServiceName = var.timeseries_service_name, ClusterName = var.cluster_name }]
          ]
          period = 300
          region = data.aws_region.current.name
          title  = "Timeseries Service - Resource Utilization"
          yAxis = {
            left = {
              label = "Percent"
            }
          }
        }
        x      = 12
        y      = 12
        width  = 12
        height = 6
      },
      # Timeseries service task count widget
      {
        type = "metric"
        properties = {
          metrics = [
            ["ECS/ContainerInsights", "RunningTaskCount", { ServiceName = var.timeseries_service_name, ClusterName = var.cluster_name, stat = "Average", label = "Running Tasks" }],
            [".", "DesiredTaskCount", { ServiceName = var.timeseries_service_name, ClusterName = var.cluster_name, stat = "Average", label = "Desired Tasks" }]
          ]
          period = 300
          region = data.aws_region.current.name
          title  = "Timeseries Service - Task Count"
          yAxis = {
            left = {
              label = "Count"
            }
          }
        }
        x      = 0
        y      = 18
        width  = 12
        height = 6
      },
      # Dask scheduler health widget
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ECS", "CPUUtilization", { stat = "Average", label = "CPU Utilization" }, { ServiceName = var.dask_scheduler_service_name, ClusterName = var.cluster_name }],
            [".", "MemoryUtilization", { stat = "Average", label = "Memory Utilization" }, { ServiceName = var.dask_scheduler_service_name, ClusterName = var.cluster_name }]
          ]
          period = 300
          region = data.aws_region.current.name
          title  = "Dask Scheduler - Resource Utilization"
          yAxis = {
            left = {
              label = "Percent"
            }
          }
        }
        x      = 12
        y      = 18
        width  = 12
        height = 6
      },
      # Dask workers health widget
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ECS", "CPUUtilization", { stat = "Average", label = "CPU Utilization" }, { ServiceName = var.dask_workers_service_name, ClusterName = var.cluster_name }],
            [".", "MemoryUtilization", { stat = "Average", label = "Memory Utilization" }, { ServiceName = var.dask_workers_service_name, ClusterName = var.cluster_name }]
          ]
          period = 300
          region = data.aws_region.current.name
          title  = "Dask Workers - Resource Utilization"
          yAxis = {
            left = {
              label = "Percent"
            }
          }
        }
        x      = 0
        y      = 24
        width  = 12
        height = 6
      },
      # Dask workers task count widget
      {
        type = "metric"
        properties = {
          metrics = [
            ["ECS/ContainerInsights", "RunningTaskCount", { ServiceName = var.dask_workers_service_name, ClusterName = var.cluster_name, stat = "Average", label = "Running Workers" }],
            [".", "DesiredTaskCount", { ServiceName = var.dask_workers_service_name, ClusterName = var.cluster_name, stat = "Average", label = "Desired Workers" }]
          ]
          period = 300
          region = data.aws_region.current.name
          title  = "Dask Workers - Task Count"
          yAxis = {
            left = {
              label = "Count"
            }
          }
        }
        x      = 12
        y      = 24
        width  = 12
        height = 6
      }
    ]
  })
}

# Data source for current region
data "aws_region" "current" {}
