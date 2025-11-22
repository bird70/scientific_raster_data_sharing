# Ingestion Pipeline Module

This module creates the automated ingestion pipeline for converting NetCDF files to Zarr and COG formats.

## Components

### Lambda Functions

1. **Trigger Lambda** (`ingestion-trigger`)
   - Triggered by S3 ObjectCreated events
   - Validates file extension (.nc)
   - Starts Step Functions execution

2. **STAC Creator Lambda** (`stac-creator`)
   - Reads Zarr metadata
   - Generates STAC item JSON
   - Writes to STAC S3 bucket

3. **STAC Indexer Lambda** (`stac-indexer`)
   - Reads STAC item from S3
   - Indexes in OpenSearch
   - Sends SNS notification on failure

### Step Functions State Machine

Orchestrates the conversion workflow:
1. ValidateInput - Validates the input file
2. ConvertToZarr - Runs ECS task to convert NetCDF to Zarr
3. GenerateCOG - Runs ECS task to generate COG from Zarr
4. CreateSTAC - Creates STAC item metadata
5. IndexSTAC - Indexes STAC item in OpenSearch
6. NotifyFailure - Sends SNS notification on error

### S3 Event Notification

- Bucket: Raw bucket
- Prefix: `ingestion/`
- Event: `s3:ObjectCreated:*`
- Target: Trigger Lambda

### SNS Topic

- Topic: `{name}-ingestion-failures`
- Used for error notifications

## Usage

```hcl
module "ingestion" {
  source = "./modules/ingestion"
  
  name                                 = "raster-platform"
  aws_region                           = "ap-southeast-2"
  raw_bucket                           = module.data.s3_raw_bucket_id
  zarr_bucket                          = module.data.s3_zarr_bucket_id
  cog_bucket                           = module.data.s3_cog_bucket_id
  stac_bucket                          = module.data.s3_stac_bucket_id
  opensearch_endpoint                  = module.data.opensearch_domain_endpoint
  opensearch_index                     = "stac"
  lambda_execution_role_arn            = module.iam.lambda_execution_role_arn
  step_functions_role_arn              = module.iam.step_functions_execution_role_arn
  ecs_cluster_arn                      = module.ecs.cluster_arn
  ecs_security_group_id                = module.network.ecs_tasks_security_group_id
  private_subnets                      = module.network.private_subnet_ids
  zarr_conversion_task_definition_arn  = ""  # To be created
  cog_generation_task_definition_arn   = ""  # To be created
  tags                                 = local.common_tags
}
```

## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name prefix for resources | string | - | yes |
| aws_region | AWS region | string | ap-southeast-2 | no |
| raw_bucket | S3 bucket for raw NetCDF files | string | - | yes |
| zarr_bucket | S3 bucket for Zarr output | string | - | yes |
| cog_bucket | S3 bucket for COG output | string | - | yes |
| stac_bucket | S3 bucket for STAC items | string | - | yes |
| opensearch_endpoint | OpenSearch endpoint | string | - | yes |
| opensearch_index | OpenSearch index name | string | stac | no |
| lambda_execution_role_arn | Lambda IAM role ARN | string | - | yes |
| step_functions_role_arn | Step Functions IAM role ARN | string | - | yes |
| ecs_cluster_arn | ECS cluster ARN | string | - | yes |
| ecs_security_group_id | ECS security group ID | string | - | yes |
| private_subnets | Private subnet IDs | list(string) | - | yes |
| zarr_conversion_task_definition_arn | Zarr conversion task ARN | string | "" | no |
| cog_generation_task_definition_arn | COG generation task ARN | string | "" | no |
| tags | Resource tags | map(string) | {} | no |

## Outputs

| Name | Description |
|------|-------------|
| trigger_lambda_arn | Trigger Lambda ARN |
| stac_creator_lambda_arn | STAC creator Lambda ARN |
| stac_indexer_lambda_arn | STAC indexer Lambda ARN |
| state_machine_arn | Step Functions state machine ARN |
| sns_topic_arn | SNS topic ARN for failures |

## Lambda Deployment

Lambda functions are packaged as zip files from the `lambda/` directory. To update Lambda code:

1. Modify the Python handler files
2. Run `terraform apply` to repackage and deploy

For the STAC indexer Lambda, dependencies are specified in `requirements.txt` and should be packaged with the function code in production deployments.

## Requirements

- Requirements 4.1: S3 event triggers Lambda
- Requirements 4.2: Lambda starts Step Functions workflow
- Requirements 4.3: Step Functions orchestrates conversion
- Requirements 4.4: STAC creation and indexing
- Requirements 4.5: Error handling and SNS notifications
- Requirements 9.6: Resource tagging
