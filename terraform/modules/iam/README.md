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
