# Data Module

This module creates data storage and search infrastructure including S3 buckets, OpenSearch domain, and ElastiCache Redis cluster for the Raster Time-series Access Web Service.

## Components

### S3 Buckets

Four S3 buckets are created for different data types:

1. **Raw Bucket** (`{name}-raw-{suffix}`)
   - Stores uploaded NetCDF files
   - Triggers ingestion pipeline on upload
   - Lifecycle: Transitions old versions to IA/Glacier

2. **Zarr Bucket** (`{name}-zarr-{suffix}`)
   - Stores converted Zarr array data
   - Optimized for chunked cloud access
   - Used by timeseries API

3. **COG Bucket** (`{name}-cog-{suffix}`)
   - Stores Cloud-Optimized GeoTIFF files
   - Optimized for partial reads
   - Used by tiles API

4. **STAC Bucket** (`{name}-stac-{suffix}`)
   - Stores STAC item JSON metadata
   - Indexed in OpenSearch
   - Provides dataset catalog

All buckets have:
- Server-side encryption (AES-256)
- Versioning enabled
- Lifecycle policies for cost optimization
- Automatic multipart upload cleanup

### OpenSearch Domain

Managed OpenSearch cluster for STAC metadata search:
- **Engine**: OpenSearch 2.8
- **Instance Type**: t3.small.search
- **Instance Count**: 2 (multi-AZ)
- **Storage**: 20GB EBS per node
- **Encryption**: At rest and in transit
- **VPC**: Deployed in private subnets

### ElastiCache Redis

Redis cluster for API response caching:
- **Engine**: Redis 7.0
- **Node Type**: cache.t3.small
- **Nodes**: 1 (can be scaled)
- **Encryption**: In transit enabled
- **VPC**: Deployed in private subnets

### Optional RDS PostgreSQL

Optional PostgreSQL database with PostGIS extension:
- **Engine**: PostgreSQL 15
- **Instance Class**: db.t3.medium
- **Storage**: Configurable (default 100GB)
- **Encryption**: Storage encryption enabled
- **VPC**: Deployed in private subnets

## Usage

```hcl
module "data" {
  source = "./modules/data"
  
  name                  = "raster-platform"
  vpc_sg_id             = module.network.data_security_group_id
  private_subnets       = module.network.private_subnet_ids
  enable_rds            = false
  rds_allocated_storage = 100
  
  tags = {
    project_owner = "platform-team"
    project_title = "raster-platform"
    environment   = "production"
  }
}
```

## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name prefix for resources | string | - | yes |
| private_subnets | Private subnet IDs for data services | list(string) | - | yes |
| vpc_sg_id | Security group ID for data services | string | - | yes |
| db_username | RDS database username | string | stac | no |
| db_password | RDS database password | string | changeMe123! | no |
| enable_rds | Enable RDS PostgreSQL instance | bool | false | no |
| rds_allocated_storage | RDS storage size in GB | number | 100 | no |
| tags | Common tags to apply to all resources | map(string) | {} | no |

## Outputs

| Name | Description |
|------|-------------|
| s3_raw_bucket_id | Name of the raw S3 bucket |
| s3_zarr_bucket_id | Name of the Zarr S3 bucket |
| s3_cog_bucket_id | Name of the COG S3 bucket |
| s3_stac_bucket_id | Name of the STAC S3 bucket |
| opensearch_domain_endpoint | Endpoint of the OpenSearch domain |
| redis_primary_endpoint_address | Primary endpoint address of Redis cluster |

## S3 Lifecycle Policies

All buckets implement lifecycle policies to optimize costs:

### Noncurrent Version Transitions
- After 30 days: Move to Standard-IA
- After 90 days: Move to Glacier
- After 365 days: Delete

### Multipart Upload Cleanup
- Abort incomplete uploads after 7 days

## Security Features

### S3 Bucket Security
- Server-side encryption (SSE-S3) enabled by default
- Versioning enabled for data protection
- No public access (private buckets only)
- Access controlled via IAM policies

### OpenSearch Security
- VPC deployment (no public endpoint)
- Encryption at rest enabled
- Node-to-node encryption enabled
- Access controlled via security groups and IAM

### Redis Security
- VPC deployment (no public endpoint)
- Transit encryption enabled
- Access controlled via security groups
- No authentication required (VPC-secured)

## Cost Optimization

### S3 Storage Classes
Lifecycle policies automatically transition data to cheaper storage:
- Standard (0-30 days): Frequent access
- Standard-IA (30-90 days): Infrequent access
- Glacier (90+ days): Archive storage

### OpenSearch Sizing
- t3.small.search instances for development
- Scale to larger instances for production
- 2-node cluster provides high availability

### Redis Sizing
- cache.t3.small for development
- Single node reduces costs
- Scale to cluster mode for production

## Requirements

- Requirements 6.4: S3 encryption and versioning
- Requirements 9.3: Data module variable definitions
- Requirements 9.6: Resource tagging
