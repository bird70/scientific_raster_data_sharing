output "table_name" {
  description = "Name of the DynamoDB STAC items table"
  value       = aws_dynamodb_table.stac_items.name
}

output "table_arn" {
  description = "ARN of the DynamoDB STAC items table"
  value       = aws_dynamodb_table.stac_items.arn
}

output "table_id" {
  description = "ID of the DynamoDB STAC items table"
  value       = aws_dynamodb_table.stac_items.id
}

output "collection_index_name" {
  description = "Name of the collection Global Secondary Index"
  value       = "collection-index"
}

output "datetime_index_name" {
  description = "Name of the datetime Global Secondary Index"
  value       = "datetime-index"
}
