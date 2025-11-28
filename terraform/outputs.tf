output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.ecs.alb_dns_name
}

output "cloudfront_domain" {
  description = "Domain name of the CloudFront distribution"
  value       = length(module.cloudfront) > 0 ? module.cloudfront[0].distribution_domain_name : "N/A - CloudFront not enabled"
}

output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution"
  value       = length(module.cloudfront) > 0 ? module.cloudfront[0].distribution_id : "N/A - CloudFront not enabled"
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

output "s3_raw_bucket" {
  description = "S3 bucket for raw data"
  value       = module.data.s3_raw_bucket_id
}

# OpenSearch endpoint - REMOVED: Migrated to DynamoDB
# output "opensearch_endpoint" {
#   description = "OpenSearch domain endpoint"
#   value       = module.data.opensearch_domain_endpoint
# }

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

output "lambda_zarr_converter_arn" {
  description = "ARN of the Lambda zarr converter function"
  value       = module.lambda_ingestion.zarr_converter_arn
}

output "lambda_cog_generator_arn" {
  description = "ARN of the Lambda COG generator function"
  value       = module.lambda_ingestion.cog_generator_arn
}

output "lambda_trigger_arn" {
  description = "ARN of the S3 trigger Lambda function"
  value       = module.ingestion.trigger_lambda_arn
}

output "lambda_stac_creator_arn" {
  description = "ARN of the STAC creator Lambda function"
  value       = module.ingestion.stac_creator_lambda_arn
}

output "lambda_stac_indexer_arn" {
  description = "ARN of the STAC indexer Lambda function"
  value       = module.ingestion.stac_indexer_lambda_arn
}

output "dynamodb_stac_table_name" {
  description = "Name of the DynamoDB STAC items table"
  value       = module.dynamodb_stac.table_name
}

output "dynamodb_stac_table_arn" {
  description = "ARN of the DynamoDB STAC items table"
  value       = module.dynamodb_stac.table_arn
}

output "stac_backend" {
  description = "STAC backend mode (dynamodb, opensearch, or dual)"
  value       = var.stac_backend
}

output "cluster_name" {
  description = "Name of the ECS cluster (for verification scripts)"
  value       = module.ecs.cluster_name
}
