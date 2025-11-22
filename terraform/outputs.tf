output "alb_dns_name" {
  value = module.ecs.alb_dns_name
}

# CloudFront module will be added in task 7
# output "cloudfront_domain" {
#   value = module.cloudfront.cloudfront_domain
# }

output "s3_zarr_bucket" {
  value = module.data.s3_zarr_bucket_id
}

output "opensearch_endpoint" {
  value = module.data.opensearch_domain_endpoint
}
o
utput "dask_scheduler_endpoint" {
  description = "DNS name of the Dask scheduler"
  value       = module.ecs.dask_scheduler_endpoint
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ecs.cluster_name
}
