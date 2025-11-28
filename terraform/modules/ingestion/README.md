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

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

| Name | Version |
|------|---------|
| <a name="provider_archive"></a> [archive](#provider\_archive) | 2.7.1 |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.22.1 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_lambda_function.stac_creator](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function) | resource |
| [aws_lambda_function.stac_indexer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function) | resource |
| [aws_lambda_function.trigger](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function) | resource |
| [aws_lambda_permission.allow_s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission) | resource |
| [aws_s3_bucket_notification.raw_bucket_notification](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_notification) | resource |
| [aws_sfn_state_machine.ingestion](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sfn_state_machine) | resource |
| [aws_sns_topic.ingestion_failures](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic) | resource |
| [archive_file.stac_creator_lambda](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) | data source |
| [archive_file.stac_indexer_lambda](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) | data source |
| [archive_file.trigger_lambda](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region | `string` | `"ap-southeast-2"` | no |
| <a name="input_cog_bucket"></a> [cog\_bucket](#input\_cog\_bucket) | S3 bucket name for COG output | `string` | n/a | yes |
| <a name="input_cog_generation_task_definition_arn"></a> [cog\_generation\_task\_definition\_arn](#input\_cog\_generation\_task\_definition\_arn) | ECS task definition ARN for COG generation | `string` | `""` | no |
| <a name="input_dynamodb_stac_table_name"></a> [dynamodb\_stac\_table\_name](#input\_dynamodb\_stac\_table\_name) | DynamoDB table name for STAC items | `string` | `""` | no |
| <a name="input_ecs_cluster_arn"></a> [ecs\_cluster\_arn](#input\_ecs\_cluster\_arn) | ECS cluster ARN for conversion tasks | `string` | n/a | yes |
| <a name="input_ecs_security_group_id"></a> [ecs\_security\_group\_id](#input\_ecs\_security\_group\_id) | Security group ID for ECS tasks | `string` | n/a | yes |
| <a name="input_lambda_cog_generator_arn"></a> [lambda\_cog\_generator\_arn](#input\_lambda\_cog\_generator\_arn) | n/a | `string` | n/a | yes |
| <a name="input_lambda_execution_role_arn"></a> [lambda\_execution\_role\_arn](#input\_lambda\_execution\_role\_arn) | IAM role ARN for Lambda execution | `string` | n/a | yes |
| <a name="input_lambda_zarr_converter_arn"></a> [lambda\_zarr\_converter\_arn](#input\_lambda\_zarr\_converter\_arn) | n/a | `string` | n/a | yes |
| <a name="input_private_subnets"></a> [private\_subnets](#input\_private\_subnets) | Private subnet IDs for ECS tasks | `list(string)` | n/a | yes |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Name prefix for ingestion resources | `string` | n/a | yes |
| <a name="input_raw_bucket"></a> [raw\_bucket](#input\_raw\_bucket) | S3 bucket name for raw NetCDF files | `string` | n/a | yes |
| <a name="input_stac_backend"></a> [stac\_backend](#input\_stac\_backend) | STAC backend mode: dynamodb, opensearch, or dual | `string` | `"opensearch"` | no |
| <a name="input_stac_bucket"></a> [stac\_bucket](#input\_stac\_bucket) | S3 bucket name for STAC items | `string` | n/a | yes |
| <a name="input_step_functions_role_arn"></a> [step\_functions\_role\_arn](#input\_step\_functions\_role\_arn) | IAM role ARN for Step Functions execution | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Common tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_zarr_bucket"></a> [zarr\_bucket](#input\_zarr\_bucket) | S3 bucket name for Zarr output | `string` | n/a | yes |
| <a name="input_zarr_conversion_task_definition_arn"></a> [zarr\_conversion\_task\_definition\_arn](#input\_zarr\_conversion\_task\_definition\_arn) | ECS task definition ARN for Zarr conversion | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_sns_topic_arn"></a> [sns\_topic\_arn](#output\_sns\_topic\_arn) | ARN of the SNS topic for ingestion failures |
| <a name="output_stac_creator_lambda_arn"></a> [stac\_creator\_lambda\_arn](#output\_stac\_creator\_lambda\_arn) | ARN of the STAC creator Lambda function |
| <a name="output_stac_indexer_lambda_arn"></a> [stac\_indexer\_lambda\_arn](#output\_stac\_indexer\_lambda\_arn) | ARN of the STAC indexer Lambda function |
| <a name="output_state_machine_arn"></a> [state\_machine\_arn](#output\_state\_machine\_arn) | ARN of the Step Functions state machine |
| <a name="output_trigger_lambda_arn"></a> [trigger\_lambda\_arn](#output\_trigger\_lambda\_arn) | ARN of the S3 trigger Lambda function |
<!-- END_TF_DOCS -->