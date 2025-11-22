terraform {
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}

resource "random_id" "suffix" {
  byte_length = 4
}

# S3 Buckets
resource "aws_s3_bucket" "raw" {
  bucket        = "${var.name}-raw-${random_id.suffix.hex}"
  force_destroy = false
  tags          = merge(var.tags, { Name = "${var.name}-raw" })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "raw" {
  bucket = aws_s3_bucket.raw.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "raw" {
  bucket = aws_s3_bucket.raw.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "raw" {
  bucket = aws_s3_bucket.raw.id

  rule {
    id     = "transition-old-versions"
    status = "Enabled"

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_transition {
      noncurrent_days = 90
      storage_class   = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket" "zarr" {
  bucket        = "${var.name}-zarr-${random_id.suffix.hex}"
  force_destroy = false
  tags          = merge(var.tags, { Name = "${var.name}-zarr" })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "zarr" {
  bucket = aws_s3_bucket.zarr.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "zarr" {
  bucket = aws_s3_bucket.zarr.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "zarr" {
  bucket = aws_s3_bucket.zarr.id

  rule {
    id     = "transition-old-versions"
    status = "Enabled"

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_transition {
      noncurrent_days = 90
      storage_class   = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket" "cog" {
  bucket        = "${var.name}-cog-${random_id.suffix.hex}"
  force_destroy = false
  tags          = merge(var.tags, { Name = "${var.name}-cog" })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cog" {
  bucket = aws_s3_bucket.cog.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "cog" {
  bucket = aws_s3_bucket.cog.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cog" {
  bucket = aws_s3_bucket.cog.id

  rule {
    id     = "transition-old-versions"
    status = "Enabled"

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_transition {
      noncurrent_days = 90
      storage_class   = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket" "stac" {
  bucket        = "${var.name}-stac-${random_id.suffix.hex}"
  force_destroy = false
  tags          = merge(var.tags, { Name = "${var.name}-stac" })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "stac" {
  bucket = aws_s3_bucket.stac.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "stac" {
  bucket = aws_s3_bucket.stac.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "stac" {
  bucket = aws_s3_bucket.stac.id

  rule {
    id     = "transition-old-versions"
    status = "Enabled"

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_transition {
      noncurrent_days = 90
      storage_class   = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# OpenSearch (managed)
resource "aws_opensearch_domain" "stac" {
  domain_name    = "${var.name}-stac"
  engine_version = "OpenSearch_2.9"
  cluster_config {
    instance_type          = "t3.small.search"
    instance_count         = 2
    zone_awareness_enabled = true
  }
  ebs_options {
    ebs_enabled = true
    volume_size = 20
  }
  encrypt_at_rest {
    enabled = true
  }
  node_to_node_encryption {
    enabled = true
  }
  vpc_options {
    subnet_ids         = var.private_subnets
    security_group_ids = [var.vpc_sg_id]
  }
  access_policies  = data.aws_iam_policy_document.os_access.json
  advanced_options = { "rest.action.multi.allow_explicit_index" = "true" }
  tags             = merge(var.tags, { Name = "${var.name}-stac" })
}

data "aws_iam_policy_document" "os_access" {
  statement {
    actions = ["es:*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    resources = ["*"]
    condition {
      test     = "IpAddress"
      variable = "aws:SourceIp"
      values   = ["0.0.0.0/0"]
    }
  }
}

# ElastiCache Redis (cluster mode disabled)
resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "${var.name}-redis"
  engine               = "redis"
  engine_version       = "7.0"
  node_type            = "cache.t3.small"
  num_cache_nodes      = 1
  subnet_group_name    = aws_elasticache_subnet_group.redis.name
  security_group_ids   = [var.vpc_sg_id]
  parameter_group_name = "default.redis7"
  tags                 = merge(var.tags, { Name = "${var.name}-redis" })
}

resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.name}-redis-sg"
  subnet_ids = var.private_subnets
  tags       = merge(var.tags, { Name = "${var.name}-redis-subnet-group" })
}

# Optional RDS Postgres with PostGIS (if enable_rds)
resource "aws_db_instance" "postgis" {
  count                  = var.enable_rds ? 1 : 0
  allocated_storage      = var.rds_allocated_storage
  engine                 = "postgres"
  engine_version         = "15"
  instance_class         = "db.t3.medium"
  db_name                = "${var.name}_db"
  username               = var.db_username
  password               = var.db_password
  skip_final_snapshot    = true
  vpc_security_group_ids = [var.vpc_sg_id]
  db_subnet_group_name   = aws_db_subnet_group.db.name
  storage_encrypted      = true
  tags                   = merge(var.tags, { Name = "${var.name}-postgis" })
}

resource "aws_db_subnet_group" "db" {
  name       = "${var.name}-db-subnets"
  subnet_ids = var.private_subnets
  tags       = merge(var.tags, { Name = "${var.name}-db-subnet-group" })
}

output "s3_raw_bucket_id" { value = aws_s3_bucket.raw.bucket }
output "s3_zarr_bucket_id" { value = aws_s3_bucket.zarr.bucket }
output "s3_cog_bucket_id" { value = aws_s3_bucket.cog.bucket }
output "s3_stac_bucket_id" { value = aws_s3_bucket.stac.bucket }
output "opensearch_domain_endpoint" { value = aws_opensearch_domain.stac.endpoint }
output "redis_primary_endpoint_address" { value = aws_elasticache_cluster.redis.cache_nodes[0].address }