variable "project_name" {
  type = string
}

variable "lambda_execution_role_arn" {
  type = string
}

variable "ecr_repository_url" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "lambda_image_digest" {
  type = string
}

variable "cog_image_digest" {
  type = string
}
