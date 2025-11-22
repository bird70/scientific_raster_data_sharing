variable "name" { type = string }
variable "cidr" { type = string }
variable "public_subnet_cidrs" { type = list(string) }
variable "private_subnet_cidrs" { type = list(string) }
variable "azs" { type = list(string) }

variable "tags" {
  type        = map(string)
  description = "Common tags to apply to all resources"
  default     = {}
}