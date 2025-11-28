variable "project_name" {
  type = string
}

variable "short_name" {
  type        = string
  description = "Short name for AWS resources with length limits"
  default     = "dp-sci-raster"
}

variable "vpc_id" {
  type = string
}

variable "public_subnets" {
  type = list(string)
}

variable "private_subnets" {
  type = list(string)
}

variable "ecr_repo_name" {
  type = string
}

variable "s3_zarr_bucket" {
  type = string
}

# OpenSearch endpoint - REMOVED: Migrated to DynamoDB
# variable "opensearch_endpoint" {
#   type = string
# }

variable "redis_endpoint" {
  type = string
}

variable "cognito_user_pool_id" {
  type = string
}

variable "alb_sg_id" {
  type    = string
  default = ""
}

variable "certificate_arn" {
  type    = string
  default = ""
}

variable "tags" {
  type        = map(string)
  description = "Common tags to apply to all resources"
  default     = {}
}

variable "task_role_arn" {
  type        = string
  description = "ARN of the IAM role for ECS tasks"
}

variable "execution_role_arn" {
  type        = string
  description = "ARN of the IAM role for ECS task execution"
}

variable "image_uri" {
  type        = string
  description = "URI of the Docker image in ECR"
}

variable "aws_region" {
  type        = string
  description = "AWS region"
  default     = "ap-southeast-2"
}

variable "s3_cog_bucket" {
  type        = string
  description = "S3 bucket name for COG files"
}

# OpenSearch index - REMOVED: Migrated to DynamoDB
# variable "opensearch_index" {
#   type        = string
#   description = "OpenSearch index name"
#   default     = "stac"
# }

variable "cognito_client_id" {
  type        = string
  description = "Cognito user pool client ID"
}

variable "ecs_sg_id" {
  type        = string
  description = "Security group ID for ECS tasks"
}

variable "dask_scheduler_endpoint" {
  type        = string
  description = "Dask scheduler endpoint"
  default     = ""
}

variable "dask_sg_id" {
  type        = string
  description = "Security group ID for Dask cluster"
  default     = ""
}


# Cost optimization variables
variable "tiles_desired_count" {
  type        = number
  description = "Desired number of tiles service tasks"
  default     = 2
}

variable "timeseries_desired_count" {
  type        = number
  description = "Desired number of timeseries service tasks"
  default     = 2
}

variable "dask_workers_desired_count" {
  type        = number
  description = "Desired number of Dask worker tasks"
  default     = 2
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
