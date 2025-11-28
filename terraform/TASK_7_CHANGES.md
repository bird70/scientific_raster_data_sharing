# Task 7: Update Root Terraform Configuration - Changes Summary

## Overview
This document summarizes the changes made to integrate the DynamoDB STAC module into the root Terraform configuration.

## Changes Made

### 1. Added DynamoDB Module Invocation (terraform/main.tf)
- Added `module "dynamodb_stac"` block after the network module
- Passed `project_name` and `tags` (common_tags) to the module
- Module creates the DynamoDB table for STAC items with GSI indexes

### 2. Updated IAM Module (terraform/main.tf)
- Added `dynamodb_stac_table_arn = module.dynamodb_stac.table_arn` parameter
- This provides the IAM module with the DynamoDB table ARN for permission policies

### 3. Updated ECS Module (terraform/main.tf)
- Added `dynamodb_stac_table_name = module.dynamodb_stac.table_name` parameter
- This passes the table name to ECS tasks as an environment variable

### 4. Updated ECS Module Variables (terraform/modules/ecs/variables.tf)
- Added new variable `dynamodb_stac_table_name` with default value ""
- Type: string
- Description: "DynamoDB table name for STAC items"

### 5. Updated ECS Task Definitions (terraform/modules/ecs/main.tf)
- Added `DYNAMODB_STAC_TABLE` environment variable to tiles service task definition
- Added `DYNAMODB_STAC_TABLE` environment variable to timeseries service task definition
- Both reference `var.dynamodb_stac_table_name`

### 6. Updated Ingestion Module (terraform/main.tf)
- Added `dynamodb_stac_table_name = module.dynamodb_stac.table_name` parameter
- This passes the table name to Lambda functions as an environment variable

### 7. Updated Outputs (terraform/outputs.tf)
- Added `dynamodb_stac_table_name` output with description
- Added `dynamodb_stac_table_arn` output with description
- Both outputs reference the dynamodb_stac module

## Validation
- Terraform configuration validated successfully with `terraform validate`
- Only deprecation warnings present (not related to our changes)

## Environment Variables Added
The following environment variable is now available in ECS tasks and Lambda functions:
- `DYNAMODB_STAC_TABLE`: Contains the name of the DynamoDB STAC items table

## Module Dependencies
The DynamoDB module is now properly integrated with:
- IAM module (for permissions)
- ECS module (for application access)
- Ingestion module (for Lambda function access)

## Next Steps
- Deploy the infrastructure with `terraform apply`
- Verify the DynamoDB table is created
- Verify environment variables are set in ECS tasks and Lambda functions
- Test application connectivity to DynamoDB
