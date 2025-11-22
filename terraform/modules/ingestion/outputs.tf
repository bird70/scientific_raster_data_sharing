output "trigger_lambda_arn" {
  description = "ARN of the S3 trigger Lambda function"
  value       = aws_lambda_function.trigger.arn
}

output "stac_creator_lambda_arn" {
  description = "ARN of the STAC creator Lambda function"
  value       = aws_lambda_function.stac_creator.arn
}

output "stac_indexer_lambda_arn" {
  description = "ARN of the STAC indexer Lambda function"
  value       = aws_lambda_function.stac_indexer.arn
}

output "state_machine_arn" {
  description = "ARN of the Step Functions state machine"
  value       = aws_sfn_state_machine.ingestion.arn
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for ingestion failures"
  value       = aws_sns_topic.ingestion_failures.arn
}
