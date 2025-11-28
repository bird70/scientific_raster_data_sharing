variable "project_name" {
  type        = string
  description = "Name prefix for all resources"
}

variable "cidr" {
  type        = string
  description = "CIDR block for VPC"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for public subnets"
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for private subnets"
}

variable "azs" {
  type        = list(string)
  description = "Availability zones for subnets"
}

variable "aws_region" {
  type        = string
  description = "AWS region for VPC endpoints"
}

variable "tags" {
  type        = map(string)
  description = "Common tags to apply to all resources"
  default     = {}
}