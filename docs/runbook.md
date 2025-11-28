# Runbook — Raster Time-series Access Service

## Quick Actions

### Deploy New Image
1. Build image: `docker build -t <repo>:<tag> .`
2. Push to ECR and update ECS task definition (or use CI pipeline)
3. Deploy via Terraform apply (if infra changes) or update service via AWS console/CLI

### Validate After Deploy
- `/health` endpoint returns 200
- Check CloudWatch logs for errors
- Verify metrics in CloudWatch dashboard

### Ingestion Pipeline Operations
- **Monitor Pipeline**: `./scripts/monitor-ingestion-pipeline.sh`
- **Check Status**: See [ECS Zarr Migration Runbook](ECS_ZARR_MIGRATION_RUNBOOK.md)
- **Troubleshoot Issues**: See [Troubleshooting Guide](ECS_ZARR_MIGRATION_RUNBOOK.md#troubleshooting-guide)

## CRS Detection and Coordinate Transformation

### Overview
The ingestion pipeline automatically detects and transforms projected coordinate reference systems (CRS) to WGS84 for proper spatial indexing.

### Supported Projection Systems
- **Geographic CRS**: WGS84 (EPSG:4326), any lat/lon system
- **Projected CRS**: 
  - NZTM2000 (EPSG:2193) - New Zealand Transverse Mercator
  - UTM zones (all EPSG codes)
  - State Plane Coordinate Systems
  - Custom projections with CF-compliant metadata

### CRS Detection Process
The system tries multiple detection methods in priority order:

1. **CF grid_mapping** (highest priority)
   - Reads `grid_mapping` attribute from data variables
   - Parses grid mapping variable for projection parameters
   - Supports: transverse_mercator, lambert_conformal_conic, polar_stereographic, etc.

2. **CRS WKT** (Well-Known Text)
   - Reads `crs_wkt` attribute
   - Parses WKT string using pyproj

3. **ESRI PE String**
   - Reads `esri_pe_string` attribute
   - Extracts EPSG code from projection string

4. **Spatial Reference**
   - Reads `spatial_ref` attribute
   - Handles both WKT and PROJ4 formats

### Coordinate Transformation
When a projected CRS is detected:
1. Extract x/y coordinate bounds from dataset
2. Transform corner points to WGS84 using pyproj
3. Compute geographic bounding box
4. Log transformation details for debugging

### Troubleshooting CRS Issues

#### Issue: Incorrect Bounding Box
**Symptom**: STAC metadata shows wrong spatial extent

**Diagnosis**:
```bash
# Check CloudWatch logs for CRS detection
aws logs tail /ecs/zarr-conversion --follow | grep "CRS"

# Look for:
# "Detected projected CRS: EPSG:2193"
# "Transformed bounds: [x_min, y_min, x_max, y_max] → [lon_min, lat_min, lon_max, lat_max]"
```

**Solutions**:
- **Missing CRS metadata**: Add CF-compliant grid_mapping to NetCDF file
- **Unsupported projection**: Check logs for CRS details, may need to add support
- **Transformation failure**: Verify coordinate values are within valid range

#### Issue: CRS Not Detected
**Symptom**: Logs show "Using default global bounding box"

**Diagnosis**:
```bash
# Check NetCDF metadata
ncdump -h your-file.nc | grep -E "grid_mapping|crs_wkt|esri_pe_string|spatial_ref"
```

**Solutions**:
1. Add CF-compliant grid_mapping:
```python
# Example: Add NZTM2000 grid mapping
ds['nztm'] = xr.DataArray(
    data=0,
    attrs={
        'grid_mapping_name': 'transverse_mercator',
        'latitude_of_projection_origin': 0.0,
        'longitude_of_central_meridian': 173.0,
        'false_easting': 1600000.0,
        'false_northing': 10000000.0,
        'scale_factor_at_central_meridian': 0.9996,
        'spatial_ref': 'EPSG:2193'
    }
)
ds['your_variable'].attrs['grid_mapping'] = 'nztm'
```

2. Or add crs_wkt attribute:
```python
ds.attrs['crs_wkt'] = 'PROJCS["NZTM2000",GEOGCS[...]]'
```

#### Issue: Transformation Produces Invalid Coordinates
**Symptom**: Bounding box has lon/lat outside valid range (-180 to 180, -90 to 90)

**Diagnosis**:
```bash
# Check transformation logs
aws logs tail /ecs/zarr-conversion --follow | grep "transform"
```

**Solutions**:
- **Coordinate order**: Ensure x/y coordinates are in correct order (not y/x)
- **Units**: Verify coordinates are in meters (for projected CRS)
- **Valid range**: Check that projected coordinates are within CRS valid bounds

### Metadata Extraction and Collections

#### Overview
The system automatically extracts variable metadata and creates STAC collections for each variable type.

#### Extracted Metadata
From each NetCDF file, the system extracts:

**Variable Metadata**:
- `name`: Variable name (e.g., "SST", "CHL")
- `long_name`: Descriptive name (e.g., "Sea Surface Temperature")
- `standard_name`: CF standard name (e.g., "sea_surface_temperature")
- `units`: Measurement units (e.g., "degC", "mg m-3")
- `dimensions`: Array dimensions
- `shape`: Array shape
- `dtype`: Data type

**Global Attributes**:
- `institution`: Data provider
- `title`: Dataset title
- `summary`: Dataset description
- `Conventions`: CF conventions version
- `creator_name`, `creator_email`: Contact information
- `project`, `acknowledgment`: Project details

#### Collection Organization
Collections are automatically created based on variable types:

**Collection Naming**:
1. Uses `standard_name` if present (e.g., "sea-surface-temperature")
2. Falls back to `long_name` (e.g., "sea-surface-temperature")
3. Falls back to variable name (e.g., "sst")

**Example Collections**:
- `sea-surface-temperature` - All SST variables
- `chlorophyll-concentration` - All chlorophyll variables
- `horizontal-visibility` - All visibility variables

#### Searchable Metadata Fields
All extracted metadata is indexed in STAC and searchable via API:

```bash
# Query by variable name
curl "http://${ALB_DNS}/api/search?variable=SST"

# Query by units
curl "http://${ALB_DNS}/api/search?units=degC"

# Query by institution
curl "http://${ALB_DNS}/api/search?institution=[YOURORG]"

# Query by collection
curl "http://${ALB_DNS}/api/collections/sea-surface-temperature/items"
```

#### Troubleshooting Metadata Issues

**Issue: Variables Not Extracted**
**Symptom**: STAC items missing variable metadata

**Diagnosis**:
```bash
# Check metadata extraction logs
aws logs tail /ecs/zarr-conversion --follow | grep "metadata"

# Check NetCDF structure
ncdump -h your-file.nc
```

**Solutions**:
- Ensure variables are data variables (not coordinate variables)
- Check that variables have dimensions
- Verify CF conventions compliance

**Issue: Collection Not Created**
**Symptom**: Variables not grouped into collections

**Diagnosis**:
```bash
# Check STAC creator logs
aws logs tail /aws/lambda/stac-creator --follow

# List collections
curl "http://${ALB_DNS}/api/collections"
```

**Solutions**:
- Add `standard_name` attribute to variables
- Ensure consistent naming across files
- Check for special characters in variable names

**Issue: Metadata Not Searchable**
**Symptom**: API queries return no results

**Diagnosis**:
```bash
# Check OpenSearch indexing
aws logs tail /aws/lambda/stac-indexer --follow

# Verify STAC properties
aws s3 cp s3://${STAC_BUCKET}/items/<item-id>.json - | jq '.properties'
```

**Solutions**:
- Verify metadata is in STAC properties field
- Check for special characters (should be escaped)
- Ensure OpenSearch index mapping is correct

## Related Documentation

- [ECS Zarr Migration Runbook](ECS_ZARR_MIGRATION_RUNBOOK.md) - Operations guide for ECS-based ingestion
- [Ingestion Pipeline Monitoring](INGESTION_PIPELINE_MONITORING.md) - Monitoring and cost verification
- [ResultSelector Data Flow Pattern](RESULTSELECTOR_DATA_FLOW_PATTERN.md) - Technical deep-dive
- [ECS Migration Deployment](ECS_MIGRATION_DEPLOYMENT.md) - Deployment procedures
- [Ingestion Pipeline](INGESTION_PIPELINE.md) - Architecture overview
- [NetCDF Metadata Enhancement](NETCDF_METADATA_ENHANCEMENT.md) - CRS detection and metadata extraction guide