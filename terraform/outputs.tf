output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.ecs.alb_dns_name
}

output "cloudfront_domain" {
  description = "Domain name of the CloudFront distribution"
  value       = module.cloudfront.distribution_domain_name
}

output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution"
  value       = module.cloudfront.distribution_id
}

output "s3_zarr_bucket" {
  description = "S3 bucket for Zarr data"
  value       = module.data.s3_zarr_bucket_id
}

output "s3_cog_bucket" {
  description = "S3 bucket for COG data"
  value       = module.data.s3_cog_bucket_id
}

output "s3_stac_bucket" {
  description = "S3 bucket for STAC items"
  value       = module.data.s3_stac_bucket_id
}

output "opensearch_endpoint" {
  description = "OpenSearch domain endpoint"
  value       = module.data.opensearch_domain_endpoint
}

output "dask_scheduler_endpoint" {
  description = "DNS name of the Dask scheduler"
  value       = module.ecs.dask_scheduler_endpoint
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ecs.cluster_name
}

output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = module.ecs.ecr_repository_url
}

output "ingestion_state_machine_arn" {
  description = "ARN of the ingestion Step Functions state machine"
  value       = module.ingestion.state_machine_arn
}

output "monitoring_sns_topic_arn" {
  description = "ARN of the SNS topic for monitoring alarms"
  value       = module.monitoring.sns_topic_arn
}

output "monitoring_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = module.monitoring.dashboard_name
}
