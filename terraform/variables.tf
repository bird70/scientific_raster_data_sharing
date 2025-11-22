variable "aws_region" {
  type    = string
  default = "ap-southeast-2"
}

variable "name" {
  type    = string
  default = "raster-platform"
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
variable "project_owner" {
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