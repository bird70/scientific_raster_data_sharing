# DynamoDB STAC Schema Documentation

## Overview

This document describes the DynamoDB table schema used for storing STAC (SpatioTemporal Asset Catalog) metadata. The schema is optimized for common query patterns while maintaining compatibility with the STAC specification.

**Table Name:** `{project_name}-stac-items`

**Billing Mode:** On-demand (pay per request)

**Key Features:**
- Single-table design for all STAC items
- Global Secondary Indexes (GSI) for efficient queries
- Point-in-time recovery enabled
- Server-side encryption enabled

---

## Table Structure

### Primary Key

**Partition Key:** `id` (String)
- The unique identifier for each STAC item
- Format: Typically `{dataset-name}-{date}` (e.g., `sst-daily-2024-01-01`)
- Used for direct item lookups via GetItem operation

**Sort Key:** None
- Single-item access pattern doesn't require a sort key

### Attributes

All STAC items stored in DynamoDB contain the following attributes:

| Attribute | Type | Required | Description | Example |
|-----------|------|----------|-------------|---------|
| `id` | String | Yes | Unique STAC item identifier | `"sst-daily-2024-01-01"` |
| `type` | String | Yes | Always "Feature" for STAC items | `"Feature"` |
| `geometry` | Map | Yes | GeoJSON geometry object | `{"type": "Polygon", "coordinates": [...]}` |
| `bbox` | List | Yes | Bounding box [minx, miny, maxx, maxy] | `[150.0, -35.0, 151.0, -34.0]` |
| `properties` | Map | Yes | STAC properties (datetime, title, etc.) | `{"datetime": "2024-01-01T00:00:00Z", ...}` |
| `assets` | Map | Yes | Asset links (zarr, cog, etc.) | `{"zarr": {...}, "cog": {...}}` |
| `collection` | String | Yes | Collection name (for GSI) | `"sst-daily"` |
| `datetime` | String | Yes | ISO 8601 datetime (for GSI) | `"2024-01-01T00:00:00Z"` |
| `stac_version` | String | No | STAC specification version | `"1.0.0"` |
| `stac_extensions` | List | No | STAC extensions used | `[]` |
| `links` | List | No | STAC links (self, collection, etc.) | `[{"rel": "self", "href": "..."}]` |

---

## Global Secondary Indexes (GSI)

### 1. collection-index

**Purpose:** Query STAC items by collection, optionally filtered by datetime

**Keys:**
- **Partition Key:** `collection` (String)
- **Sort Key:** `datetime` (String)

**Projection:** ALL (all attributes included)

**Use Cases:**
- Get all items in a collection
- Get items in a collection within a date range
- List items in a collection sorted by time

**Example Queries:**
```python
# Get all items in a collection
response = table.query(
    IndexName='collection-index',
    KeyConditionExpression='collection = :coll',
    ExpressionAttributeValues={':coll': 'sst-daily'}
)

# Get items in a collection within date range
response = table.query(
    IndexName='collection-index',
    KeyConditionExpression='collection = :coll AND datetime BETWEEN :start AND :end',
    ExpressionAttributeValues={
        ':coll': 'sst-daily',
        ':start': '2024-01-01T00:00:00Z',
        ':end': '2024-01-31T23:59:59Z'
    }
)
```

### 2. datetime-index

**Purpose:** Query STAC items by datetime across all collections

**Keys:**
- **Partition Key:** `datetime` (String) - Date only (YYYY-MM-DD)
- **Sort Key:** `id` (String)

**Projection:** ALL (all attributes included)

**Use Cases:**
- Get all items for a specific date
- Get items across date range (requires multiple queries)
- Temporal analysis across collections

**Example Queries:**
```python
# Get all items for a specific date
response = table.query(
    IndexName='datetime-index',
    KeyConditionExpression='datetime = :date',
    ExpressionAttributeValues={':date': '2024-01-01T00:00:00Z'}
)

# Note: For date ranges, query collection-index instead
```

---

## Query Patterns

### Pattern 1: Get Item by ID

**Use Case:** Retrieve a specific STAC item

**Operation:** GetItem

**Performance:** ~5-10ms (p95)

**Cost:** 0.5 RCU per item (4KB or less)

**Example:**
```python
from boto3.dynamodb.conditions import Key

response = table.get_item(
    Key={'id': 'sst-daily-2024-01-01'}
)
item = response.get('Item')
```

