output "bucket_name" {
  description = "Name of the S3 bucket for frontend"
  value       = aws_s3_bucket.frontend.id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.frontend.arn
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.frontend.bucket_regional_domain_name
}

output "cloudfront_oai_iam_arn" {
  description = "IAM ARN of the CloudFront Origin Access Identity"
  value       = aws_cloudfront_origin_access_identity.frontend.iam_arn
}

output "cloudfront_oai_path" {
  description = "CloudFront Origin Access Identity path"
  value       = aws_cloudfront_origin_access_identity.frontend.cloudfront_access_identity_path
}

output "website_endpoint" {
  description = "S3 website endpoint"
  value       = aws_s3_bucket_website_configuration.frontend.website_endpoint
}
