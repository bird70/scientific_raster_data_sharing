variable "project_name" {
  type = string
}

variable "short_name" {
  type        = string
  description = "Short name for AWS resources with length limits"
  default     = "dp-sci-raster"
}

variable "private_subnets" {
  type = list(string)
}

variable "vpc_sg_id" {
  type = string
}

variable "db_username" {
  type    = string
  default = "stac"
}

variable "db_password" {
  type    = string
  default = "changeMe123!"
}

variable "enable_rds" {
  type    = bool
  default = false
}

variable "rds_allocated_storage" {
  type    = number
  default = 100
}

variable "tags" {
  type        = map(string)
  description = "Common tags to apply to all resources"
  default     = {}
}

# OpenSearch variables - REMOVED: Migrated to DynamoDB
# variable "opensearch_service_linked_role_arn" {
#   type        = string
#   description = "ARN of the OpenSearch service-linked role"
# }
#
# variable "opensearch_instance_type" {
#   type        = string
#   description = "OpenSearch instance type"
#   default     = "t3.small.search"
# }
#
# variable "opensearch_instance_count" {
#   type        = number
#   description = "Number of OpenSearch instances"
#   default     = 2
# }
#
# variable "opensearch_ebs_volume_size" {
#   type        = number
#   description = "EBS volume size in GB for OpenSearch"
#   default     = 20
# }

variable "redis_node_type" {
  type        = string
  description = "Redis node type"
  default     = "cache.t3.small"
}