**DynamoDB CLI:**
```bash
aws dynamodb get-item \
  --table-name project-stac-items \
  --key '{"id": {"S": "sst-daily-2024-01-01"}}'
```

---

### Pattern 2: Query by Collection

**Use Case:** Get all items in a collection

**Operation:** Query on collection-index

**Performance:** ~20-50ms (p95) for 100 items

**Cost:** 0.5 RCU per 4KB of data returned

**Example:**
```python
response = table.query(
    IndexName='collection-index',
    KeyConditionExpression='collection = :coll',
    ExpressionAttributeValues={':coll': 'sst-daily'},
    Limit=100
)
items = response['Items']
```

**DynamoDB CLI:**
```bash
aws dynamodb query \
  --table-name project-stac-items \
  --index-name collection-index \
  --key-condition-expression "collection = :coll" \
  --expression-attribute-values '{":coll": {"S": "sst-daily"}}' \
  --limit 100
```

---

### Pattern 3: Query by Collection and Date Range

**Use Case:** Get items in a collection within a time period

**Operation:** Query on collection-index with range condition

**Performance:** ~30-80ms (p95) for 100 items

**Cost:** 0.5 RCU per 4KB of data returned

**Example:**
```python
response = table.query(
    IndexName='collection-index',
    KeyConditionExpression='collection = :coll AND datetime BETWEEN :start AND :end',
    ExpressionAttributeValues={
        ':coll': 'sst-daily',
        ':start': '2024-01-01T00:00:00Z',
        ':end': '2024-01-31T23:59:59Z'
    },
    Limit=100
)
items = response['Items']
```

**DynamoDB CLI:**
```bash
aws dynamodb query \
  --table-name project-stac-items \
  --index-name collection-index \
  --key-condition-expression "collection = :coll AND datetime BETWEEN :start AND :end" \
  --expression-attribute-values '{
    ":coll": {"S": "sst-daily"},
    ":start": {"S": "2024-01-01T00:00:00Z"},
    ":end": {"S": "2024-01-31T23:59:59Z"}
  }' \
  --limit 100
```

---

### Pattern 4: Query by Bounding Box

**Use Case:** Get items that intersect with a geographic area

**Operation:** Scan with filter expression (less efficient)

**Performance:** ~100-500ms (p95) depending on table size

**Cost:** 0.5 RCU per 4KB scanned (not just returned)

**Note:** This is the least efficient query pattern. Consider adding a geohash attribute for better performance.

**Example:**
```python
def bbox_intersects(item_bbox, query_bbox):
    """Check if bounding boxes intersect"""
    return not (
        item_bbox[2] < query_bbox[0] or  # item east of query
        item_bbox[0] > query_bbox[2] or  # item west of query
        item_bbox[3] < query_bbox[1] or  # item south of query
        item_bbox[1] > query_bbox[3]     # item north of query
    )

# Scan and filter in application code
response = table.scan()
query_bbox = [150.0, -35.0, 151.0, -34.0]
items = [
    item for item in response['Items']
    if bbox_intersects(item['bbox'], query_bbox)
]
```

**Optimization:** For better performance, consider:
1. Adding a geohash attribute and GSI
2. Pre-filtering by collection or datetime to reduce scan size
3. Using DynamoDB Streams to maintain a spatial index

---

### Pattern 5: List All Collections

**Use Case:** Get unique collection names

**Operation:** Scan with projection

**Performance:** ~50-200ms (p95)

**Cost:** 0.5 RCU per 4KB scanned

**Example:**
```python
response = table.scan(
    ProjectionExpression='collection'
)
collections = set(item['collection'] for item in response['Items'])
```

**Optimization:** Consider maintaining a separate collections table or caching this result.

---

### Pattern 6: Pagination

**Use Case:** Retrieve large result sets in chunks

**Operation:** Query or Scan with LastEvaluatedKey

**Example:**
```python
def paginate_collection(collection_name, page_size=100):
    """Paginate through all items in a collection"""
    last_key = None
    
    while True:
        if last_key:
            response = table.query(
                IndexName='collection-index',
                KeyConditionExpression='collection = :coll',
                ExpressionAttributeValues={':coll': collection_name},
                Limit=page_size,
                ExclusiveStartKey=last_key
            )
        else:
            response = table.query(
                IndexName='collection-index',
                KeyConditionExpression='collection = :coll',
                ExpressionAttributeValues={':coll': collection_name},
                Limit=page_size
            )
        
        yield response['Items']
        
        last_key = response.get('LastEvaluatedKey')
        if not last_key:
            break
```

