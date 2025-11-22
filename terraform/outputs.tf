output "alb_dns_name" {
  value = module.ecs.alb_dns_name
}

output "cloudfront_domain" {
  value = module.infra.cloudfront_domain
}

output "s3_zarr_bucket" {
  value = module.data.s3_zarr_bucket_id
}

output "opensearch_endpoint" {
  value = module.data.opensearch_domain_endpoint
}