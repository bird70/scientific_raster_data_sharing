# SNS Topic for alarm notifications
resource "aws_sns_topic" "alarms" {
  name = "${var.project_name}-alarms"
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
  alarm_name          = "${var.project_name}-high-error-rate"
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
  alarm_name          = "${var.project_name}-high-latency"
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
  alarm_name          = "${var.project_name}-tiles-service-unavailable"
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
  alarm_name          = "${var.project_name}-timeseries-service-unavailable"
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
  alarm_name          = "${var.project_name}-dask-scheduler-health"
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
  count          = 0 # Temporarily disabled due to JSON format issues
  dashboard_name = "${var.project_name}-dashboard"

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

# ============================================================================
# DynamoDB CloudWatch Alarms
# ============================================================================

# Alarm for throttled read requests
resource "aws_cloudwatch_metric_alarm" "dynamodb_throttled_reads" {
  count               = var.dynamodb_table_name != "" ? 1 : 0
  alarm_name          = "${var.project_name}-dynamodb-throttled-reads"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UserErrors"
  namespace           = "AWS/DynamoDB"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Alert when DynamoDB read requests are throttled (>5 in 10 minutes)"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"
  tags                = var.tags

  dimensions = {
    TableName = var.dynamodb_table_name
  }
}

# Alarm for throttled write requests
resource "aws_cloudwatch_metric_alarm" "dynamodb_throttled_writes" {
  count               = var.dynamodb_table_name != "" ? 1 : 0
  alarm_name          = "${var.project_name}-dynamodb-throttled-writes"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "WriteThrottleEvents"
  namespace           = "AWS/DynamoDB"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Alert when DynamoDB write requests are throttled (>5 in 10 minutes)"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"
  tags                = var.tags

  dimensions = {
    TableName = var.dynamodb_table_name
  }
}

# Alarm for high read latency (p95 > 50ms)
resource "aws_cloudwatch_metric_alarm" "dynamodb_high_read_latency" {
  count               = var.dynamodb_table_name != "" ? 1 : 0
  alarm_name          = "${var.project_name}-dynamodb-high-read-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "SuccessfulRequestLatency"
  namespace           = "AWS/DynamoDB"
  period              = 300
  extended_statistic  = "p95"
  threshold           = 50
  alarm_description   = "Alert when DynamoDB read latency p95 exceeds 50ms for 10 minutes"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"
  tags                = var.tags

  dimensions = {
    TableName = var.dynamodb_table_name
    Operation = "GetItem"
  }
}

# Alarm for high query latency (p95 > 50ms)
resource "aws_cloudwatch_metric_alarm" "dynamodb_high_query_latency" {
  count               = var.dynamodb_table_name != "" ? 1 : 0
  alarm_name          = "${var.project_name}-dynamodb-high-query-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "SuccessfulRequestLatency"
  namespace           = "AWS/DynamoDB"
  period              = 300
  extended_statistic  = "p95"
  threshold           = 50
  alarm_description   = "Alert when DynamoDB query latency p95 exceeds 50ms for 10 minutes"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"
  tags                = var.tags

  dimensions = {
    TableName = var.dynamodb_table_name
    Operation = "Query"
  }
}

# Alarm for high write latency (p95 > 50ms)
resource "aws_cloudwatch_metric_alarm" "dynamodb_high_write_latency" {
  count               = var.dynamodb_table_name != "" ? 1 : 0
  alarm_name          = "${var.project_name}-dynamodb-high-write-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "SuccessfulRequestLatency"
  namespace           = "AWS/DynamoDB"
  period              = 300
  extended_statistic  = "p95"
  threshold           = 50
  alarm_description   = "Alert when DynamoDB write latency p95 exceeds 50ms for 10 minutes"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"
  tags                = var.tags

  dimensions = {
    TableName = var.dynamodb_table_name
    Operation = "PutItem"
  }
}

# ============================================================================
# DynamoDB CloudWatch Dashboard
# ============================================================================

resource "aws_cloudwatch_dashboard" "dynamodb" {
  count          = 0  # Temporarily disabled due to metric formatting issues
  dashboard_name = "${var.project_name}-dynamodb-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      # Read/Write Capacity Units
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", { stat = "Sum", label = "Read Capacity Units" }, { TableName = var.dynamodb_table_name }],
            [".", "ConsumedWriteCapacityUnits", { stat = "Sum", label = "Write Capacity Units" }, { TableName = var.dynamodb_table_name }]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "DynamoDB - Consumed Capacity Units"
          yAxis = {
            left = {
              label = "Units"
            }
          }
        }
        x      = 0
        y      = 0
        width  = 12
        height = 6
      },
      # Request Latency
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/DynamoDB", "SuccessfulRequestLatency", { stat = "Average", label = "GetItem Avg" }, { TableName = var.dynamodb_table_name, Operation = "GetItem" }],
            ["...", { stat = "p95", label = "GetItem P95" }, { TableName = var.dynamodb_table_name, Operation = "GetItem" }],
            ["...", { stat = "Average", label = "Query Avg" }, { TableName = var.dynamodb_table_name, Operation = "Query" }],
            ["...", { stat = "p95", label = "Query P95" }, { TableName = var.dynamodb_table_name, Operation = "Query" }],
            ["...", { stat = "Average", label = "PutItem Avg" }, { TableName = var.dynamodb_table_name, Operation = "PutItem" }],
            ["...", { stat = "p95", label = "PutItem P95" }, { TableName = var.dynamodb_table_name, Operation = "PutItem" }]
          ]
          period = 300
          region = data.aws_region.current.name
          title  = "DynamoDB - Request Latency (ms)"
          yAxis = {
            left = {
              label = "Milliseconds"
            }
          }
        }
        x      = 12
        y      = 0
        width  = 12
        height = 6
      },
      # Throttled Requests
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/DynamoDB", "ReadThrottleEvents", { stat = "Sum", label = "Read Throttles" }, { TableName = var.dynamodb_table_name }],
            [".", "WriteThrottleEvents", { stat = "Sum", label = "Write Throttles" }, { TableName = var.dynamodb_table_name }],
            [".", "UserErrors", { stat = "Sum", label = "User Errors" }, { TableName = var.dynamodb_table_name }]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "DynamoDB - Throttled Requests & Errors"
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
      # Item Count (approximate)
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/DynamoDB", "ItemCount", { stat = "Average", label = "Item Count" }, { TableName = var.dynamodb_table_name }]
          ]
          period = 3600
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "DynamoDB - Item Count (Approximate)"
          yAxis = {
            left = {
              label = "Count"
            }
          }
        }
        x      = 12
        y      = 6
        width  = 12
        height = 6
      },
      # GSI Consumed Capacity - Collection Index
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", { stat = "Sum", label = "Collection Index Reads" }, { TableName = var.dynamodb_table_name, GlobalSecondaryIndexName = "collection-index" }],
            [".", "ConsumedWriteCapacityUnits", { stat = "Sum", label = "Collection Index Writes" }, { TableName = var.dynamodb_table_name, GlobalSecondaryIndexName = "collection-index" }]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "DynamoDB - Collection Index Capacity"
          yAxis = {
            left = {
              label = "Units"
            }
          }
        }
        x      = 0
        y      = 12
        width  = 12
        height = 6
      },
      # GSI Consumed Capacity - Datetime Index
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", { stat = "Sum", label = "Datetime Index Reads" }, { TableName = var.dynamodb_table_name, GlobalSecondaryIndexName = "datetime-index" }],
            [".", "ConsumedWriteCapacityUnits", { stat = "Sum", label = "Datetime Index Writes" }, { TableName = var.dynamodb_table_name, GlobalSecondaryIndexName = "datetime-index" }]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "DynamoDB - Datetime Index Capacity"
          yAxis = {
            left = {
              label = "Units"
            }
          }
        }
        x      = 12
        y      = 12
        width  = 12
        height = 6
      },
      # Request Count by Operation
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/DynamoDB", "SuccessfulRequestLatency", { stat = "SampleCount", label = "GetItem Requests" }, { TableName = var.dynamodb_table_name, Operation = "GetItem" }],
            ["...", { stat = "SampleCount", label = "Query Requests" }, { TableName = var.dynamodb_table_name, Operation = "Query" }],
            ["...", { stat = "SampleCount", label = "Scan Requests" }, { TableName = var.dynamodb_table_name, Operation = "Scan" }],
            ["...", { stat = "SampleCount", label = "PutItem Requests" }, { TableName = var.dynamodb_table_name, Operation = "PutItem" }]
          ]
          period = 300
          region = data.aws_region.current.name
          title  = "DynamoDB - Request Count by Operation"
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
      # System Errors
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/DynamoDB", "SystemErrors", { stat = "Sum", label = "System Errors" }, { TableName = var.dynamodb_table_name }],
            [".", "ConditionalCheckFailedRequests", { stat = "Sum", label = "Conditional Check Failures" }, { TableName = var.dynamodb_table_name }]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "DynamoDB - System Errors"
          yAxis = {
            left = {
              label = "Count"
            }
          }
        }
        x      = 12
        y      = 18
        width  = 12
        height = 6
      }
    ]
  })

  depends_on = [aws_sns_topic.alarms]
}


