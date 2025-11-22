# Ingestion Pipeline Module
# This module creates Lambda functions, Step Functions state machine, and S3 event notifications
# for the automated NetCDF to Zarr/COG conversion pipeline

# Data source for packaging Lambda functions
data "archive_file" "trigger_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/trigger"
  output_path = "${path.module}/lambda_packages/trigger.zip"
}

data "archive_file" "stac_creator_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/stac_creator"
  output_path = "${path.module}/lambda_packages/stac_creator.zip"
}

data "archive_file" "stac_indexer_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/stac_indexer"
  output_path = "${path.module}/lambda_packages/stac_indexer.zip"
}

# Trigger Lambda Function
resource "aws_lambda_function" "trigger" {
  filename         = data.archive_file.trigger_lambda.output_path
  function_name    = "${var.name}-ingestion-trigger"
  role             = var.lambda_execution_role_arn
  handler          = "handler.lambda_handler"
  source_code_hash = data.archive_file.trigger_lambda.output_base64sha256
  runtime          = "python3.12"
  memory_size      = 256
  timeout          = 60

  environment {
    variables = {
      STATE_MACHINE_ARN = aws_sfn_state_machine.ingestion.arn
    }
  }

  tags = var.tags
}

# STAC Creator Lambda Function
resource "aws_lambda_function" "stac_creator" {
  filename         = data.archive_file.stac_creator_lambda.output_path
  function_name    = "${var.name}-stac-creator"
  role             = var.lambda_execution_role_arn
  handler          = "handler.lambda_handler"
  source_code_hash = data.archive_file.stac_creator_lambda.output_base64sha256
  runtime          = "python3.12"
  memory_size      = 512
  timeout          = 300

  environment {
    variables = {
      STAC_BUCKET = var.stac_bucket
    }
  }

  tags = var.tags
}

# STAC Indexer Lambda Function
resource "aws_lambda_function" "stac_indexer" {
  filename         = data.archive_file.stac_indexer_lambda.output_path
  function_name    = "${var.name}-stac-indexer"
  role             = var.lambda_execution_role_arn
  handler          = "handler.lambda_handler"
  source_code_hash = data.archive_file.stac_indexer_lambda.output_base64sha256
  runtime          = "python3.12"
  memory_size      = 256
  timeout          = 60

  environment {
    variables = {
      OPENSEARCH_ENDPOINT = var.opensearch_endpoint
      OPENSEARCH_INDEX    = var.opensearch_index
      SNS_TOPIC_ARN       = aws_sns_topic.ingestion_failures.arn
    }
  }

  tags = var.tags
}

# S3 bucket notification permission for trigger Lambda
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.trigger.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = "arn:aws:s3:::${var.raw_bucket}"
}

# S3 bucket notification
resource "aws_s3_bucket_notification" "raw_bucket_notification" {
  bucket = var.raw_bucket

  lambda_function {
    lambda_function_arn = aws_lambda_function.trigger.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "ingestion/"
  }

  depends_on = [aws_lambda_permission.allow_s3]
}

# SNS Topic for ingestion failures
resource "aws_sns_topic" "ingestion_failures" {
  name = "${var.name}-ingestion-failures"
  tags = var.tags
}

