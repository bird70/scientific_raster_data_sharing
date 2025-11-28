# DynamoDB table for STAC items
resource "aws_dynamodb_table" "stac_items" {
  name         = "${var.project_name}-stac-items"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  # Primary key attribute
  attribute {
    name = "id"
    type = "S"
  }

  # GSI attributes
  attribute {
    name = "collection"
    type = "S"
  }

  attribute {
    name = "datetime"
    type = "S"
  }

  # Global Secondary Index for collection-based queries
  global_secondary_index {
    name            = "collection-index"
    hash_key        = "collection"
    range_key       = "datetime"
    projection_type = "ALL"
  }

  # Global Secondary Index for datetime-based queries
  global_secondary_index {
    name            = "datetime-index"
    hash_key        = "datetime"
    range_key       = "id"
    projection_type = "ALL"
  }

  # Enable point-in-time recovery for data protection
  point_in_time_recovery {
    enabled = true
  }

  # Enable server-side encryption with AWS managed keys
  server_side_encryption {
    enabled = true
  }

  # Apply tags for cost tracking
  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-stac-items"
    }
  )
}
