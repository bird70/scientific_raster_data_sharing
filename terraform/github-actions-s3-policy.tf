# Additional S3 permissions for GitHub Actions role
# This allows the GitHub Actions workflow to upload test files for enhanced smoke tests

data "aws_iam_role" "github_actions" {
  name = "GitHubActions-SciRaster-Platform-Role"
}

resource "aws_iam_policy" "github_actions_s3" {
  name        = "GitHubActions-S3-TestUpload"
  description = "Allow GitHub Actions to upload test files and deploy frontend to S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "${module.data.s3_raw_bucket_arn}/*",
          "arn:aws:s3:::cloud-scientific-raster-sharing-frontend-dev/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          module.data.s3_raw_bucket_arn,
          "arn:aws:s3:::cloud-scientific-raster-sharing-frontend-dev"
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