# Step Functions State Machine
resource "aws_sfn_state_machine" "ingestion" {
  name     = "${var.name}-ingestion-pipeline"
  role_arn = var.step_functions_role_arn
  tags     = var.tags

  definition = jsonencode({
    Comment = "Ingestion pipeline for NetCDF to Zarr/COG conversion"
    StartAt = "ConvertToZarr"
    States = {
      ConvertToZarr = {
        Type     = "Task"
        Resource = "arn:aws:states:::ecs:runTask.sync"
        Parameters = {
          LaunchType     = "FARGATE"
          Cluster        = var.ecs_cluster_arn
          TaskDefinition = var.zarr_conversion_task_definition_arn
          NetworkConfiguration = {
            AwsvpcConfiguration = {
              Subnets        = var.private_subnets
              SecurityGroups = [var.ecs_security_group_id]
              AssignPublicIp = "DISABLED"
            }
          }
          Overrides = {
            ContainerOverrides = [{
              Name = "converter"
              Environment = [
                {
                  Name  = "INPUT_BUCKET"
                  Value = var.raw_bucket
                },
                {
                  Name  = "INPUT_KEY.$"
                  Value = "$.key"
                },
                {
                  Name  = "OUTPUT_BUCKET"
                  Value = var.zarr_bucket
                }
              ]
            }]
          }
        }
        ResultPath = "$.zarr_conversion"
        Next       = "GenerateCOG"
        Catch = [{
          ErrorEquals = ["States.ALL"]
          ResultPath  = "$.error"
          Next        = "NotifyFailure"
        }]
        Retry = [{
          ErrorEquals     = ["States.TaskFailed"]
          IntervalSeconds = 10
          MaxAttempts     = 2
          BackoffRate     = 2.0
        }]
      }

      GenerateCOG = {
        Type     = "Task"
        Resource = "arn:aws:states:::ecs:runTask.sync"
        Parameters = {
          LaunchType     = "FARGATE"
          Cluster        = var.ecs_cluster_arn
          TaskDefinition = var.cog_generation_task_definition_arn
          NetworkConfiguration = {
            AwsvpcConfiguration = {
              Subnets        = var.private_subnets
              SecurityGroups = [var.ecs_security_group_id]
              AssignPublicIp = "DISABLED"
            }
          }
          Overrides = {
            ContainerOverrides = [{
              Name = "cog-generator"
              Environment = [
                {
                  Name  = "ZARR_BUCKET"
                  Value = var.zarr_bucket
                },
                {
                  Name  = "ZARR_KEY.$"
                  Value = "$.zarr_conversion.zarr_key"
                },
                {
                  Name  = "OUTPUT_BUCKET"
                  Value = var.cog_bucket
                }
              ]
            }]
          }
        }
        ResultPath = "$.cog_generation"
        Next       = "CreateSTAC"
        Catch = [{
          ErrorEquals = ["States.ALL"]
          ResultPath  = "$.error"
          Next        = "NotifyFailure"
        }]
        Retry = [{
          ErrorEquals     = ["States.TaskFailed"]
          IntervalSeconds = 10
          MaxAttempts     = 2
          BackoffRate     = 2.0
        }]
      }

      CreateSTAC = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.stac_creator.arn
          Payload = {
            "zarr_bucket" = var.zarr_bucket
            "zarr_key.$"  = "$.zarr_conversion.zarr_key"
            "cog_bucket"  = var.cog_bucket
            "cog_key.$"   = "$.cog_generation.cog_key"
            "metadata.$"  = "$.metadata"
          }
        }
        ResultPath = "$.stac_creation"
        Next       = "IndexSTAC"
        Catch = [{
          ErrorEquals = ["States.ALL"]
          ResultPath  = "$.error"
          Next        = "NotifyFailure"
        }]
        Retry = [{
          ErrorEquals     = ["States.TaskFailed"]
          IntervalSeconds = 2
          MaxAttempts     = 3
          BackoffRate     = 2.0
        }]
      }

      IndexSTAC = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.stac_indexer.arn
          Payload = {
            "stac_bucket" = var.stac_bucket
            "stac_key.$"  = "$.stac_creation.Payload.stac_key"
          }
        }
        ResultPath = "$.stac_indexing"
        Next       = "Success"
        Catch = [{
          ErrorEquals = ["States.ALL"]
          ResultPath  = "$.error"
          Next        = "NotifyFailure"
        }]
        Retry = [{
          ErrorEquals     = ["States.TaskFailed"]
          IntervalSeconds = 2
          MaxAttempts     = 3
          BackoffRate     = 2.0
        }]
      }

      NotifyFailure = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn = aws_sns_topic.ingestion_failures.arn
          Subject  = "Ingestion Pipeline Failure"
          Message = {
            "error.$" = "$.error"
            "input.$" = "$"
          }
        }
        Next = "Fail"
      }

      Success = {
        Type = "Succeed"
      }

      Fail = {
        Type  = "Fail"
        Error = "IngestionPipelineFailed"
        Cause = "The ingestion pipeline encountered an error"
      }
    }
  })
}
