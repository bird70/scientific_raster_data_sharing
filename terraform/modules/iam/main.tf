resource "aws_iam_role" "ecs_task_role" {
  name = "${var.name}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
}

data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "s3_access" {
  name = "${var.name}-s3-access"
  policy = data.aws_iam_policy_document.s3_policy.json
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
  name = "${var.name}-opensearch-access"
  policy = data.aws_iam_policy_document.opensearch_policy.json
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

output "ecs_task_role_arn" { value = aws_iam_role.ecs_task_role.arn }