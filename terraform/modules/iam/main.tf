resource "aws_iam_role" "ecs_task_role" {
  name               = "${var.name}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
  tags               = var.tags
}

data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# ECS Execution Role (separate from task role)
resource "aws_iam_role" "ecs_execution_role" {
  name               = "${var.name}-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_policy" "s3_access" {
  name   = "${var.name}-s3-access"
  policy = data.aws_iam_policy_document.s3_policy.json
  tags   = var.tags
}

data "aws_iam_policy_document" "s3_policy" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
      "s3:PutObject"
    ]
    resources = concat(
      [for b in var.s3_buckets: "arn:aws:s3:::${b}"],
      [for b in var.s3_buckets: "arn:aws:s3:::${b}/*"]
    )
  }
}

resource "aws_iam_role_policy_attachment" "attach_s3" {
  role = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.s3_access.arn
}

resource "aws_iam_policy" "opensearch_access" {
  name   = "${var.name}-opensearch-access"
  policy = data.aws_iam_policy_document.opensearch_policy.json
  tags   = var.tags
}

data "aws_iam_policy_document" "opensearch_policy" {
  statement {
    effect = "Allow"
    actions = [
      "es:ESHttpGet",
      "es:ESHttpPost",
      "es:ESHttpPut",
      "es:ESHttpDelete"
    ]
    resources = ["arn:aws:es:${var.region}:${data.aws_caller_identity.current.account_id}:domain/*"]
  }
}

resource "aws_iam_role_policy_attachment" "attach_opensearch" {
  role = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.opensearch_access.arn
}

data "aws_caller_identity" "current" {}

# Lambda Execution Role for Ingestion Pipeline
resource "aws_iam_role" "lambda_execution_role" {
  name               = "${var.name}-lambda-execution-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = var.tags
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "lambda_s3_access" {
  name   = "${var.name}-lambda-s3-access"
  policy = data.aws_iam_policy_document.lambda_s3_policy.json
  tags   = var.tags
}

data "aws_iam_policy_document" "lambda_s3_policy" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject"
    ]
    resources = concat(
      [for b in var.s3_buckets : "arn:aws:s3:::${b}/*"]
    )
  }
}

resource "aws_iam_role_policy_attachment" "lambda_s3_access" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_s3_access.arn
}

resource "aws_iam_policy" "lambda_step_functions" {
  name   = "${var.name}-lambda-step-functions"
  policy = data.aws_iam_policy_document.lambda_step_functions_policy.json
  tags   = var.tags
}

data "aws_iam_policy_document" "lambda_step_functions_policy" {
  statement {
    effect = "Allow"
    actions = [
      "states:StartExecution"
    ]
    resources = ["arn:aws:states:${var.region}:${data.aws_caller_identity.current.account_id}:stateMachine:${var.name}-*"]
  }
}

resource "aws_iam_role_policy_attachment" "lambda_step_functions" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_step_functions.arn
}

resource "aws_iam_role_policy_attachment" "lambda_opensearch_access" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.opensearch_access.arn
}

# Step Functions Execution Role
resource "aws_iam_role" "step_functions_execution_role" {
  name               = "${var.name}-step-functions-execution-role"
  assume_role_policy = data.aws_iam_policy_document.step_functions_assume_role.json
  tags               = var.tags
}

data "aws_iam_policy_document" "step_functions_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "step_functions_policy" {
  name   = "${var.name}-step-functions-policy"
  policy = data.aws_iam_policy_document.step_functions_policy.json
  tags   = var.tags
}

data "aws_iam_policy_document" "step_functions_policy" {
  statement {
    effect = "Allow"
    actions = [
      "lambda:InvokeFunction"
    ]
    resources = ["arn:aws:lambda:${var.region}:${data.aws_caller_identity.current.account_id}:function:${var.name}-*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ecs:RunTask"
    ]
    resources = ["arn:aws:ecs:${var.region}:${data.aws_caller_identity.current.account_id}:task-definition/${var.name}-*:*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "iam:PassRole"
    ]
    resources = [
      aws_iam_role.ecs_task_role.arn,
      aws_iam_role.ecs_execution_role.arn
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "sns:Publish"
    ]
    resources = ["arn:aws:sns:${var.region}:${data.aws_caller_identity.current.account_id}:${var.name}-*"]
  }
}

resource "aws_iam_role_policy_attachment" "step_functions_policy" {
  role       = aws_iam_role.step_functions_execution_role.name
  policy_arn = aws_iam_policy.step_functions_policy.arn
}

output "ecs_task_role_arn" { value = aws_iam_role.ecs_task_role.arn }
output "ecs_execution_role_arn" { value = aws_iam_role.ecs_execution_role.arn }
output "lambda_execution_role_arn" { value = aws_iam_role.lambda_execution_role.arn }
output "step_functions_execution_role_arn" { value = aws_iam_role.step_functions_execution_role.arn }