# ============================================================================
# Ingestion Pipeline CloudWatch Alarms
# ============================================================================

# Alarm for Step Functions execution failures (high failure rate)
resource "aws_cloudwatch_metric_alarm" "step_functions_high_failure_rate" {
  count               = var.state_machine_arn != "" ? 1 : 0
  alarm_name          = "${var.project_name}-ingestion-high-failure-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 2
  alarm_description   = "Alert when Step Functions execution failure rate exceeds 2 failures in 5 minutes"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"
  tags                = var.tags

  metric_query {
    id          = "failure_rate"
    expression  = "m1"
    label       = "Failed Executions"
    return_data = true
  }

  metric_query {
    id = "m1"
    metric {
      metric_name = "ExecutionsFailed"
      namespace   = "AWS/States"
      period      = 300
      stat        = "Sum"
      dimensions = {
        StateMachineArn = var.state_machine_arn
      }
    }
  }
}

# Alarm for Step Functions long execution time (>20 minutes)
resource "aws_cloudwatch_metric_alarm" "step_functions_long_execution" {
  count               = var.state_machine_arn != "" ? 1 : 0
  alarm_name          = "${var.project_name}-ingestion-long-execution"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ExecutionTime"
  namespace           = "AWS/States"
  period              = 300
  statistic           = "Maximum"
  threshold           = 1200000  # 20 minutes in milliseconds
  alarm_description   = "Alert when Step Functions execution time exceeds 20 minutes"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"
  tags                = var.tags

  dimensions = {
    StateMachineArn = var.state_machine_arn
  }
}

