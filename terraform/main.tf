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

data "aws_caller_identity" "current" {}

locals {
  common_tags = {
    service_owner = var.service_owner
    project_title = var.project_title
    environment   = var.environment
    managed_by    = "terraform"
  }
}

module "network" {
  source               = "./modules/network"
  project_name         = var.project_name
  cidr                 = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  azs                  = var.azs
  aws_region           = var.aws_region
  tags                 = local.common_tags
}

module "dynamodb_stac" {
  source       = "./modules/dynamodb_stac"
  project_name = var.project_name
  tags         = local.common_tags
}

module "iam" {
  source       = "./modules/iam"
  project_name = var.project_name
  short_name   = var.short_name
  s3_buckets = [
    module.data.s3_raw_bucket_id,
    module.data.s3_zarr_bucket_id,
    module.data.s3_cog_bucket_id,
    module.data.s3_stac_bucket_id
  ]
  # OpenSearch removed - migrated to DynamoDB
  # opensearch_domain       = module.data.opensearch_domain_endpoint
  dynamodb_stac_table_arn = module.dynamodb_stac.table_arn
  tags                    = local.common_tags
}

module "data" {
  source                             = "./modules/data"
  project_name                       = var.project_name
  short_name                         = var.short_name
  vpc_sg_id                          = module.network.data_security_group_id
  private_subnets                    = module.network.private_subnet_ids
  enable_rds                         = var.enable_postgis
  rds_allocated_storage              = var.rds_allocated_storage
  # OpenSearch removed - migrated to DynamoDB
  # opensearch_service_linked_role_arn = module.iam.opensearch_service_linked_role_arn
  # opensearch_instance_type           = var.opensearch_instance_type
  # opensearch_instance_count          = var.opensearch_instance_count
  # opensearch_ebs_volume_size         = var.opensearch_ebs_volume_size
  redis_node_type                    = var.redis_node_type
  tags                               = local.common_tags
}

module "ecs" {
  source                     = "./modules/ecs"
  project_name               = var.project_name
  short_name                 = var.short_name
  vpc_id                     = module.network.vpc_id
  public_subnets             = module.network.public_subnet_ids
  private_subnets            = module.network.private_subnet_ids
  ecr_repo_name              = "${var.project_name}-repo"
  s3_zarr_bucket             = module.data.s3_zarr_bucket_id
  s3_cog_bucket              = module.data.s3_cog_bucket_id
  # OpenSearch removed - migrated to DynamoDB
  # opensearch_endpoint        = module.data.opensearch_domain_endpoint
  # opensearch_index           = "stac"
  dynamodb_stac_table_name   = module.dynamodb_stac.table_name
  stac_backend               = var.stac_backend
  redis_endpoint             = module.data.redis_primary_endpoint_address
  cognito_user_pool_id       = var.cognito_user_pool_id
  cognito_client_id          = var.cognito_client_id
  alb_sg_id                  = module.network.alb_security_group_id
  ecs_sg_id                  = module.network.ecs_tasks_security_group_id
  dask_sg_id                 = module.network.dask_security_group_id
  certificate_arn            = var.alb_certificate_arn
  task_role_arn              = module.iam.ecs_task_role_arn
  execution_role_arn         = module.iam.ecs_execution_role_arn
  image_uri                  = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${var.project_name}-repo:latest"
  aws_region                 = var.aws_region
  dask_scheduler_endpoint    = "scheduler.dask.local"
  tiles_desired_count        = var.ecs_desired_count_tiles
  timeseries_desired_count   = var.ecs_desired_count_timeseries
  dask_workers_desired_count = var.ecs_desired_count_tiles # Reuse tiles count for workers
  tags                       = local.common_tags
}

module "cloudfront" {
  count           = var.alb_certificate_arn != "" && var.alb_certificate_arn != "arn:aws:acm:ap-southeast-2:123456789012:certificate/EXAMPLE" ? 1 : 0
  source          = "./modules/cloudfront"
  project_name    = var.project_name
  alb_dns_name    = module.ecs.alb_dns_name
  certificate_arn = var.alb_certificate_arn
  domain_name     = var.domain_name
  waf_acl_id      = var.waf_web_acl_id
  price_class     = var.cloudfront_price_class
  tags            = local.common_tags
}

module "monitoring" {
  source                             = "./modules/monitoring"
  project_name                       = var.project_name
  alb_arn_suffix                     = module.ecs.alb_arn_suffix
  tiles_target_group_arn_suffix      = module.ecs.tiles_target_group_arn_suffix
  timeseries_target_group_arn_suffix = module.ecs.timeseries_target_group_arn_suffix
  cluster_name                       = module.ecs.cluster_name
  tiles_service_name                 = module.ecs.tiles_service_name
  timeseries_service_name            = module.ecs.timeseries_service_name
  dask_scheduler_service_name        = module.ecs.dask_scheduler_service_name
  dask_workers_service_name          = module.ecs.dask_workers_service_name
  dynamodb_table_name                = module.dynamodb_stac.table_name
  state_machine_arn                  = module.ingestion.state_machine_arn
  zarr_task_definition_family        = "zarr-conversion"
  cog_task_definition_family         = "cog-generation"
  alarm_email                        = var.alarm_email
  tags                               = local.common_tags
}

module "ingestion" {
  source                              = "./modules/ingestion"
  project_name                        = var.project_name
  aws_region                          = var.aws_region
  raw_bucket                          = module.data.s3_raw_bucket_id
  zarr_bucket                         = module.data.s3_zarr_bucket_id
  cog_bucket                          = module.data.s3_cog_bucket_id
  stac_bucket                         = module.data.s3_stac_bucket_id
  # OpenSearch removed - migrated to DynamoDB
  # opensearch_endpoint                 = module.data.opensearch_domain_endpoint
  # opensearch_index                    = "stac"
  dynamodb_stac_table_name            = module.dynamodb_stac.table_name
  stac_backend                        = var.stac_backend
  lambda_execution_role_arn           = module.iam.lambda_execution_role_arn
  step_functions_role_arn             = module.iam.step_functions_execution_role_arn
  ecs_cluster_arn                     = module.ecs.cluster_arn
  ecs_security_group_id               = module.network.ecs_tasks_security_group_id
  private_subnets                     = module.network.private_subnet_ids
  zarr_conversion_task_definition_arn = module.ecs.zarr_conversion_task_definition_arn
  cog_generation_task_definition_arn  = module.ecs.cog_generation_task_definition_arn
  tags                                = local.common_tags
  lambda_zarr_converter_arn           = module.lambda_ingestion.zarr_converter_arn
  lambda_cog_generator_arn            = module.lambda_ingestion.cog_generator_arn
}


module "lambda_ingestion" {
  source = "./modules/lambda_ingestion"

  project_name              = var.project_name
  lambda_execution_role_arn = module.iam.lambda_execution_role_arn
  ecr_repository_url        = module.ecs.ecr_repository_url
  aws_region                = var.aws_region
  lambda_image_digest       = var.lambda_image_digest
  cog_image_digest          = var.cog_image_digest
}