---

## Example STAC Item

Here's a complete example of a STAC item as stored in DynamoDB:

```json
{
  "id": "sst-daily-2024-01-01",
  "type": "Feature",
  "geometry": {
    "type": "Polygon",
    "coordinates": [
      [
        [150.0, -35.0],
        [151.0, -35.0],
        [151.0, -34.0],
        [150.0, -34.0],
        [150.0, -35.0]
      ]
    ]
  },
  "bbox": [150.0, -35.0, 151.0, -34.0],
  "properties": {
    "datetime": "2024-01-01T00:00:00Z",
    "title": "Sea Surface Temperature - Daily Mean",
    "description": "Daily mean sea surface temperature from satellite observations",
    "platform": "Sentinel-3",
    "instruments": ["SLSTR"],
    "gsd": 1000,
    "created": "2024-01-02T10:30:00Z",
    "updated": "2024-01-02T10:30:00Z"
  },
  "assets": {
    "zarr": {
      "href": "s3://project-data/zarr/sst-daily-2024-01-01.zarr",
      "type": "application/vnd+zarr",
      "roles": ["data"],
      "title": "Zarr data store"
    },
    "cog": {
      "href": "s3://project-data/cog/sst-daily-2024-01-01.tif",
      "type": "image/tiff; application=geotiff; profile=cloud-optimized",
      "roles": ["visual"],
      "title": "Cloud-Optimized GeoTIFF"
    },
    "thumbnail": {
      "href": "s3://project-data/thumbnails/sst-daily-2024-01-01.png",
      "type": "image/png",
      "roles": ["thumbnail"],
      "title": "Thumbnail image"
    }
  },
  "collection": "sst-daily",
  "datetime": "2024-01-01T00:00:00Z",
  "stac_version": "1.0.0",
  "stac_extensions": [],
  "links": [
    {
      "rel": "self",
      "href": "https://api.example.com/stac/items/sst-daily-2024-01-01"
    },
    {
      "rel": "collection",
      "href": "https://api.example.com/stac/collections/sst-daily"
    }
  ]
}
```

---

## Data Types and Limits

### DynamoDB Limits

- **Item Size:** Maximum 400 KB per item
- **Attribute Name:** Maximum 64 KB (UTF-8)
- **String Attribute:** Maximum 400 KB
- **Number Precision:** 38 digits
- **Nested Depth:** Maximum 32 levels

### STAC Item Considerations

Most STAC items are well under the 400 KB limit. Typical sizes:
- **Minimal Item:** ~2-5 KB
- **Standard Item:** ~10-20 KB
- **Complex Item:** ~50-100 KB

If items exceed limits:
- Store large assets metadata in S3, reference by URL
- Compress nested structures
- Split large items into multiple records

---

## Cost Optimization Tips

### 1. Use GetItem Instead of Query

When you know the exact item ID, use GetItem:
```python
# Efficient (0.5 RCU)
response = table.get_item(Key={'id': item_id})

# Less efficient (scans multiple items)
response = table.query(
    KeyConditionExpression='id = :id',
    ExpressionAttributeValues={':id': item_id}
)
```

### 2. Use Projection Expressions

Only retrieve attributes you need:
```python
# Retrieve only specific fields
response = table.query(
    IndexName='collection-index',
    KeyConditionExpression='collection = :coll',
    ExpressionAttributeValues={':coll': 'sst-daily'},
    ProjectionExpression='id, datetime, bbox'
)
```

### 3. Limit Result Sets

Always use Limit to control costs:
```python
response = table.query(
    IndexName='collection-index',
    KeyConditionExpression='collection = :coll',
    ExpressionAttributeValues={':coll': 'sst-daily'},
    Limit=100  # Limit results
)
```

### 4. Cache Frequently Accessed Items

Use Redis or application-level caching:
```python
# Check cache first
cached_item = redis.get(f"stac:{item_id}")
if cached_item:
    return json.loads(cached_item)

# Query DynamoDB if not cached
response = table.get_item(Key={'id': item_id})
item = response.get('Item')

# Cache for 1 hour
redis.setex(f"stac:{item_id}", 3600, json.dumps(item))
return item
```

### 5. Avoid Scans

Scans are expensive. Use Query with GSI instead:
```python
# Expensive: Scan entire table
response = table.scan(
    FilterExpression='collection = :coll',
    ExpressionAttributeValues={':coll': 'sst-daily'}
)

# Efficient: Query GSI
response = table.query(
    IndexName='collection-index',
    KeyConditionExpression='collection = :coll',
    ExpressionAttributeValues={':coll': 'sst-daily'}
)
```

