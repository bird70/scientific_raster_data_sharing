variable "project_name" {
  type        = string
  description = "Name prefix for ingestion resources"
}

variable "aws_region" {
  type        = string
  description = "AWS region"
  default     = "ap-southeast-2"
}

variable "raw_bucket" {
  type        = string
  description = "S3 bucket name for raw NetCDF files"
}

variable "zarr_bucket" {
  type        = string
  description = "S3 bucket name for Zarr output"
}

variable "cog_bucket" {
  type        = string
  description = "S3 bucket name for COG output"
}

variable "stac_bucket" {
  type        = string
  description = "S3 bucket name for STAC items"
}

# OpenSearch variables - REMOVED: Migrated to DynamoDB
# variable "opensearch_endpoint" {
#   type        = string
#   description = "OpenSearch domain endpoint"
# }
#
# variable "opensearch_index" {
#   type        = string
#   description = "OpenSearch index name for STAC items"
#   default     = "stac"
# }

variable "lambda_execution_role_arn" {
  type        = string
  description = "IAM role ARN for Lambda execution"
}

variable "step_functions_role_arn" {
  type        = string
  description = "IAM role ARN for Step Functions execution"
}

variable "ecs_cluster_arn" {
  type        = string
  description = "ECS cluster ARN for conversion tasks"
}

variable "ecs_security_group_id" {
  type        = string
  description = "Security group ID for ECS tasks"
}

variable "private_subnets" {
  type        = list(string)
  description = "Private subnet IDs for ECS tasks"
}

variable "zarr_conversion_task_definition_arn" {
  type        = string
  description = "ECS task definition ARN for Zarr conversion"
  default     = ""
}

variable "cog_generation_task_definition_arn" {
  type        = string
  description = "ECS task definition ARN for COG generation"
  default     = ""
}

variable "tags" {
  type        = map(string)
  description = "Common tags to apply to all resources"
  default     = {}
}

variable "lambda_zarr_converter_arn" {
  type = string
}

variable "lambda_cog_generator_arn" {
  type = string
}

variable "dynamodb_stac_table_name" {
  type        = string
  description = "DynamoDB table name for STAC items"
  default     = ""
}

variable "stac_backend" {
  type        = string
  description = "STAC backend mode: dynamodb, opensearch, or dual"
  default     = "opensearch"
}
