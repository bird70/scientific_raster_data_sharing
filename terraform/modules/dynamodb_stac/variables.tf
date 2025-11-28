variable "project_name" {
  description = "Name of the project, used for resource naming"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources for cost tracking and organization"
  type        = map(string)
  default     = {}
}
