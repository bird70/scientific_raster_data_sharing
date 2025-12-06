variable "aws_region" {
  type    = string
  default = "ap-southeast-2"
}

variable "project_name" {
  type    = string
  default = "cloud-scientific-raster-sharing"
}

variable "short_name" {
  type        = string
  description = "Short name for AWS resources with length limits"
  default     = "dataplatform-sciraster"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "azs" {
  type    = list(string)
  default = ["ap-southeast-2a", "ap-southeast-2b"]
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "s3_prefix" {
  type    = string
  default = "raster-app"
}

variable "enable_postgis" {
  type    = bool
  default = false
}

variable "rds_allocated_storage" {
  type    = number
  default = 100
}

variable "alb_certificate_arn" {
  type    = string
  default = ""
}

variable "domain_name" {
  type    = string
  default = ""
}

variable "waf_web_acl_id" {
  type    = string
  default = ""
}

variable "cognito_user_pool_id" {
  type    = string
  default = ""
}

variable "cognito_client_id" {
  type    = string
  default = ""
}

# Optional overrides for production tuning
variable "ecs_desired_count_tiles" {
  type    = number
  default = 2
}

variable "ecs_desired_count_timeseries" {
  type    = number
  default = 2
}

# Tagging variables
variable "service_owner" {
  type        = string
  description = "Owner of the project for resource tagging"
}

variable "project_title" {
  type        = string
  description = "Title of the project for resource tagging"
}

variable "environment" {
  type        = string
  description = "Environment name (dev, staging, prod)"
  default     = "dev"
}

variable "cloudfront_price_class" {
  type        = string
  description = "CloudFront price class (PriceClass_All, PriceClass_200, PriceClass_100)"
  default     = "PriceClass_100"
}

variable "alarm_email" {
  type        = string
  description = "Email address for alarm notifications (optional)"
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

variable "dask_workers_min" {
  type        = number
  description = "Minimum number of Dask worker tasks"
  default     = 1
}

variable "dask_workers_max" {
  type        = number
  description = "Maximum number of Dask worker tasks"
  default     = 10
}

variable "opensearch_instance_count" {
  type        = number
  description = "Number of OpenSearch instances (1 for dev, 2+ for prod)"
  default     = 1
}

variable "opensearch_instance_type" {
  type        = string
  description = "OpenSearch instance type (or1.small.search for Graviton, t3.small.search for x86)"
  default     = "t3.small.search"
}

variable "opensearch_ebs_volume_size" {
  type        = number
  description = "EBS volume size in GB for OpenSearch"
  default     = 20
}

variable "redis_node_type" {
  type        = string
  description = "Redis node type (cache.t4g.micro for Graviton, cache.t3.micro for x86)"
  default     = "cache.t3.small"
}

variable "lambda_image_digest" {
  type        = string
  description = "Lambda image digest (sha256:...) for zarr converter"
  default     = "sha256:07bae9b7be28ff2cf56ea3f2273815b49a835ad1f7add5aa2ce9f814834dc22a"
}

variable "cog_image_digest" {
  type        = string
  description = "Lambda image digest (sha256:...) for COG generator"
  default     = "sha256:07bae9b7be28ff2cf56ea3f2273815b49a835ad1f7add5aa2ce9f814834dc22a"
}

variable "stac_backend" {
  type        = string
  description = "STAC backend mode: dynamodb, opensearch, or dual"
  default     = "dynamodb"
  validation {
    condition     = contains(["dynamodb", "opensearch", "dual"], var.stac_backend)
    error_message = "The stac_backend must be one of: dynamodb, opensearch, or dual."
  }
}
