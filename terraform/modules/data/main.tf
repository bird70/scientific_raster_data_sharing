esource "aws_s3_bucket" "raw" {
  bucket = "${var.name}-raw-${random_id.suffix.hex}"
  force_destroy = false
  server_side_encryption_configuration { rule { apply_server_side_encryption_by_default { sse_algorithm = "AES256" } } }
  versioning { enabled = true }
  tags = { Name = "${var.name}-raw" }
}

resource "aws_s3_bucket" "zarr" {
  bucket = "${var.name}-zarr-${random_id.suffix.hex}"
  force_destroy = false
  server_side_encryption_configuration { rule { apply_server_side_encryption_by_default { sse_algorithm = "AES256" } } }
  versioning { enabled = true }
  tags = { Name = "${var.name}-zarr" }
}

resource "aws_s3_bucket" "cog" {
  bucket = "${var.name}-cog-${random_id.suffix.hex}"
  force_destroy = false
  server_side_encryption_configuration { rule { apply_server_side_encryption_by_default { sse_algorithm = "AES256" } } }
  versioning { enabled = true }
  tags = { Name = "${var.name}-cog" }
}

resource "aws_s3_bucket" "stac" {
  bucket = "${var.name}-stac-${random_id.suffix.hex}"
  force_destroy = false
  server_side_encryption_configuration { rule { apply_server_side_encryption_by_default { sse_algorithm = "AES256" } } }
  versioning { enabled = true }
  tags = { Name = "${var.name}-stac" }
}

resource "random_id" "suffix" {
  byte_length = 4
}

# OpenSearch (managed)
resource "aws_opensearch_domain" "stac" {
  domain_name = "${var.name}-stac"
  engine_version = "OpenSearch_2.8"
  cluster_config {
    instance_type = "t3.small.search"
    instance_count = 2
    zone_awareness_enabled = true
  }
  ebs_options { ebs_enabled = true, volume_size = 20 }
  vpc_options {
    subnet_ids = var.private_subnets
    security_group_ids = [var.vpc_sg_id]
  }
  access_policies = data.aws_iam_policy_document.os_access.json
  advanced_options = { "rest.action.multi.allow_explicit_index" = "true" }
}

data "aws_iam_policy_document" "os_access" {
  statement {
    actions = ["es:*"]
    principals { type = "AWS", identifiers = ["*"] }
    resources = ["*"]
    condition { test = "IpAddress", variable = "aws:SourceIp", values = ["0.0.0.0/0"] }
  }
}

# ElastiCache Redis (cluster mode disabled)
resource "aws_elasticache_cluster" "redis" {
  cluster_id = "${var.name}-redis"
  engine = "redis"
  node_type = "cache.t3.small"
  num_cache_nodes = 1
  subnet_group_name = aws_elasticache_subnet_group.redis.name
  security_group_ids = [var.vpc_sg_id]
}

resource "aws_elasticache_subnet_group" "redis" {
  name = "${var.name}-redis-sg"
  subnet_ids = var.private_subnets
}

# Optional RDS Postgres with PostGIS (if enable_rds)
resource "aws_db_instance" "postgis" {
  count = var.enable_rds ? 1 : 0
  allocated_storage = var.rds_allocated_storage
  engine = "postgres"
  engine_version = "15"
  instance_class = "db.t3.medium"
  name = "${var.name}_db"
  username = var.db_username
  password = var.db_password
  skip_final_snapshot = true
  vpc_security_group_ids = [var.vpc_sg_id]
  db_subnet_group_name = aws_db_subnet_group.db.name
}

resource "aws_db_subnet_group" "db" {
  name = "${var.name}-db-subnets"
  subnet_ids = var.private_subnets
}

output "s3_raw_bucket_id" { value = aws_s3_bucket.raw.bucket }
output "s3_zarr_bucket_id" { value = aws_s3_bucket.zarr.bucket }
output "s3_cog_bucket_id" { value = aws_s3_bucket.cog.bucket }
output "s3_stac_bucket_id" { value = aws_s3_bucket.stac.bucket }
output "opensearch_domain_endpoint" { value = aws_opensearch_domain.stac.endpoint }
output "redis_primary_endpoint_address" { value = aws_elasticache_cluster.redis.cache_nodes[0].address }