variable "project_name" {
  type        = string
  description = "Name prefix for IAM resources"
}

variable "short_name" {
  type        = string
  description = "Short name for AWS resources with length limits"
  default     = "dp-sci-raster"
}

variable "s3_buckets" {
  type        = list(string)
  description = "List of S3 bucket names for IAM policy access"
}

variable "region" {
  type        = string
  description = "AWS region for resource ARNs"
  default     = "ap-southeast-2"
}

# OpenSearch domain variable - REMOVED: Migrated to DynamoDB
# variable "opensearch_domain" {
#   type        = string
#   description = "OpenSearch domain endpoint"
#   default     = ""
# }

variable "tags" {
  type        = map(string)
  description = "Common tags to apply to all resources"
  default     = {}
}

variable "dynamodb_stac_table_arn" {
  type        = string
  description = "ARN of the DynamoDB STAC items table"
  default     = ""
}