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
