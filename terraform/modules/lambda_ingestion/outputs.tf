output "zarr_converter_arn" {
  value = aws_lambda_function.zarr_converter.arn
}

output "cog_generator_arn" {
  value = aws_lambda_function.cog_generator.arn
}
