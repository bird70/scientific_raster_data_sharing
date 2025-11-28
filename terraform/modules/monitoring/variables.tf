variable "project_name" {
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

variable "dynamodb_table_name" {
  type        = string
  description = "Name of the DynamoDB STAC items table for monitoring"
  default     = ""
}

variable "state_machine_arn" {
  type        = string
  description = "ARN of the Step Functions state machine for ingestion pipeline"
  default     = ""
}

variable "zarr_task_definition_family" {
  type        = string
  description = "Family name of the Zarr conversion ECS task definition"
  default     = "zarr-conversion"
}

variable "cog_task_definition_family" {
  type        = string
  description = "Family name of the COG generation ECS task definition"
  default     = "cog-generation"
}
