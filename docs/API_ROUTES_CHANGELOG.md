# API Routes Changelog

This document captures all changes and additions made to the API routes in the Scientific Raster Data Sharing platform.

## Overview

The platform provides a FastAPI-based REST API for accessing scientific raster data through tiles and timeseries endpoints, with STAC catalog integration for data discovery.

## API Endpoints Summary

### Core Endpoints

| Endpoint | Method | Description | Module |
|----------|--------|-------------|---------|
| `/` | GET | Root endpoint with API information | main.py |
| `/health` | GET | Health check endpoint | main.py |
| `/docs` | GET | Interactive API documentation (Swagger UI) | FastAPI auto-generated |
| `/openapi.json` | GET | OpenAPI specification | FastAPI auto-generated |
| `/metrics` | GET | Prometheus metrics endpoint | metrics.py |

### Data Access Endpoints

| Endpoint | Method | Description | Module |
|----------|--------|-------------|---------|
| `/api/collections` | GET | List available STAC collections | main.py + stac_lookup.py |
| `/api/timeseries` | GET | Extract timeseries data for point location | timeseries.py |
| `/tiles/{collection}/{z}/{x}/{y}.png` | GET | Serve map tiles for visualization | tiles.py |

## Detailed Route Documentation

### 1. Root Endpoint (`/`)

**File**: `app/main.py`
**Added**: Initial implementation
**Purpose**: Provides API overview and endpoint discovery

```python
@app.get("/")
def root():
    return {
        "title": "Scientific Raster Data Platform",
        "description": "API for accessing scientific raster data",
        "version": "1.0.0",
        "endpoints": {
            "health": "/health",
            "docs": "/docs", 
            "metrics": "/metrics",
            "collections": "/api/collections",
            "timeseries": "/api/timeseries",
            "tiles": "/tiles/{collection}/{z}/{x}/{y}.png"
        }
    }
```

### 2. Collections Endpoint (`/api/collections`)

**File**: `app/main.py` (route) + `app/stac_lookup.py` (implementation)
**Added**: New endpoint for STAC collection discovery
**Purpose**: Returns list of available data collections from STAC catalog

#### Route Implementation:
```python
@app.get("/api/collections")
def get_collections():
    """Get available STAC collections"""
    try:
        collections = stac_search_collections()
        return {"collections": collections}
    except Exception as e:
        return {"collections": [], "error": str(e)}
```

#### Backend Function (`stac_lookup.py`):
```python
def stac_search_collections():
    """Get all available collections from STAC catalog"""
    try:
        body = {
            "aggs": {
                "collections": {
                    "terms": {
                        "field": "collection.keyword",
                        "size": 100
                    }
                }
            },
            "size": 0
        }
        res = client.search(index=settings.OPENSEARCH_INDEX, body=body)
        buckets = res.get("aggregations", {}).get("collections", {}).get("buckets", [])
        return [bucket["key"] for bucket in buckets]
    except Exception as e:
        logger.error(f"Error searching collections: {e}")
        return []
```

**Response Format**:
```json
{
    "collections": ["collection1", "collection2", "..."]
}
```

### 3. Timeseries Endpoint (`/api/timeseries`)

**File**: `app/timeseries.py`
**Added**: Complete implementation with Dask integration
**Purpose**: Extract timeseries data for specific point coordinates

#### Route Implementation:
```python
@router.get("/api/timeseries")
async def timeseries(lon: float = Query(...), lat: float = Query(...),
                     start: str = Query(...), end: str = Query(...),
                     variable: str = Query(...)):
```

#### Key Features Added:
- **STAC Integration**: Uses `stac_search_point()` to find relevant datasets
- **Dask Support**: Optional distributed computing with fallback to local processing
- **Caching**: Redis-based caching with TTL
- **Error Handling**: Comprehensive error handling and logging
- **Async Processing**: Concurrent processing of multiple data sources

#### Query Parameters:
- `lon`: Longitude coordinate (required)
- `lat`: Latitude coordinate (required) 
- `start`: Start datetime (ISO format, required)
- `end`: End datetime (ISO format, required)
- `variable`: Variable name to extract (required)

#### Response Format:
```json
{
    "times": ["2023-01-01T00:00:00", "2023-01-02T00:00:00"],
    "values": [15.2, 16.1]
}
```

#### Supporting Functions Added:
- `ensure_dask_client()`: Manages Dask client connection
- `_make_cache_key()`: Generates cache keys for Redis
- `open_zarr_mapper()`: Opens Zarr datasets from S3 with retry logic

### 4. Tiles Endpoint (`/tiles/{collection}/{z}/{x}/{y}.png`)

**File**: `app/tiles.py`
**Added**: Complete tile server implementation
**Purpose**: Serves map tiles for web mapping applications

#### Route Implementation:
```python
@router.get("/tiles/{collection}/{z}/{x}/{y}.png")
def get_tile(collection: str, z: int, x: int, y: int, resampling: str = Query("bilinear")):
```

#### Key Features Added:
- **STAC Integration**: Uses `lookup_cog_href()` to find COG assets
- **COG Support**: Reads Cloud Optimized GeoTIFFs via rio-tiler
- **Dynamic Rendering**: Generates PNG tiles with matplotlib
- **Resampling Options**: Configurable resampling methods
- **Error Handling**: Comprehensive error handling with HTTP status codes

#### Path Parameters:
- `collection`: STAC collection identifier
- `z`: Zoom level
- `x`: Tile X coordinate
- `y`: Tile Y coordinate

