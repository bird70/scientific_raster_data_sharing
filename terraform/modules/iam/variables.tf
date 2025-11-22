variable "name" {
  type        = string
  description = "Name prefix for IAM resources"
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

variable "opensearch_domain" {
  type        = string
  description = "OpenSearch domain endpoint"
  default     = ""
}

variable "tags" {
  type        = map(string)
  description = "Common tags to apply to all resources"
  default     = {}
}