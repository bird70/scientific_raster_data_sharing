# Lambda function for zarr conversion
resource "aws_lambda_function" "zarr_converter" {
  function_name = "${var.project_name}-zarr-converter"
  role          = var.lambda_execution_role_arn
  package_type  = "Image"
  image_uri     = "${var.ecr_repository_url}@${var.lambda_image_digest}"
  timeout       = 900   # 15 minutes
  memory_size   = 10240 # 10GB
}

# Lambda function for COG generation
resource "aws_lambda_function" "cog_generator" {
  function_name = "${var.project_name}-cog-generator"
  role          = var.lambda_execution_role_arn
  package_type  = "Image"
  image_uri     = "${var.ecr_repository_url}@${var.cog_image_digest}"
  timeout       = 900   # 15 minutes
  memory_size   = 10240 # 10GB
}
