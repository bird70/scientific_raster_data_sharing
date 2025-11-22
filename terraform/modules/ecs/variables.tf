variable "name" {
  type = string
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

variable "opensearch_endpoint" {
  type = string
}

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

variable "opensearch_index" {
  type        = string
  description = "OpenSearch index name"
  default     = "stac"
}

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
