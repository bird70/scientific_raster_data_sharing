variable "name" { type = string }
variable "s3_buckets" { type = list(string) }
variable "region" { type = string, default = "ap-southeast-2" }

variable "tags" {
  type        = map(string)
  description = "Common tags to apply to all resources"
  default     = {}
}