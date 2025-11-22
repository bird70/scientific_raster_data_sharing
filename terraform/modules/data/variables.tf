variable "name" {
  type = string
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