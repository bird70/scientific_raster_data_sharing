# STAC Migration Script

## Overview

The `migrate_stac_to_dynamodb.py` script migrates STAC items from OpenSearch to DynamoDB with comprehensive features for safe, resumable migrations.

## Features

- **Scroll API**: Efficiently reads all items from OpenSearch using scroll API
- **Batch Writing**: Writes items to DynamoDB in batches of 25 (optimal for DynamoDB)
- **Progress Logging**: Real-time progress updates and detailed logging
- **Error Tracking**: Continues on errors and generates comprehensive error report
- **Resume Capability**: Can skip already-migrated items to resume interrupted migrations
- **Dry Run Mode**: Validate migration without writing to DynamoDB
- **Migration Report**: Generates JSON report with statistics and error details

## Requirements

Install required Python packages:

```bash
pip install boto3 opensearch-py requests-aws4auth
```

## Usage

### Basic Migration

```bash
python scripts/migrate_stac_to_dynamodb.py \
  --opensearch-host search-domain.region.es.amazonaws.com \
  --dynamodb-table my-project-stac-items
```

### Dry Run (Validation)

Test the migration without writing to DynamoDB:

```bash
python scripts/migrate_stac_to_dynamodb.py \
  --opensearch-host search-domain.region.es.amazonaws.com \
  --dynamodb-table my-project-stac-items \
  --dry-run
```

### Resume Interrupted Migration

If a migration is interrupted, resume by skipping already-migrated items:

```bash
python scripts/migrate_stac_to_dynamodb.py \
  --opensearch-host search-domain.region.es.amazonaws.com \
  --dynamodb-table my-project-stac-items \
  --resume
```

### Using Environment Variables

```bash
export OPENSEARCH_HOST=search-domain.region.es.amazonaws.com
export DYNAMODB_STAC_TABLE=my-project-stac-items
export AWS_REGION=ap-southeast-2

python scripts/migrate_stac_to_dynamodb.py
```

## Command-Line Arguments

| Argument | Environment Variable | Default | Description |
|----------|---------------------|---------|-------------|
| `--opensearch-host` | `OPENSEARCH_HOST` | (required) | OpenSearch endpoint without https:// |
| `--opensearch-index` | `OPENSEARCH_INDEX` | `stac` | OpenSearch index name |
| `--dynamodb-table` | `DYNAMODB_STAC_TABLE` | (required) | DynamoDB table name |
| `--region` | `AWS_REGION` | `ap-southeast-2` | AWS region |
| `--dry-run` | - | `false` | Validate without writing |
| `--resume` | - | `false` | Skip already-migrated items |
| `--batch-size` | - | `25` | Items per batch write |
| `--no-opensearch-auth` | - | `false` | Disable AWS auth (for testing) |

## Output

The script generates two output files:

1. **Log File**: `migration_YYYYMMDD_HHMMSS.log`
   - Detailed logs of all operations
   - Error messages and stack traces
   - Progress updates

2. **Report File**: `migration_report_YYYYMMDD_HHMMSS.json`
   - Summary statistics (total read, written, skipped, errors)
   - Duration and throughput metrics
   - List of all errors with item IDs

## Migration Report Example

```json
{
  "summary": {
    "total_read": 1000,
    "total_written": 995,
    "total_skipped": 0,
    "total_errors": 5,
    "duration_seconds": 120.5,
    "items_per_second": 8.26
  },
  "errors": [
    {
      "item_id": "dataset-123",
      "error": "Missing required field: geometry",
      "timestamp": "2024-01-15T10:30:45.123456"
    }
  ]
}
```

## Migration Process

1. **Pre-Migration**
   - Run dry-run to validate: `--dry-run`
   - Review log output for any issues
   - Ensure DynamoDB table exists and has correct schema

2. **Migration**
   - Run full migration
   - Monitor progress in real-time
   - Script continues on individual item errors

3. **Post-Migration**
   - Review migration report
   - Verify item counts match
   - Spot-check random items for data integrity
   - If errors occurred, investigate and re-run for failed items

4. **Resume (if needed)**
   - If migration is interrupted, use `--resume` flag
   - Script will scan DynamoDB for existing items and skip them

## Error Handling

The script handles errors gracefully:

- **Individual Item Errors**: Logged and tracked, but migration continues
- **Batch Write Errors**: Entire batch fails, but script continues with next batch
- **Connection Errors**: Script will fail and can be resumed with `--resume`

## Performance

- **Throughput**: Typically 5-10 items/second depending on item size
- **Memory**: Minimal (processes items in batches)
- **Network**: Efficient use of scroll API and batch writes

## Troubleshooting

### "Missing required field" errors
- Some items in OpenSearch may be incomplete
- Review error report to identify problematic items
- Fix items in OpenSearch and re-run migration

### "Throttling" errors
- DynamoDB may throttle if write capacity is exceeded
- Script will retry with exponential backoff (boto3 default)
- Consider using provisioned capacity for large migrations

### "Connection timeout" errors
- Network issues or OpenSearch overload
- Use `--resume` to continue from where it left off

## AWS Permissions Required

### For OpenSearch (Source)
```json
{
  "Effect": "Allow",
  "Action": [
    "es:ESHttpGet",
    "es:ESHttpPost"
  ],
  "Resource": "arn:aws:es:region:account:domain/domain-name/*"
}
```

### For DynamoDB (Target)
```json
{
  "Effect": "Allow",
  "Action": [
    "dynamodb:PutItem",
    "dynamodb:BatchWriteItem",
    "dynamodb:Scan"
  ],
  "Resource": "arn:aws:dynamodb:region:account:table/table-name"
}
```

## Related Documentation

- [DynamoDB STAC Schema](../docs/DYNAMODB_STAC_SCHEMA.md)
- [Migration Guide](../docs/DYNAMODB_MIGRATION_GUIDE.md)
- [Architecture Documentation](../docs/ARCHITECTURE_ANALYSIS.md)