### 6. Use On-Demand Billing

For unpredictable workloads, on-demand billing is more cost-effective:
- No capacity planning required
- Pay only for what you use
- Automatically scales to workload

For predictable workloads, consider provisioned capacity with auto-scaling.

### 7. Monitor and Optimize

Use CloudWatch to track:
- Read/Write capacity units consumed
- Throttled requests
- Query patterns

Optimize based on actual usage patterns.

---

## Monitoring and Metrics

### Key Metrics to Track

1. **ConsumedReadCapacityUnits**
   - Track read costs
   - Identify hot partitions
   - Optimize query patterns

2. **ConsumedWriteCapacityUnits**
   - Track write costs
   - Monitor ingestion rate
   - Plan capacity

3. **ThrottledRequests**
   - Should be 0 for on-demand
   - Indicates capacity issues for provisioned

4. **UserErrors**
   - Track validation errors
   - Identify application issues

5. **SystemErrors**
   - Track DynamoDB service issues
   - Monitor availability

### CloudWatch Alarms

Set up alarms for:
- Throttled requests > 0
- User errors > threshold
- Read latency > 50ms (p95)
- Write latency > 50ms (p95)

### Example CloudWatch Query

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name ConsumedReadCapacityUnits \
  --dimensions Name=TableName,Value=project-stac-items \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-02T00:00:00Z \
  --period 3600 \
  --statistics Sum
```

---

## Backup and Recovery

### Point-in-Time Recovery (PITR)

PITR is enabled for the STAC table:
- Continuous backups for 35 days
- Restore to any point in time
- No performance impact

**Restore Example:**
```bash
aws dynamodb restore-table-to-point-in-time \
  --source-table-name project-stac-items \
  --target-table-name project-stac-items-restored \
  --restore-date-time 2024-01-01T12:00:00Z
```

### On-Demand Backups

Create manual backups for long-term retention:
```bash
aws dynamodb create-backup \
  --table-name project-stac-items \
  --backup-name stac-backup-2024-01-01
```

### Export to S3

Export table data to S3 for analysis:
```bash
aws dynamodb export-table-to-point-in-time \
  --table-arn arn:aws:dynamodb:region:account:table/project-stac-items \
  --s3-bucket project-backups \
  --s3-prefix dynamodb-exports/ \
  --export-format DYNAMODB_JSON
```

---

## Migration from OpenSearch

See `docs/DYNAMODB_MIGRATION_GUIDE.md` for detailed migration instructions.

**Key Differences:**

| Feature | OpenSearch | DynamoDB |
|---------|-----------|----------|
| Query Language | DSL (JSON) | KeyConditionExpression |
| Full-Text Search | Yes | No (use OpenSearch for this) |
| Geospatial Queries | Native support | Manual filtering required |
| Cost | ~$100/month | ~$5-10/month |
| Latency | 20-100ms | 5-20ms |
| Scaling | Manual | Automatic |
| Maintenance | Cluster management | Fully managed |

---

## Best Practices

1. **Design for Access Patterns**
   - Identify query patterns before schema design
   - Create GSIs for common queries
   - Avoid Scan operations

2. **Use Consistent Naming**
   - Use lowercase for attribute names
   - Use underscores for multi-word names
   - Follow STAC specification conventions

3. **Validate Data Before Writing**
   - Ensure required fields are present
   - Validate data types
   - Check for size limits

4. **Handle Errors Gracefully**
   - Implement retry logic with exponential backoff
   - Log errors for debugging
   - Monitor error rates

5. **Test Query Performance**
   - Load test with realistic data volumes
   - Measure latency at different scales
   - Optimize based on results

6. **Document Schema Changes**
   - Version your schema
   - Document migration procedures
   - Test changes in staging first

---

## Additional Resources

- **AWS DynamoDB Best Practices**: https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/best-practices.html
- **STAC Specification**: https://stacspec.org/
- **DynamoDB Data Modeling**: https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/data-modeling.html
- **boto3 DynamoDB Documentation**: https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/dynamodb.html

---

## Changelog

- **2024-01-01**: Initial schema design
- **2024-01-15**: Added collection-index and datetime-index GSIs
- **2024-02-01**: Enabled point-in-time recovery
- **2024-03-01**: Migrated from OpenSearch to DynamoDB