#### Query Parameters:
- `resampling`: Resampling method (default: "bilinear")

#### Supporting Functions Added:
```python
@retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=0.5))
def lookup_cog_href(collection: str) -> str:
    """Find COG asset URL for given collection"""
```

### 5. Health Check Endpoint (`/health`)

**File**: `app/main.py`
**Added**: Basic health check
**Purpose**: Service health monitoring

```python
@app.get("/health")
def health():
    return {"status": "ok"}
```

### 6. Metrics Endpoint (`/metrics`)

**File**: `app/metrics.py`
**Added**: Prometheus metrics integration
**Purpose**: Application monitoring and observability

## STAC Lookup Module Enhancements (`stac_lookup.py`)

### Functions Added:

1. **`make_client()`**: Creates OpenSearch client with retry logic
2. **`stac_search_point()`**: Searches STAC catalog for point-based queries
3. **`stac_search_collections()`**: Aggregates available collections

### Key Features:
- **Retry Logic**: All OpenSearch operations use tenacity for resilience
- **Geospatial Queries**: Support for geo_distance queries
- **Temporal Filtering**: Date range filtering capabilities
- **Error Handling**: Comprehensive logging and error management

## Configuration Changes

### Environment Variables Added:
- `OPENSEARCH_HOST`: OpenSearch cluster endpoint
- `OPENSEARCH_INDEX`: STAC catalog index name
- `DASK_SCHEDULER`: Optional Dask scheduler address
- `REDIS_URL`: Redis cache connection string

## Authentication Integration

All endpoints support Cognito JWT authentication via the `auth.py` middleware, though specific route protection can be configured as needed.

## Error Handling Strategy

### HTTP Status Codes:
- `200`: Success
- `404`: Collection/resource not found
- `422`: Invalid query parameters
- `500`: Internal server error

### Error Response Format:
```json
{
    "detail": "Error description",
    "error": "Additional error context"
}
```

## Caching Strategy

### Redis Integration:
- **Timeseries**: 10-minute TTL for point queries
- **Collections**: Could be cached with longer TTL
- **Cache Keys**: SHA256 hashed parameter combinations

## Performance Optimizations

1. **Async Processing**: Concurrent data loading in timeseries endpoint
2. **Dask Integration**: Optional distributed computing for large datasets
3. **Retry Logic**: Resilient external service calls
4. **Caching**: Redis-based response caching
5. **Streaming**: Efficient tile generation and delivery

## Ingestion Pipeline

### Overview
The platform includes an automated data ingestion pipeline that processes uploaded NetCDF files into analysis-ready formats.

**Documentation**: See `INGESTION_PIPELINE.md` for complete details.

### Pipeline Components:

1. **S3 Upload Trigger**: Lambda function detects new files in raw bucket
2. **Step Functions Orchestration**: Manages multi-step conversion workflow
3. **Zarr Conversion** (`app/ingestion/zarr_converter.py`): NetCDF → Zarr
4. **COG Generation** (`app/ingestion/cog_generator.py`): Zarr → Cloud Optimized GeoTIFF
5. **STAC Metadata Creation**: Extracts and structures metadata
6. **OpenSearch Indexing**: Makes data discoverable via API

### ECS Task Definitions:

| Task Definition | Module | Purpose |
|----------------|--------|----------|
| `zarr-conversion` | `app/ingestion/zarr_converter.py` | Convert NetCDF to Zarr format |
| `cog-generation` | `app/ingestion/cog_generator.py` | Generate Cloud Optimized GeoTIFFs |
| `stac-metadata` | `app/ingestion/stac_creator.py` | Create STAC metadata |
| `opensearch-indexer` | `app/ingestion/opensearch_indexer.py` | Index in STAC catalog |

### Workflow:
```
Upload NetCDF → Lambda → Step Functions → [Zarr Conversion] → [COG Generation] → [STAC Creation] → [OpenSearch Index]
```

### Terraform Resources:
- **Task Definitions**: `terraform/modules/ecs/main.tf` (zarr-conversion, cog-generation)
- **State Machine**: `terraform/modules/ingestion/main.tf`
- **IAM Permissions**: `terraform/modules/iam/main.tf` (Step Functions, ECS task roles)
- **Outputs**: `terraform/modules/ecs/outputs.tf` (task definition ARNs)

### Key IAM Permissions:
- **Step Functions**: `ecs:RunTask`, `iam:PassRole`, `events:PutTargets`
- **ECS Tasks**: S3 read/write, OpenSearch indexing

### Monitoring:
```bash
# View conversion logs
aws logs tail /ecs/zarr-conversion --follow
aws logs tail /ecs/cog-generation --follow

# Check Step Functions execution
aws stepfunctions describe-execution --execution-arn <arn>
```

## Future Enhancements

### Planned Additions:
- Polygon-based timeseries extraction
- Batch processing endpoints
- WebSocket support for real-time data
- Advanced filtering and aggregation options
- Rate limiting and quota management
- Parallel ingestion for large files
- Automatic retry and dead letter queues

## Testing Coverage

All endpoints include:
- Unit tests for core functionality
- Integration tests for external dependencies
- Error condition testing
- Performance benchmarking

## Monitoring and Observability

- **Structured Logging**: All operations logged with context
- **Metrics**: Prometheus metrics for request rates, latencies, errors
- **Tracing**: OpenTelemetry integration for distributed tracing
- **Health Checks**: Comprehensive service health monitoring