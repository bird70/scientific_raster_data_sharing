variable "name" {
  type        = string
  description = "Name prefix for monitoring resources"
}

variable "alb_arn_suffix" {
  type        = string
  description = "ARN suffix of the Application Load Balancer for CloudWatch metrics"
}

variable "tiles_target_group_arn_suffix" {
  type        = string
  description = "ARN suffix of the tiles target group for CloudWatch metrics"
}

variable "timeseries_target_group_arn_suffix" {
  type        = string
  description = "ARN suffix of the timeseries target group for CloudWatch metrics"
}

variable "cluster_name" {
  type        = string
  description = "Name of the ECS cluster"
}

variable "tiles_service_name" {
  type        = string
  description = "Name of the tiles ECS service"
}

variable "timeseries_service_name" {
  type        = string
  description = "Name of the timeseries ECS service"
}

variable "dask_scheduler_service_name" {
  type        = string
  description = "Name of the Dask scheduler ECS service"
}

variable "dask_workers_service_name" {
  type        = string
  description = "Name of the Dask workers ECS service"
}

variable "alarm_email" {
  type        = string
  description = "Email address for alarm notifications (optional)"
  default     = ""
}

variable "tags" {
  type        = map(string)
  description = "Common tags to apply to all resources"
  default     = {}
}
