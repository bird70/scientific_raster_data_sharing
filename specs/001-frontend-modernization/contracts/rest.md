# API Contracts (REST)

All endpoints require `Authorization: Bearer <JWT>` (Cognito). Errors return `{ "error": { "code": string, "message": string, "details"?: any } }` with appropriate HTTP status.

## STAC Search
- **Endpoint**: `POST /api/v1/stac/search`
- **Request (JSON)**:
  ```json
  {
    "keywords": "temperature",
    "bbox": [minLon, minLat, maxLon, maxLat],
    "datetime": "start/end",            // ISO8601 range; "../2024-12-31" etc.
    "collections": ["collection-id"],
    "variables": ["temperature", "precipitation"],
    "limit": 20,
    "page": 1
  }
  ```
- **Response 200**:
  ```json
  {
    "items": [
      {
        "id": "dataset-123",
        "title": "Sea Surface Temperature",
        "description": "...",
        "bbox": [..],
        "temporalExtent": {"start": "2024-01-01", "end": "2024-06-30"},
        "variables": [{"name": "temperature", "units": "K", "assetKey": "temp"}],
        "assets": {"temp": "s3://..."},
        "thumbnailUrl": "https://.../thumb.png",
        "collectionId": "collection-1"
      }
    ],
    "page": 1,
    "pageSize": 20,
    "hasMore": true
  }
  ```
- **Errors**: `400` invalid filters, `401` unauthorized, `500` server error.

## Tiles (COG)
- **Endpoint**: `GET /tiles/{collectionId}/{z}/{x}/{y}.png?asset={assetKey}`
- **Query**: `asset` required for variable/asset selection.
- **Response 200**: PNG/WebP tile image.
- **Headers**: Cache-Control, ETag recommended.
- **Errors**: `400` invalid params, `401`, `404` missing tile, `500` server error.

## Timeseries
- **Endpoint**: `POST /api/v1/timeseries`
- **Request (JSON)**:
  ```json
  {
    "lon": 151.0,
    "lat": -33.0,
    "start": "2024-01-01",
    "end": "2024-12-31",
    "variables": ["temperature"],
    "datasetIds": ["dataset-123"]
  }
  ```
- **Response 200**:
  ```json
  {
    "series": [
      {
        "datasetId": "dataset-123",
        "variable": "temperature",
        "units": "K",
        "times": ["2024-01-01T00:00:00Z", "2024-01-02T00:00:00Z"],
        "values": [290.1, 289.5]
      }
    ]
  }
  ```
- **Errors**: `400` invalid inputs, `401`, `404` dataset/variable not found, `429` throttled, `500` server error.

## Common Error Model
- **Response**:
  ```json
  {
    "error": {
      "code": "INVALID_INPUT",
      "message": "bbox is required",
      "details": {}
    }
  }
  ```

## Non-Functional Requirements
- All requests must include `Authorization` header.
- Frontend must honor CORS and use HTTPS.
- Rate limiting/backoff: on `429`, show retry guidance and exponential backoff client-side.
- Timeouts: client should timeout requests after 10s and surface user-friendly errors.