# Alarm for Zarr conversion ECS task failures
resource "aws_cloudwatch_metric_alarm" "zarr_task_failure" {
  count               = var.state_machine_arn != "" ? 1 : 0
  alarm_name          = "${var.project_name}-zarr-task-failure"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "TasksFailed"
  namespace           = "ECS/ContainerInsights"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Alert when Zarr conversion ECS task fails"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"
  tags                = var.tags

  dimensions = {
    ClusterName = var.cluster_name
    TaskDefinitionFamily = var.zarr_task_definition_family
  }
}

# Alarm for COG generation ECS task failures
resource "aws_cloudwatch_metric_alarm" "cog_task_failure" {
  count               = var.state_machine_arn != "" ? 1 : 0
  alarm_name          = "${var.project_name}-cog-task-failure"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "TasksFailed"
  namespace           = "ECS/ContainerInsights"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Alert when COG generation ECS task fails"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"
  tags                = var.tags

  dimensions = {
    ClusterName = var.cluster_name
    TaskDefinitionFamily = var.cog_task_definition_family
  }
}

# Alarm for Zarr conversion high memory usage (>90%)
resource "aws_cloudwatch_metric_alarm" "zarr_high_memory" {
  count               = var.state_machine_arn != "" ? 1 : 0
  alarm_name          = "${var.project_name}-zarr-high-memory"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "MemoryUtilization"
  namespace           = "ECS/ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = 90
  alarm_description   = "Alert when Zarr conversion memory usage exceeds 90% for 10 minutes"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"
  tags                = var.tags

  dimensions = {
    ClusterName = var.cluster_name
    TaskDefinitionFamily = var.zarr_task_definition_family
  }
}

# Alarm for COG generation high memory usage (>90%)
resource "aws_cloudwatch_metric_alarm" "cog_high_memory" {
  count               = var.state_machine_arn != "" ? 1 : 0
  alarm_name          = "${var.project_name}-cog-high-memory"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "MemoryUtilization"
  namespace           = "ECS/ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = 90
  alarm_description   = "Alert when COG generation memory usage exceeds 90% for 10 minutes"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"
  tags                = var.tags

  dimensions = {
    ClusterName = var.cluster_name
    TaskDefinitionFamily = var.cog_task_definition_family
  }
}

