# NetCDF Metadata Enhancement Guide

## Overview

This guide covers the enhanced NetCDF ingestion capabilities including:
- Automatic CRS detection and coordinate transformation
- Variable metadata extraction
- Collection organization
- Searchable metadata indexing

## Table of Contents

1. [CRS Detection and Transformation](#crs-detection-and-transformation)
2. [Metadata Extraction](#metadata-extraction)
3. [Collection Management](#collection-management)
4. [Troubleshooting](#troubleshooting)
5. [Best Practices](#best-practices)

---

## CRS Detection and Transformation

### Supported Coordinate Reference Systems

The ingestion pipeline supports both geographic and projected coordinate systems:

#### Geographic CRS (No Transformation)
- **WGS84** (EPSG:4326) - Standard lat/lon
- Any geographic CRS with latitude/longitude coordinates

#### Projected CRS (Automatic Transformation to WGS84)
- **NZTM2000** (EPSG:2193) - New Zealand Transverse Mercator
- **UTM Zones** - All Universal Transverse Mercator zones
- **State Plane** - US State Plane Coordinate Systems
- **Custom Projections** - Any projection with CF-compliant metadata

### Detection Methods

The system tries multiple detection methods in priority order:


#### 1. CF Grid Mapping (Highest Priority)

**What it is**: CF conventions standard for specifying coordinate reference systems

**How it works**:
```python
# NetCDF structure with grid_mapping
dimensions:
    y = 3163
    x = 2471
variables:
    float SST(y, x)
        SST:grid_mapping = "nztm"
    int nztm
        nztm:grid_mapping_name = "transverse_mercator"
        nztm:latitude_of_projection_origin = 0.0
        nztm:longitude_of_central_meridian = 173.0
        nztm:false_easting = 1600000.0
        nztm:false_northing = 10000000.0
        nztm:scale_factor_at_central_meridian = 0.9996
        nztm:spatial_ref = "EPSG:2193"
```

**Supported grid mapping names**:
- `transverse_mercator` - UTM, NZTM, etc.
- `lambert_conformal_conic` - Lambert projections
- `polar_stereographic` - Polar projections
- `albers_conical_equal_area` - Albers projections
- And all other CF-compliant grid mappings

#### 2. CRS WKT (Well-Known Text)

**What it is**: OGC standard for describing coordinate systems

**How it works**:
```python
# NetCDF global attribute
:crs_wkt = "PROJCS[\"NZTM2000\",GEOGCS[\"GCS_NZGD_2000\",...]]"
```


#### 3. ESRI PE String

**What it is**: ESRI projection string format

**How it works**:
```python
# NetCDF global or variable attribute
:esri_pe_string = "PROJCS[\"NZGD_2000_New_Zealand_Transverse_Mercator\",...]"
```

#### 4. Spatial Reference

**What it is**: Generic spatial reference attribute

**How it works**:
```python
# Can be WKT or PROJ4 format
:spatial_ref = "EPSG:2193"
# or
:spatial_ref = "+proj=tmerc +lat_0=0 +lon_0=173 +k=0.9996 +x_0=1600000 +y_0=10000000"
```

### Coordinate Transformation Process

When a projected CRS is detected, the system:

1. **Extracts coordinate bounds**
   - Finds x/y coordinate variables
   - Computes min/max values
   - Handles large arrays via sampling (>10,000 points)

2. **Transforms to WGS84**
   - Uses pyproj.Transformer with `always_xy=True`
   - Transforms corner points of bounding box
   - Handles coordinate order correctly

3. **Validates results**
   - Ensures lon/lat within valid range
   - Logs transformation details
   - Falls back to default if transformation fails


### Example: NZTM2000 File Processing

**Input NetCDF** (NZTM2000 coordinates):
```
dimensions:
    y = 3163 ;
    x = 2471 ;
variables:
    double y(y) ;
        y:units = "m" ;
        y:standard_name = "projection_y_coordinate" ;
    double x(x) ;
        x:units = "m" ;
        x:standard_name = "projection_x_coordinate" ;
    float SST(y, x) ;
        SST:grid_mapping = "nztm" ;
    int nztm ;
        nztm:grid_mapping_name = "transverse_mercator" ;
        nztm:spatial_ref = "EPSG:2193" ;
```

**Processing Steps**:
```
1. CRS Detection: Detected EPSG:2193 (NZTM2000) via grid_mapping
2. Coordinate Extraction: x=[1100000, 1600000], y=[4700000, 5200000]
3. Transformation: [1100000, 4700000, 1600000, 5200000] → [166.5, -47.3, 179.8, -34.4]
4. STAC Metadata: bbox=[166.5, -47.3, 179.8, -34.4]
```

**CloudWatch Logs**:
```
INFO: Detected projected CRS: EPSG:2193
INFO: Original bounds (NZTM): [1100000.0, 4700000.0, 1600000.0, 5200000.0]
INFO: Transformed bounds (WGS84): [166.5, -47.3, 179.8, -34.4]
INFO: Bounding box successfully transformed
```

---

## Metadata Extraction

### Variable Metadata

The system extracts comprehensive metadata from each data variable:


#### Extracted Fields

| Field | Source | Example | Required |
|-------|--------|---------|----------|
| `name` | Variable name | `"SST"` | Yes |
| `long_name` | CF attribute | `"Sea Surface Temperature"` | No |
| `standard_name` | CF attribute | `"sea_surface_temperature"` | No |
| `units` | CF attribute | `"degC"` | No |
| `description` | CF attribute | `"Daily mean SST"` | No |
| `dimensions` | Variable dims | `["time", "y", "x"]` | Yes |
| `shape` | Variable shape | `[365, 3163, 2471]` | Yes |
| `dtype` | Data type | `"float32"` | Yes |

#### Example NetCDF Variable

```python
float SST(time, y, x) ;
    SST:long_name = "Sea Surface Temperature" ;
    SST:standard_name = "sea_surface_temperature" ;
    SST:units = "degC" ;
    SST:description = "Daily mean sea surface temperature" ;
    SST:valid_min = -2.0 ;
    SST:valid_max = 35.0 ;
    SST:_FillValue = -999.0 ;
    SST:grid_mapping = "nztm" ;
```

#### Extracted Metadata JSON

```json
{
  "name": "SST",
  "long_name": "Sea Surface Temperature",
  "standard_name": "sea_surface_temperature",
  "units": "degC",
  "description": "Daily mean sea surface temperature",
  "dimensions": ["time", "y", "x"],
  "shape": [365, 3163, 2471],
  "dtype": "float32"
}
```


### Global Attributes

The system extracts CF-compliant global attributes:

#### Standard CF Attributes

| Attribute | Description | Example |
|-----------|-------------|---------|
| `title` | Dataset title | `"[YOURORG] Marine Coastal SST"` |
| `institution` | Data provider | `"[YOURORG]"` |
| `source` | Data source | `"Satellite observations"` |
| `history` | Processing history | `"Created 2024-01-15"` |
| `references` | Citations | `"doi:10.1234/example"` |
| `comment` | Additional info | `"Quality controlled"` |
| `summary` | Dataset summary | `"Daily SST for NZ waters"` |
| `keywords` | Search keywords | `"ocean, temperature, SST"` |
| `Conventions` | CF version | `"CF-1.6"` |
| `creator_name` | Creator name | `"John Smith"` |
| `creator_email` | Contact email | `"john@[YOURORG].co.nz"` |
| `project` | Project name | `"Marine Monitoring"` |

#### Example Global Attributes

```python
// global attributes:
    :title = "[YOURORG] Marine Coastal Sea Surface Temperature" ;
    :institution = "[YOURORG] (National Institute of Water and Atmospheric Research)" ;
    :source = "Satellite observations and in-situ measurements" ;
    :Conventions = "CF-1.6" ;
    :creator_name = "[YOURORG] Ocean Data Team" ;
    :creator_email = "ocean.data@[YOURORG].co.nz" ;
    :project = "Marine Coastal Monitoring Programme" ;
    :summary = "Daily mean sea surface temperature for New Zealand coastal waters" ;
```


---

## Collection Management

### Collection Creation

Collections are automatically created based on variable types. Each unique variable type gets its own collection.

#### Collection Naming Strategy

The system uses this priority order to determine collection names:

1. **standard_name** (highest priority)
   - Uses CF standard name
   - Example: `sea_surface_temperature` → `sea-surface-temperature`

2. **long_name** (fallback)
   - Uses descriptive name
   - Example: `Sea Surface Temperature` → `sea-surface-temperature`

3. **variable name** (last resort)
   - Uses variable name directly
   - Example: `SST` → `sst`

#### Collection Metadata

Each collection includes:

```json
{
  "id": "sea-surface-temperature",
  "title": "Sea Surface Temperature",
  "description": "Sea Surface Temperature measurements",
  "extent": {
    "spatial": {
      "bbox": [[-180, -90, 180, 90]]
    },
    "temporal": {
      "interval": [["2002-01-01T00:00:00Z", "2024-12-31T23:59:59Z"]]
    }
  },
  "properties": {
    "units": "degC",
    "standard_name": "sea_surface_temperature"
  }
}
```


### Multi-Variable Files

When a NetCDF file contains multiple data variables, each variable is indexed separately:

**Example File Structure**:
```
variables:
    float SST(time, y, x) ;
        SST:standard_name = "sea_surface_temperature" ;
    float CHL(time, y, x) ;
        CHL:standard_name = "mass_concentration_of_chlorophyll_in_sea_water" ;
    float HVIS(time, y, x) ;
        HVIS:standard_name = "horizontal_visibility_in_air" ;
```

**Result**:
- 3 STAC items created (one per variable)
- 3 collections: `sea-surface-temperature`, `chlorophyll-concentration`, `horizontal-visibility`
- Each item linked to appropriate collection

### Searchable Metadata

All extracted metadata is indexed in STAC and searchable via API.

#### Search by Variable Name

```bash
# Find all SST datasets
curl "http://${ALB_DNS}/api/search?variable=SST"

# Find all chlorophyll datasets
curl "http://${ALB_DNS}/api/search?variable=CHL"
```

#### Search by Units

```bash
# Find all temperature datasets (degC)
curl "http://${ALB_DNS}/api/search?units=degC"

# Find all chlorophyll datasets (mg m-3)
curl "http://${ALB_DNS}/api/search?units=mg+m-3"
```


#### Search by Institution

```bash
# Find all [YOURORG] datasets
curl "http://${ALB_DNS}/api/search?institution=[YOURORG]"
```

#### Search by Collection

```bash
# List all collections
curl "http://${ALB_DNS}/api/collections"

# Get items in a collection
curl "http://${ALB_DNS}/api/collections/sea-surface-temperature/items"

# Get collection metadata
curl "http://${ALB_DNS}/api/collections/sea-surface-temperature"
```

#### Search by Spatial Extent

```bash
# Find datasets intersecting a bounding box
curl "http://${ALB_DNS}/api/search?bbox=166,-48,180,-34"
```

#### Combined Queries

```bash
# Find SST datasets from [YOURORG] in a specific area
curl "http://${ALB_DNS}/api/search?variable=SST&institution=[YOURORG]&bbox=166,-48,180,-34"
```

---

## Troubleshooting

### CRS Detection Issues


#### Problem: CRS Not Detected

**Symptoms**:
- CloudWatch logs show: "Using default global bounding box"
- STAC metadata has bbox: [-180, -90, 180, 90]

**Diagnosis**:
```bash
# Check NetCDF metadata
ncdump -h your-file.nc | grep -E "grid_mapping|crs_wkt|esri_pe_string|spatial_ref"

# Check CloudWatch logs
aws logs tail /ecs/zarr-conversion --follow | grep "CRS"
```

**Solutions**:

1. **Add CF grid_mapping** (recommended):
```python
import xarray as xr

ds = xr.open_dataset('your-file.nc')

# Create grid mapping variable
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

# Link data variable to grid mapping
ds['SST'].attrs['grid_mapping'] = 'nztm'

ds.to_netcdf('your-file-fixed.nc')
```

2. **Add crs_wkt attribute**:
```python
ds.attrs['crs_wkt'] = 'PROJCS["NZTM2000",GEOGCS["GCS_NZGD_2000",...]]'
```

3. **Add spatial_ref attribute**:
```python
ds.attrs['spatial_ref'] = 'EPSG:2193'
```


#### Problem: Incorrect Bounding Box

**Symptoms**:
- Bounding box doesn't match expected geographic extent
- Coordinates outside valid range (lon: -180 to 180, lat: -90 to 90)

**Diagnosis**:
```bash
# Check transformation logs
aws logs tail /ecs/zarr-conversion --follow | grep "transform"

# Look for:
# - Original projected bounds
# - Transformed geographic bounds
# - Any error messages
```

**Common Causes and Solutions**:

1. **Wrong coordinate order** (y/x instead of x/y):
```python
# Check coordinate variable names
ncdump -h your-file.nc | grep "projection_[xy]_coordinate"

# Ensure x has standard_name = "projection_x_coordinate"
# Ensure y has standard_name = "projection_y_coordinate"
```

2. **Wrong units** (degrees instead of meters):
```python
# Check coordinate units
ncdump -h your-file.nc | grep "units"

# For projected CRS, coordinates should be in meters
x:units = "m" ;
y:units = "m" ;
```

3. **Coordinates outside valid range**:
```python
# Check coordinate values
ncdump -v x,y your-file.nc | head -20

# For NZTM2000, valid range is approximately:
# x: 1000000 to 2000000
# y: 4700000 to 6200000
```


#### Problem: Transformation Fails

**Symptoms**:
- CloudWatch logs show: "Coordinate transformation failed"
- Falls back to default bounding box

**Diagnosis**:
```bash
# Check error logs
aws logs tail /ecs/zarr-conversion --follow | grep -A 5 "transformation failed"
```

**Common Causes and Solutions**:

1. **Invalid CRS definition**:
   - Verify EPSG code is correct
   - Check grid mapping parameters are complete
   - Ensure pyproj can parse the CRS

2. **Coordinates outside CRS valid area**:
   - Check coordinate values are within CRS bounds
   - For NZTM2000: New Zealand only
   - For UTM: specific zone only

3. **Missing pyproj database**:
   - Ensure Docker image includes pyproj with PROJ database
   - Check pyproj version compatibility

### Metadata Extraction Issues

#### Problem: Variables Not Extracted

**Symptoms**:
- STAC items missing variable metadata
- Empty variables array in STAC properties

**Diagnosis**:
```bash
# Check metadata extraction logs
aws logs tail /ecs/zarr-conversion --follow | grep "metadata"

# Check NetCDF structure
ncdump -h your-file.nc
```


**Solutions**:

1. **Ensure variables are data variables**:
```python
# Data variables (extracted):
float SST(time, y, x) ;

# Coordinate variables (not extracted):
double time(time) ;
double y(y) ;
double x(x) ;
```

2. **Check variable has dimensions**:
```python
# Valid (has dimensions):
float SST(time, y, x) ;

# Invalid (scalar variable):
int crs ;
```

3. **Verify CF conventions**:
```python
# Add CF attributes
SST:long_name = "Sea Surface Temperature" ;
SST:standard_name = "sea_surface_temperature" ;
SST:units = "degC" ;
```

#### Problem: Collections Not Created

**Symptoms**:
- API returns empty collections list
- Variables not grouped by type

**Diagnosis**:
```bash
# Check STAC creator logs
aws logs tail /aws/lambda/stac-creator --follow

# List collections
curl "http://${ALB_DNS}/api/collections"
```

**Solutions**:

1. **Add standard_name to variables**:
```python
SST:standard_name = "sea_surface_temperature" ;
```

2. **Ensure consistent naming**:
```python
# All SST files should use same standard_name
# File 1:
SST:standard_name = "sea_surface_temperature" ;

# File 2:
SST:standard_name = "sea_surface_temperature" ;  # Same!
```


#### Problem: Metadata Not Searchable

**Symptoms**:
- API queries return no results
- Metadata present in STAC JSON but not searchable

**Diagnosis**:
```bash
# Check STAC indexer logs
aws logs tail /aws/lambda/stac-indexer --follow

# Verify STAC properties
aws s3 cp s3://${STAC_BUCKET}/items/<item-id>.json - | jq '.properties'

# Check OpenSearch index
curl -X GET "https://${OPENSEARCH_ENDPOINT}/_cat/indices?v"
```

**Solutions**:

1. **Verify metadata in STAC properties**:
```json
{
  "properties": {
    "variables": ["SST"],
    "variable_metadata": [{
      "name": "SST",
      "units": "degC",
      "standard_name": "sea_surface_temperature"
    }],
    "institution": "[YOURORG]"
  }
}
```

2. **Check OpenSearch index mapping**:
```bash
# Get index mapping
curl -X GET "https://${OPENSEARCH_ENDPOINT}/stac/_mapping"
```

3. **Re-index if needed**:
```bash
# Delete and recreate index
curl -X DELETE "https://${OPENSEARCH_ENDPOINT}/stac"

# Re-run ingestion pipeline
aws s3 cp your-file.nc s3://${RAW_BUCKET}/ingestion/your-file.nc
```


---

## Best Practices

### NetCDF File Preparation

#### 1. Always Include CF-Compliant Metadata

**Minimum required**:
```python
// global attributes:
    :Conventions = "CF-1.6" ;
    :title = "Your Dataset Title" ;
    :institution = "Your Institution" ;

// variable attributes:
float SST(time, y, x) ;
    SST:long_name = "Sea Surface Temperature" ;
    SST:units = "degC" ;
```

**Recommended**:
```python
// global attributes:
    :Conventions = "CF-1.6" ;
    :title = "[YOURORG] Marine Coastal Sea Surface Temperature" ;
    :institution = "[YOURORG]" ;
    :source = "Satellite observations" ;
    :summary = "Daily mean SST for NZ coastal waters" ;
    :creator_name = "[YOURORG] Ocean Data Team" ;
    :creator_email = "ocean.data@[YOURORG].co.nz" ;
    :project = "Marine Coastal Monitoring" ;

// variable attributes:
float SST(time, y, x) ;
    SST:long_name = "Sea Surface Temperature" ;
    SST:standard_name = "sea_surface_temperature" ;
    SST:units = "degC" ;
    SST:description = "Daily mean sea surface temperature" ;
    SST:valid_min = -2.0f ;
    SST:valid_max = 35.0f ;
    SST:_FillValue = -999.0f ;
```


#### 2. Use Standard Names

Always use CF standard names when available:

**Good**:
```python
SST:standard_name = "sea_surface_temperature" ;
CHL:standard_name = "mass_concentration_of_chlorophyll_in_sea_water" ;
```

**Avoid**:
```python
SST:standard_name = "sst" ;  # Not a CF standard name
CHL:standard_name = "chlorophyll" ;  # Too generic
```

**Reference**: [CF Standard Names Table](http://cfconventions.org/standard-names.html)

#### 3. Include Grid Mapping for Projected CRS

For projected coordinate systems, always include grid_mapping:

```python
dimensions:
    y = 3163 ;
    x = 2471 ;

variables:
    double y(y) ;
        y:standard_name = "projection_y_coordinate" ;
        y:long_name = "y coordinate of projection" ;
        y:units = "m" ;
    
    double x(x) ;
        x:standard_name = "projection_x_coordinate" ;
        x:long_name = "x coordinate of projection" ;
        x:units = "m" ;
    
    float SST(y, x) ;
        SST:grid_mapping = "nztm" ;
        SST:coordinates = "lat lon" ;
    
    int nztm ;
        nztm:grid_mapping_name = "transverse_mercator" ;
        nztm:latitude_of_projection_origin = 0.0 ;
        nztm:longitude_of_central_meridian = 173.0 ;
        nztm:false_easting = 1600000.0 ;
        nztm:false_northing = 10000000.0 ;
        nztm:scale_factor_at_central_meridian = 0.9996 ;
        nztm:spatial_ref = "EPSG:2193" ;
```


#### 4. Consistent Variable Naming

Use consistent variable names and standard_names across files:

**Good** (files will be grouped in same collection):
```python
// File 1:
float SST(time, y, x) ;
    SST:standard_name = "sea_surface_temperature" ;

// File 2:
float SST(time, y, x) ;
    SST:standard_name = "sea_surface_temperature" ;  # Same!
```

**Avoid** (files will be in different collections):
```python
// File 1:
float SST(time, y, x) ;
    SST:standard_name = "sea_surface_temperature" ;

// File 2:
float TEMP(time, y, x) ;
    TEMP:standard_name = "sea_water_temperature" ;  # Different!
```

#### 5. Include Units

Always specify units for data variables:

```python
SST:units = "degC" ;
CHL:units = "mg m-3" ;
HVIS:units = "m" ;
```

Use standard unit formats:
- Temperature: `degC`, `K`
- Concentration: `mg m-3`, `kg m-3`
- Distance: `m`, `km`
- Time: `seconds since 1970-01-01`


### Testing Your NetCDF Files

Before uploading to production, test your NetCDF files:

#### 1. Validate CF Compliance

```bash
# Install CF checker
pip install cfchecker

# Check your file
cfchecks your-file.nc
```

#### 2. Verify CRS Detection

```python
import xarray as xr
from app.ingestion.crs_utils import CRSDetector

# Open your file
ds = xr.open_dataset('your-file.nc')

# Test CRS detection
detector = CRSDetector()
crs = detector.detect_crs(ds)

if crs:
    print(f"Detected CRS: {crs.to_string()}")
    print(f"Is geographic: {crs.is_geographic}")
else:
    print("No CRS detected - will use default bbox")
```

#### 3. Test Metadata Extraction

```python
from app.ingestion.metadata_extractor import MetadataExtractor

# Extract metadata
extractor = MetadataExtractor()
metadata = extractor.extract_all_metadata(ds)

# Check results
print(f"Variables: {[v['name'] for v in metadata['variables']]}")
print(f"Collections: {[c['name'] for c in metadata['collections']]}")
print(f"Global attributes: {list(metadata['global_attributes'].keys())}")
```


#### 4. Test End-to-End Ingestion

```bash
# Upload to test bucket
aws s3 cp your-file.nc s3://${RAW_BUCKET}/ingestion/test/your-file.nc

# Monitor Step Functions
aws stepfunctions list-executions \
  --state-machine-arn $(terraform output -raw ingestion_state_machine_arn) \
  --max-results 1

# Check CloudWatch logs
aws logs tail /ecs/zarr-conversion --follow

# Verify STAC metadata
aws s3 ls s3://${STAC_BUCKET}/items/

# Query API
curl "http://${ALB_DNS}/api/collections"
curl "http://${ALB_DNS}/api/search?variable=SST"
```

### Monitoring and Debugging

#### CloudWatch Log Groups

Monitor these log groups for CRS and metadata processing:

```bash
# Zarr conversion (includes CRS detection and metadata extraction)
aws logs tail /ecs/zarr-conversion --follow

# STAC creator (includes collection creation)
aws logs tail /aws/lambda/stac-creator --follow

# STAC indexer (includes OpenSearch indexing)
aws logs tail /aws/lambda/stac-indexer --follow
```

#### Key Log Messages

**Successful CRS detection**:
```
INFO: Detected projected CRS: EPSG:2193
INFO: Original bounds (NZTM): [1100000.0, 4700000.0, 1600000.0, 5200000.0]
INFO: Transformed bounds (WGS84): [166.5, -47.3, 179.8, -34.4]
```

**CRS detection failure**:
```
WARNING: No CRS detected, using default global bounding box
```


**Successful metadata extraction**:
```
INFO: Extracted 3 variables: ['SST', 'CHL', 'HVIS']
INFO: Created 3 collections: ['sea-surface-temperature', 'chlorophyll-concentration', 'horizontal-visibility']
```

**Metadata extraction issues**:
```
WARNING: No data variables found in dataset
WARNING: Variable 'SST' missing standard_name, using variable name for collection
```

#### CloudWatch Metrics

Monitor these metrics:

- **Ingestion Success Rate**: Step Functions execution success/failure
- **CRS Detection Rate**: Percentage of files with detected CRS
- **Transformation Success Rate**: Percentage of successful coordinate transformations
- **Collection Count**: Number of unique collections created

---

## Reference

### Supported EPSG Codes

Common EPSG codes supported by the system:

| EPSG | Name | Region | Type |
|------|------|--------|------|
| 4326 | WGS84 | Global | Geographic |
| 2193 | NZTM2000 | New Zealand | Projected |
| 32601-32660 | UTM North | Global | Projected |
| 32701-32760 | UTM South | Global | Projected |
| 3857 | Web Mercator | Global | Projected |
| 2154 | Lambert-93 | France | Projected |
| 27700 | OSGB36 | UK | Projected |

**Note**: Any EPSG code supported by pyproj will work.


### CF Standard Names

Common CF standard names for ocean/atmosphere data:

| Standard Name | Description | Units |
|---------------|-------------|-------|
| `sea_surface_temperature` | Sea surface temperature | K, degC |
| `sea_water_temperature` | Water temperature | K, degC |
| `sea_water_salinity` | Salinity | psu, 1 |
| `mass_concentration_of_chlorophyll_in_sea_water` | Chlorophyll concentration | mg m-3 |
| `horizontal_visibility_in_air` | Visibility | m |
| `air_temperature` | Air temperature | K, degC |
| `wind_speed` | Wind speed | m s-1 |
| `sea_surface_wave_significant_height` | Wave height | m |

**Full list**: [CF Standard Names](http://cfconventions.org/standard-names.html)

### API Endpoints

#### Collections

```bash
# List all collections
GET /api/collections

# Get collection metadata
GET /api/collections/{collection_id}

# Get items in collection
GET /api/collections/{collection_id}/items
```

#### Search

```bash
# Search all items
GET /api/search

# Search with filters
GET /api/search?variable=SST&institution=[YOURORG]&bbox=166,-48,180,-34

# Search by collection
GET /api/collections/{collection_id}/items?bbox=166,-48,180,-34
```


### Query Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `bbox` | Bounding box (lon_min,lat_min,lon_max,lat_max) | `166,-48,180,-34` |
| `datetime` | Time range (ISO 8601) | `2024-01-01/2024-12-31` |
| `variable` | Variable name | `SST` |
| `units` | Measurement units | `degC` |
| `institution` | Data provider | `[YOURORG]` |
| `limit` | Max results | `10` |
| `offset` | Pagination offset | `20` |

---

## Summary

The NetCDF metadata enhancement feature provides:

✅ **Automatic CRS Detection**
- Supports geographic and projected coordinate systems
- Multiple detection methods (grid_mapping, WKT, ESRI, spatial_ref)
- Automatic transformation to WGS84

✅ **Comprehensive Metadata Extraction**
- Variable metadata (name, units, standard_name, etc.)
- Global attributes (institution, title, creator, etc.)
- CF-compliant attribute handling

✅ **Intelligent Collection Management**
- Automatic collection creation by variable type
- Consistent naming from standard_name
- Multi-variable file support

✅ **Full-Text Search**
- All metadata indexed in STAC
- Query by variable, units, institution, spatial extent
- Collection-based organization

For questions or issues, check CloudWatch logs or refer to the troubleshooting section above.

