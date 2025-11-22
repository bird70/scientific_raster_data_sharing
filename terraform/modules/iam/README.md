# IAM Module

This module creates IAM roles and policies for ECS tasks, Lambda functions, and Step Functions in the Raster Time-series Access Web Service.

## Components

### ECS Task Role

The ECS task role is assumed by running ECS tasks and provides permissions for:
- **S3 Access**: Read/write access to data buckets (raw, zarr, cog, stac)
- **OpenSearch Access**: HTTP operations on OpenSearch domains
- **CloudWatch**: Metric and log publishing

This role is separate from the execution role and provides application-level permissions.

### ECS Execution Role

The ECS execution role is used by the ECS agent to:
- Pull container images from ECR
- Write logs to CloudWatch
- Retrieve secrets from Secrets Manager (if configured)

This role uses the AWS managed policy `AmazonECSTaskExecutionRolePolicy`.

### Lambda Execution Role

The Lambda execution role provides permissions for ingestion pipeline Lambda functions:
- **Basic Execution**: CloudWatch Logs access via AWS managed policy
- **S3 Access**: Read/write to data buckets
- **Step Functions**: Start execution of state machines
- **OpenSearch Access**: Index STAC items

### Step Functions Execution Role

The Step Functions execution role orchestrates the ingestion workflow:
- **Lambda Invocation**: Invoke Lambda functions
- **ECS Task Execution**: Run ECS tasks for conversion
- **IAM PassRole**: Pass ECS task and execution roles
- **SNS Publishing**: Send failure notifications

## Usage

```hcl
module "iam" {
  source = "./modules/iam"
  
  name = "raster-platform"
  s3_buckets = [
    "raster-platform-raw-abc123",
    "raster-platform-zarr-abc123",
    "raster-platform-cog-abc123",
    "raster-platform-stac-abc123"
  ]
  opensearch_domain = "vpc-raster-platform-stac-xyz.ap-southeast-2.es.amazonaws.com"
  region            = "ap-southeast-2"
  
  tags = {
    project_owner = "platform-team"
    project_title = "raster-platform"
    environment   = "production"
  }
}
```

## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name prefix for IAM resources | string | - | yes |
| s3_buckets | List of S3 bucket names for IAM policy access | list(string) | - | yes |
| region | AWS region for resource ARNs | string | ap-southeast-2 | no |
| opensearch_domain | OpenSearch domain endpoint | string | "" | no |
| tags | Common tags to apply to all resources | map(string) | {} | no |

## Outputs

| Name | Description |
|------|-------------|
| ecs_task_role_arn | ARN of the ECS task role |
| ecs_execution_role_arn | ARN of the ECS execution role |
| lambda_execution_role_arn | ARN of the Lambda execution role |
| step_functions_execution_role_arn | ARN of the Step Functions execution role |

## Security Best Practices

### Least Privilege

All policies follow least-privilege principles:
- S3 policies specify exact bucket ARNs
- OpenSearch policies scope to specific domains
- Lambda and ECS task ARNs use name prefixes to limit scope

### Separation of Concerns

- **Task Role**: Application permissions (S3, OpenSearch)
- **Execution Role**: Infrastructure permissions (ECR, CloudWatch)
- **Lambda Role**: Function-specific permissions
- **Step Functions Role**: Orchestration permissions

### Resource-Based Policies

IAM policies use specific resource ARNs rather than wildcards:
```hcl
resources = [
  "arn:aws:s3:::${bucket_name}",
  "arn:aws:s3:::${bucket_name}/*"
]
```

## IAM Policy Structure

### S3 Access Policy
```json
{
  "Effect": "Allow",
  "Action": [
    "s3:GetObject",
    "s3:ListBucket",
    "s3:PutObject"
  ],
  "Resource": [
    "arn:aws:s3:::bucket-name",
    "arn:aws:s3:::bucket-name/*"
  ]
}
```

### OpenSearch Access Policy
```json
{
  "Effect": "Allow",
  "Action": [
    "es:ESHttpGet",
    "es:ESHttpPost",
    "es:ESHttpPut",
    "es:ESHttpDelete"
  ],
  "Resource": "arn:aws:es:region:account:domain/*"
}
```

## Requirements

- Requirements 4.5: Lambda and Step Functions IAM roles
- Requirements 6.5: Least-privilege IAM policies
- Requirements 9.6: Resource tagging

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.22.1 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_iam_policy.lambda_s3_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.lambda_step_functions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.opensearch_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.s3_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.step_functions_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.ecs_execution_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.ecs_task_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.lambda_execution_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.step_functions_execution_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.attach_opensearch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.attach_s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.ecs_execution_role_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.lambda_basic_execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.lambda_opensearch_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.lambda_s3_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.lambda_step_functions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.step_functions_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_service_linked_role.opensearch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_service_linked_role) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.ecs_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.lambda_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.lambda_s3_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.lambda_step_functions_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.opensearch_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.s3_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.step_functions_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.step_functions_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_name"></a> [name](#input\_name) | Name prefix for IAM resources | `string` | n/a | yes |
| <a name="input_opensearch_domain"></a> [opensearch\_domain](#input\_opensearch\_domain) | OpenSearch domain endpoint | `string` | `""` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region for resource ARNs | `string` | `"ap-southeast-2"` | no |
| <a name="input_s3_buckets"></a> [s3\_buckets](#input\_s3\_buckets) | List of S3 bucket names for IAM policy access | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Common tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_ecs_execution_role_arn"></a> [ecs\_execution\_role\_arn](#output\_ecs\_execution\_role\_arn) | n/a |
| <a name="output_ecs_task_role_arn"></a> [ecs\_task\_role\_arn](#output\_ecs\_task\_role\_arn) | n/a |
| <a name="output_lambda_execution_role_arn"></a> [lambda\_execution\_role\_arn](#output\_lambda\_execution\_role\_arn) | n/a |
| <a name="output_opensearch_service_linked_role_arn"></a> [opensearch\_service\_linked\_role\_arn](#output\_opensearch\_service\_linked\_role\_arn) | n/a |
| <a name="output_step_functions_execution_role_arn"></a> [step\_functions\_execution\_role\_arn](#output\_step\_functions\_execution\_role\_arn) | n/a |
<!-- END_TF_DOCS -->