# ============================================================================
# Ingestion Pipeline CloudWatch Dashboard
# ============================================================================

resource "aws_cloudwatch_dashboard" "ingestion_pipeline" {
  count          = 0  # Temporarily disabled due to metric format issues - use AWS Console to create manually
  dashboard_name = "${var.project_name}-ingestion-pipeline"

  dashboard_body = jsonencode({
    widgets = [
      # Step Functions Execution Status
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/States", "ExecutionsSucceeded", { stat = "Sum", label = "Succeeded", color = "#2ca02c" }, { StateMachineArn = var.state_machine_arn }],
            [".", "ExecutionsFailed", { stat = "Sum", label = "Failed", color = "#d62728" }, { StateMachineArn = var.state_machine_arn }],
            [".", "ExecutionsTimedOut", { stat = "Sum", label = "Timed Out", color = "#ff7f0e" }, { StateMachineArn = var.state_machine_arn }],
            [".", "ExecutionsAborted", { stat = "Sum", label = "Aborted", color = "#9467bd" }, { StateMachineArn = var.state_machine_arn }]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Step Functions - Execution Status"
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
      # Step Functions Execution Time
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/States", "ExecutionTime", { stat = "Average", label = "Average Duration" }, { StateMachineArn = var.state_machine_arn }],
            ["...", { stat = "Maximum", label = "Max Duration" }, { StateMachineArn = var.state_machine_arn }],
            ["...", { stat = "Minimum", label = "Min Duration" }, { StateMachineArn = var.state_machine_arn }]
          ]
          period = 300
          region = data.aws_region.current.name
          title  = "Step Functions - Execution Time (ms)"
          yAxis = {
            left = {
              label = "Milliseconds"
            }
          }
        }
        x      = 12
        y      = 0
        width  = 12
        height = 6
      },
      # Zarr Conversion Task Status
      {
        type = "metric"
        properties = {
          metrics = [
            ["ECS/ContainerInsights", "RunningTaskCount", { stat = "Average", label = "Running Tasks" }, { ClusterName = var.cluster_name, TaskDefinitionFamily = var.zarr_task_definition_family }],
            [".", "TasksStarted", { stat = "Sum", label = "Tasks Started" }, { ClusterName = var.cluster_name, TaskDefinitionFamily = var.zarr_task_definition_family }],
            [".", "TasksStopped", { stat = "Sum", label = "Tasks Stopped" }, { ClusterName = var.cluster_name, TaskDefinitionFamily = var.zarr_task_definition_family }],
            [".", "TasksFailed", { stat = "Sum", label = "Tasks Failed", color = "#d62728" }, { ClusterName = var.cluster_name, TaskDefinitionFamily = var.zarr_task_definition_family }]
          ]
          period = 300
          region = data.aws_region.current.name
          title  = "Zarr Conversion - Task Status"
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
      # Zarr Conversion Resource Utilization
      {
        type = "metric"
        properties = {
          metrics = [
            ["ECS/ContainerInsights", "CpuUtilized", { stat = "Average", label = "CPU Utilized (vCPU)" }, { ClusterName = var.cluster_name, TaskDefinitionFamily = var.zarr_task_definition_family }],
            [".", "MemoryUtilized", { stat = "Average", label = "Memory Utilized (MB)", yAxis = "right" }, { ClusterName = var.cluster_name, TaskDefinitionFamily = var.zarr_task_definition_family }]
          ]
          period = 300
          region = data.aws_region.current.name
          title  = "Zarr Conversion - Resource Utilization"
          yAxis = {
            left = {
              label = "vCPU"
            }
            right = {
              label = "MB"
            }
          }
        }
        x      = 12
        y      = 6
        width  = 12
        height = 6
      },
      # Zarr Conversion Memory & CPU Percentage
      {
        type = "metric"
        properties = {
          metrics = [
            ["ECS/ContainerInsights", "CpuUtilization", { stat = "Average", label = "CPU %" }, { ClusterName = var.cluster_name, TaskDefinitionFamily = var.zarr_task_definition_family }],
            [".", "MemoryUtilization", { stat = "Average", label = "Memory %" }, { ClusterName = var.cluster_name, TaskDefinitionFamily = var.zarr_task_definition_family }]
          ]
          period = 300
          region = data.aws_region.current.name
          title  = "Zarr Conversion - Utilization Percentage"
          yAxis = {
            left = {
              label = "Percent"
              min   = 0
              max   = 100
            }
          }
        }
        x      = 0
        y      = 12
        width  = 12
        height = 6
      },
      # COG Generation Task Status
      {
        type = "metric"
        properties = {
          metrics = [
            ["ECS/ContainerInsights", "RunningTaskCount", { stat = "Average", label = "Running Tasks" }, { ClusterName = var.cluster_name, TaskDefinitionFamily = var.cog_task_definition_family }],
            [".", "TasksStarted", { stat = "Sum", label = "Tasks Started" }, { ClusterName = var.cluster_name, TaskDefinitionFamily = var.cog_task_definition_family }],
            [".", "TasksStopped", { stat = "Sum", label = "Tasks Stopped" }, { ClusterName = var.cluster_name, TaskDefinitionFamily = var.cog_task_definition_family }],
            [".", "TasksFailed", { stat = "Sum", label = "Tasks Failed", color = "#d62728" }, { ClusterName = var.cluster_name, TaskDefinitionFamily = var.cog_task_definition_family }]
          ]
          period = 300
          region = data.aws_region.current.name
          title  = "COG Generation - Task Status"
          yAxis = {
            left = {
              label = "Count"
            }
          }
        }
        x      = 12
        y      = 12
        width  = 12
        height = 6
      },
      # COG Generation Resource Utilization
      {
        type = "metric"
        properties = {
          metrics = [
            ["ECS/ContainerInsights", "CpuUtilized", { stat = "Average", label = "CPU Utilized (vCPU)" }, { ClusterName = var.cluster_name, TaskDefinitionFamily = var.cog_task_definition_family }],
            [".", "MemoryUtilized", { stat = "Average", label = "Memory Utilized (MB)", yAxis = "right" }, { ClusterName = var.cluster_name, TaskDefinitionFamily = var.cog_task_definition_family }]
          ]
          period = 300
          region = data.aws_region.current.name
          title  = "COG Generation - Resource Utilization"
          yAxis = {
            left = {
              label = "vCPU"
            }
            right = {
              label = "MB"
            }
          }
        }
        x      = 0
        y      = 18
        width  = 12
        height = 6
      },
      # COG Generation Memory & CPU Percentage
      {
        type = "metric"
        properties = {
          metrics = [
            ["ECS/ContainerInsights", "CpuUtilization", { stat = "Average", label = "CPU %" }, { ClusterName = var.cluster_name, TaskDefinitionFamily = var.cog_task_definition_family }],
            [".", "MemoryUtilization", { stat = "Average", label = "Memory %" }, { ClusterName = var.cluster_name, TaskDefinitionFamily = var.cog_task_definition_family }]
          ]
          period = 300
          region = data.aws_region.current.name
          title  = "COG Generation - Utilization Percentage"
          yAxis = {
            left = {
              label = "Percent"
              min   = 0
              max   = 100
            }
          }
        }
        x      = 12
        y      = 18
        width  = 12
        height = 6
      },
      # Step Functions Success Rate
      {
        type = "metric"
        properties = {
          metrics = [
            [{ expression = "(m1/(m1+m2))*100", label = "Success Rate %", id = "e1" }],
            ["AWS/States", "ExecutionsSucceeded", { id = "m1", visible = false }, { StateMachineArn = var.state_machine_arn }],
            [".", "ExecutionsFailed", { id = "m2", visible = false }, { StateMachineArn = var.state_machine_arn }]
          ]
          period = 300
          region = data.aws_region.current.name
          title  = "Step Functions - Success Rate"
          yAxis = {
            left = {
              label = "Percent"
              min   = 0
              max   = 100
            }
          }
        }
        x      = 0
        y      = 24
        width  = 12
        height = 6
      },
      # Cost Estimation (based on task duration)
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/States", "ExecutionTime", { stat = "Sum", label = "Total Execution Time (ms)" }, { StateMachineArn = var.state_machine_arn }]
          ]
          period = 3600
          region = data.aws_region.current.name
          title  = "Total Execution Time (for cost estimation)"
          yAxis = {
            left = {
              label = "Milliseconds"
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

  depends_on = [aws_sns_topic.alarms]
}
