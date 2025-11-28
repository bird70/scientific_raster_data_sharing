#!/bin/bash
# Script to remove failed resources from Terraform state

echo "Removing failed resources from Terraform state..."

# Remove CloudFront if it failed
terraform state rm 'module.cloudfront.aws_cloudfront_distribution.main' 2>/dev/null || echo "CloudFront not in state"

# Remove HTTPS listener if it failed  
terraform state rm 'module.ecs.aws_lb_listener.https[0]' 2>/dev/null || echo "HTTPS listener not in state"
terraform state rm 'module.ecs.aws_lb_listener.https' 2>/dev/null || echo "HTTPS listener not in state"

# Remove OpenSearch if it failed
terraform state rm 'module.data.aws_opensearch_domain.stac' 2>/dev/null || echo "OpenSearch not in state"

# Remove Redis if it failed
terraform state rm 'module.data.aws_elasticache_cluster.redis' 2>/dev/null || echo "Redis not in state"

# Remove Lambda functions if they failed
terraform state rm 'module.ingestion.aws_lambda_function.stac_creator' 2>/dev/null || echo "STAC creator Lambda not in state"
terraform state rm 'module.ingestion.aws_lambda_function.stac_indexer' 2>/dev/null || echo "STAC indexer Lambda not in state"
terraform state rm 'module.ingestion.aws_lambda_function.trigger' 2>/dev/null || echo "Trigger Lambda not in state"

# Remove VPC endpoint if it failed
terraform state rm 'module.network.aws_vpc_endpoint.es' 2>/dev/null || echo "ES VPC endpoint not in state"
terraform state rm 'module.network.aws_vpc_endpoint.opensearch' 2>/dev/null || echo "OpenSearch VPC endpoint not in state"

echo "Done! Now run: terraform apply"
