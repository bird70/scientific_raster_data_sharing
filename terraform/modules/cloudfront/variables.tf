variable "name" {
  type        = string
  description = "Name prefix for CloudFront resources"
}

variable "alb_dns_name" {
  type        = string
  description = "DNS name of the Application Load Balancer to use as origin"
}

variable "certificate_arn" {
  type        = string
  description = "ARN of ACM certificate for custom domain (optional)"
  default     = ""
}

variable "domain_name" {
  type        = string
  description = "Custom domain name for CloudFront distribution (optional)"
  default     = ""
}

variable "waf_acl_id" {
  type        = string
  description = "ID of WAF Web ACL to associate with distribution (optional)"
  default     = ""
}

variable "price_class" {
  type        = string
  description = "CloudFront price class (PriceClass_All, PriceClass_200, PriceClass_100)"
  default     = "PriceClass_100"
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources"
  default     = {}
}
