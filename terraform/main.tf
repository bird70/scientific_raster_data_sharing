terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  common_tags = {
    project_owner = var.project_owner
    project_title = var.project_title
    environment   = var.environment
    managed_by    = "terraform"
  }
}

module "network" {
  source               = "./modules/network"
  name                 = var.name
  cidr                 = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  azs                  = var.azs
  aws_region           = var.aws_region
  tags                 = local.common_tags
}

module "iam" {
  source = "./modules/iam"
  name   = var.name
  s3_buckets = [
    module.data.s3_raw_bucket_id,
    module.data.s3_zarr_bucket_id,
    module.data.s3_cog_bucket_id,
    module.data.s3_stac_bucket_id
  ]
  opensearch_domain = module.data.opensearch_domain_endpoint
  tags              = local.common_tags
}

module "data" {
  source                = "./modules/data"
  name                  = var.name
  vpc_sg_id             = module.network.data_security_group_id
  private_subnets       = module.network.private_subnet_ids
  enable_rds            = var.enable_postgis
  rds_allocated_storage = var.rds_allocated_storage
  tags                  = local.common_tags
}

module "ecs" {
  source               = "./modules/ecs"
  name                 = var.name
  vpc_id               = module.network.vpc_id
  public_subnets       = module.network.public_subnet_ids
  private_subnets      = module.network.private_subnet_ids
  ecr_repo_name        = "${var.name}-repo"
  s3_zarr_bucket       = module.data.s3_zarr_bucket_id
  opensearch_endpoint  = module.data.opensearch_domain_endpoint
  redis_endpoint       = module.data.redis_primary_endpoint_address
  cognito_user_pool_id = var.cognito_user_pool_id
  tags                 = local.common_tags
}

# CloudFront/infra module will be added in task 7
# module "infra" {
#   source = "./modules/infra"
#   name = var.name
#   alb_certificate_arn = var.alb_certificate_arn
#   domain_name = var.domain_name
#   alb_security_group_id = module.network.alb_security_group_id
#   alb_dns_name = module.ecs.alb_dns_name
#   cloudfront_origin_id = "${var.name}-alb-origin"
#   web_acl_id = var.waf_web_acl_id
#   tags = local.common_tags
# }
