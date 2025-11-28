# Additional S3 permissions for GitHub Actions role
# This allows the GitHub Actions workflow to upload test files for enhanced smoke tests

data "aws_iam_role" "github_actions" {
  name = "GitHubActions-SciRaster-cloud-Role"
}

resource "aws_iam_policy" "github_actions_s3" {
  name        = "GitHubActions-S3-TestUpload"
  description = "Allow GitHub Actions to upload test files to S3 raw bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = [
          "${module.data.s3_raw_bucket_arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          module.data.s3_raw_bucket_arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "states:ListExecutions"
        ]
        Resource = [
          module.ingestion.state_machine_arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_actions_s3" {
  role       = data.aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions_s3.arn
}