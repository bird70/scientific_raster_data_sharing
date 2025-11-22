# EARS (kiro.dev-style) Requirements — Raster Time-series Access Web Service

## Project: Raster Time-series Access Web Service (AWS)

Stakeholders:
- Data owners
- External users (researchers)
- Platform operators
- Security & compliance

Context: Provide performant web/API access to large raster datasets (NetCDF converted to Zarr and COG), including interactive map tiles and point-based timeseries extraction aggregated across overlapping datasets. Hosted in AWS (ap-southeast-2).

EARS-format Requirements (Easy Approach to Requirements Syntax)

1) WHEN a new NetCDF file is uploaded to the ingestion S3 prefix, the system SHALL convert it to chunked Zarr and generate a Cloud-Optimized GeoTIFF (COG) with overviews, and SHALL create a STAC item for the dataset and index it in the STAC search service.
- Acceptance Criteria:
  - Conversion produces Zarr store with expected variables/dimensions.
  - COG pyramids are generated for zoom levels appropriate to the dataset.
  - STAC item includes bbox, datetime extent, assets (zarr, cog), and variable metadata.
  - OpenSearch index contains the item and is queryable.

2) WHEN a user requests a map tile at /tiles/{collection}/{z}/{x}/{y}.png, the service SHALL return a PNG tile rendered from the dataset's COG, honoring nodata and palette rules, with caching headers suitable for CDN.
- Acceptance Criteria:
  - Cached tile median latency < 150ms for target region.
  - Non-cached tile server-side generation latency < 800ms under typical load.
  - Correct nodata handling and color scaling.

3) WHEN a user requests /api/timeseries with lon/lat/time-range/variable, the service SHALL return a time-ordered JSON timeseries aggregated across all overlapping datasets covering the time-range.
- Acceptance Criteria:
  - Returned timestamps correspond to dataset times.
  - Numerical values match ground-truth extraction within tolerance.
  - Cache hits return <500ms; common queries <2s.

4) WHEN traffic increases, the system SHALL autoscale services and compute (Dask) to maintain 95th percentile latencies within targets.
- Acceptance Criteria:
  - Autoscaling triggers under load tests (e.g., 500 concurrent tile requests).
  - Metrics show sustained latency under thresholds with scaled capacity.

5) WHEN data is ingested, the system SHALL preserve raw NetCDF and generated artifacts, include version metadata in STAC, and support querying historic versions.
- Acceptance Criteria:
  - STAC items reference versioned S3 paths.
  - Consumers can request previous versions via STAC properties.

6) WHEN users access APIs, the system SHALL enforce authentication and authorization via Cognito/OIDC and return 401/403 for unauthorized requests.
- Acceptance Criteria:
  - Unauthorized requests blocked.
  - Role-based dataset access enforced per STAC properties.

Operational & Non-functional Requirements (short)
- Observability: logs, traces, metrics, dashboards.
- Security: S3 encryption, least-privilege IAM, WAF, VPC endpoints.
- Cost control: lifecycle rules, spot for batch conversion, autoscale limits.

Developer Tasks (high-level)
- Build ingestion conversion service (NetCDF→Zarr+COG), STAC creation, indexer.
- Implement tile server (rio-tiler + COG serving) with CDN.
- Implement timeseries API (xarray/zarr + Dask), STAC lookup, caching.
- Provide Terraform, CI/CD, observability, monitoring, and runbooks.

Runbook (summary)
- Deploy change: update container, push to ECR, update task definition, run smoke tests, validate STAC queries, sample timeseries.
- Troubleshoot: verify CloudFront cache, ALB target health, Dask worker status, Redis hit rates, OpenSearch errors.
