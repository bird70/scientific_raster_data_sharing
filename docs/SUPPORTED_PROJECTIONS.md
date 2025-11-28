# Supported Projection Systems

## Overview

The ingestion pipeline automatically detects and transforms coordinate reference systems (CRS) from NetCDF files. This document lists commonly used projection systems and how to configure them in your NetCDF files.

## Geographic Coordinate Systems

### WGS84 (EPSG:4326)

**Description**: World Geodetic System 1984, the standard geographic CRS

**Usage**: No transformation needed, coordinates used directly

**NetCDF Configuration**:
```python
dimensions:
    lat = 180 ;
    lon = 360 ;
variables:
    double lat(lat) ;
        lat:standard_name = "latitude" ;
        lat:units = "degrees_north" ;
    double lon(lon) ;
        lon:standard_name = "longitude" ;
        lon:units = "degrees_east" ;
    float SST(lat, lon) ;
```

**Coordinate Range**:
- Longitude: -180 to 180 degrees
- Latitude: -90 to 90 degrees

---

## Projected Coordinate Systems

### NZTM2000 (EPSG:2193)

**Description**: New Zealand Transverse Mercator 2000

**Region**: New Zealand

**Units**: Meters

**NetCDF Configuration**:
```python
dimensions:
    y = 3163 ;
    x = 2471 ;
variables:
    double y(y) ;
        y:standard_name = "projection_y_coordinate" ;
        y:units = "m" ;
    double x(x) ;
        x:standard_name = "projection_x_coordinate" ;
        x:units = "m" ;
    float SST(y, x) ;
        SST:grid_mapping = "nztm" ;
    int nztm ;
        nztm:grid_mapping_name = "transverse_mercator" ;
        nztm:latitude_of_projection_origin = 0.0 ;
        nztm:longitude_of_central_meridian = 173.0 ;
        nztm:false_easting = 1600000.0 ;
        nztm:false_northing = 10000000.0 ;
        nztm:scale_factor_at_central_meridian = 0.9996 ;
        nztm:spatial_ref = "EPSG:2193" ;
```

**Coordinate Range**:
- X (Easting): ~1,000,000 to 2,000,000 meters
- Y (Northing): ~4,700,000 to 6,200,000 meters


### UTM (Universal Transverse Mercator)

**Description**: Universal Transverse Mercator projection system

**Region**: Global (divided into 60 zones)

**Units**: Meters

**Common EPSG Codes**:
- UTM Zone 1N: EPSG:32601
- UTM Zone 30N: EPSG:32630 (UK)
- UTM Zone 60N: EPSG:32660
- UTM Zone 1S: EPSG:32701
- UTM Zone 60S: EPSG:32760

**NetCDF Configuration** (Example: UTM Zone 60S):
```python
dimensions:
    y = 1000 ;
    x = 1000 ;
variables:
    double y(y) ;
        y:standard_name = "projection_y_coordinate" ;
        y:units = "m" ;
    double x(x) ;
        x:standard_name = "projection_x_coordinate" ;
        x:units = "m" ;
    float data(y, x) ;
        data:grid_mapping = "utm" ;
    int utm ;
        utm:grid_mapping_name = "transverse_mercator" ;
        utm:latitude_of_projection_origin = 0.0 ;
        utm:longitude_of_central_meridian = 177.0 ;
        utm:false_easting = 500000.0 ;
        utm:false_northing = 10000000.0 ;
        utm:scale_factor_at_central_meridian = 0.9996 ;
        utm:spatial_ref = "EPSG:32760" ;
```

**Coordinate Range** (per zone):
- X (Easting): 160,000 to 840,000 meters
- Y (Northing): 0 to 10,000,000 meters (Northern Hemisphere)
- Y (Northing): 0 to 10,000,000 meters (Southern Hemisphere)


### Web Mercator (EPSG:3857)

**Description**: Web Mercator projection used by web mapping services

**Region**: Global (excluding polar regions)

**Units**: Meters

**NetCDF Configuration**:
```python
dimensions:
    y = 1000 ;
    x = 1000 ;
variables:
    double y(y) ;
        y:standard_name = "projection_y_coordinate" ;
        y:units = "m" ;
    double x(x) ;
        x:standard_name = "projection_x_coordinate" ;
        x:units = "m" ;
    float data(y, x) ;
        data:grid_mapping = "mercator" ;
    int mercator ;
        mercator:grid_mapping_name = "mercator" ;
        mercator:longitude_of_projection_origin = 0.0 ;
        mercator:standard_parallel = 0.0 ;
        mercator:false_easting = 0.0 ;
        mercator:false_northing = 0.0 ;
        mercator:spatial_ref = "EPSG:3857" ;
```

**Coordinate Range**:
- X: -20,037,508 to 20,037,508 meters
- Y: -20,037,508 to 20,037,508 meters

**Note**: Not suitable for polar regions (>85° latitude)


### Lambert Conformal Conic

**Description**: Lambert Conformal Conic projection

**Region**: Mid-latitude regions

**Units**: Meters

**Common EPSG Codes**:
- Lambert-93 (France): EPSG:2154
- NAD83 / Lambert Conformal Conic (US): Various

**NetCDF Configuration** (Example: Lambert-93):
```python
dimensions:
    y = 1000 ;
    x = 1000 ;
variables:
    double y(y) ;
        y:standard_name = "projection_y_coordinate" ;
        y:units = "m" ;
    double x(x) ;
        x:standard_name = "projection_x_coordinate" ;
        x:units = "m" ;
    float data(y, x) ;
        data:grid_mapping = "lambert" ;
    int lambert ;
        lambert:grid_mapping_name = "lambert_conformal_conic" ;
        lambert:latitude_of_projection_origin = 46.5 ;
        lambert:longitude_of_central_meridian = 3.0 ;
        lambert:standard_parallel = 44.0, 49.0 ;
        lambert:false_easting = 700000.0 ;
        lambert:false_northing = 6600000.0 ;
        lambert:spatial_ref = "EPSG:2154" ;
```

### Polar Stereographic

**Description**: Polar Stereographic projection

**Region**: Polar regions (Arctic/Antarctic)

**Units**: Meters

**Common EPSG Codes**:
- WGS 84 / Antarctic Polar Stereographic: EPSG:3031
- WGS 84 / NSIDC Sea Ice Polar Stereographic North: EPSG:3413

**NetCDF Configuration** (Example: Antarctic):
```python
dimensions:
    y = 1000 ;
    x = 1000 ;
variables:
    double y(y) ;
        y:standard_name = "projection_y_coordinate" ;
        y:units = "m" ;
    double x(x) ;
        x:standard_name = "projection_x_coordinate" ;
        x:units = "m" ;
    float data(y, x) ;
        data:grid_mapping = "polar_stereo" ;
    int polar_stereo ;
        polar_stereo:grid_mapping_name = "polar_stereographic" ;
        polar_stereo:latitude_of_projection_origin = -90.0 ;
        polar_stereo:straight_vertical_longitude_from_pole = 0.0 ;
        polar_stereo:scale_factor_at_projection_origin = 1.0 ;
        polar_stereo:false_easting = 0.0 ;
        polar_stereo:false_northing = 0.0 ;
        polar_stereo:spatial_ref = "EPSG:3031" ;
```


---

## Alternative CRS Specification Methods

### Method 1: Using crs_wkt Attribute

Instead of grid_mapping, you can use Well-Known Text (WKT):

```python
// global attributes:
    :crs_wkt = "PROJCS[\"NZTM2000\",GEOGCS[\"GCS_NZGD_2000\",DATUM[\"D_NZGD_2000\",SPHEROID[\"GRS_1980\",6378137.0,298.257222101]],PRIMEM[\"Greenwich\",0.0],UNIT[\"Degree\",0.0174532925199433]],PROJECTION[\"Transverse_Mercator\"],PARAMETER[\"False_Easting\",1600000.0],PARAMETER[\"False_Northing\",10000000.0],PARAMETER[\"Central_Meridian\",173.0],PARAMETER[\"Scale_Factor\",0.9996],PARAMETER[\"Latitude_Of_Origin\",0.0],UNIT[\"Meter\",1.0]]" ;
```

### Method 2: Using spatial_ref Attribute

Simplest method using EPSG code:

```python
// global attributes:
    :spatial_ref = "EPSG:2193" ;
```

Or using PROJ4 string:

```python
// global attributes:
    :spatial_ref = "+proj=tmerc +lat_0=0 +lon_0=173 +k=0.9996 +x_0=1600000 +y_0=10000000 +ellps=GRS80 +units=m +no_defs" ;
```

### Method 3: Using esri_pe_string Attribute

ESRI projection string format:

```python
// global attributes:
    :esri_pe_string = "PROJCS[\"NZGD_2000_New_Zealand_Transverse_Mercator\",GEOGCS[\"GCS_NZGD_2000\",DATUM[\"D_NZGD_2000\",SPHEROID[\"GRS_1980\",6378137.0,298.257222101]],PRIMEM[\"Greenwich\",0.0],UNIT[\"Degree\",0.0174532925199433]],PROJECTION[\"Transverse_Mercator\"],PARAMETER[\"False_Easting\",1600000.0],PARAMETER[\"False_Northing\",10000000.0],PARAMETER[\"Central_Meridian\",173.0],PARAMETER[\"Scale_Factor\",0.9996],PARAMETER[\"Latitude_Of_Origin\",0.0],UNIT[\"Meter\",1.0]]" ;
```

---

## Detection Priority

The system tries detection methods in this order:

1. **CF grid_mapping** (highest priority, most detailed)
2. **crs_wkt** (Well-Known Text)
3. **esri_pe_string** (ESRI format)
4. **spatial_ref** (EPSG code or PROJ4)

**Recommendation**: Use CF grid_mapping for best compatibility and documentation.


---

## Testing Your CRS Configuration

### Validate with Python

```python
import xarray as xr
from app.ingestion.crs_utils import CRSDetector

# Open your NetCDF file
ds = xr.open_dataset('your-file.nc')

# Test CRS detection
detector = CRSDetector()
crs = detector.detect_crs(ds)

if crs:
    print(f"✓ CRS detected: {crs.to_string()}")
    print(f"  EPSG code: {crs.to_epsg()}")
    print(f"  Is geographic: {crs.is_geographic}")
    print(f"  Units: {crs.axis_info[0].unit_name}")
else:
    print("✗ No CRS detected")
    print("  Will use default global bounding box")
```

### Validate with ncdump

```bash
# Check for CRS metadata
ncdump -h your-file.nc | grep -E "grid_mapping|crs_wkt|spatial_ref|esri_pe_string"

# Check coordinate variables
ncdump -h your-file.nc | grep -E "projection_[xy]_coordinate"

# Check coordinate units
ncdump -h your-file.nc | grep "units"
```

### Validate with CF Checker

```bash
# Install CF checker
pip install cfchecker

# Check CF compliance
cfchecks your-file.nc

# Look for warnings about:
# - Missing grid_mapping
# - Invalid coordinate attributes
# - Non-standard projection parameters
```

---

## Common Issues and Solutions

### Issue: CRS Not Detected

**Problem**: System uses default global bounding box

**Solution**: Add one of the CRS specification methods above

### Issue: Wrong Coordinate Order

**Problem**: Bounding box is incorrect

**Solution**: Ensure coordinates have correct standard_name:
```python
x:standard_name = "projection_x_coordinate" ;
y:standard_name = "projection_y_coordinate" ;
```

### Issue: Wrong Units

**Problem**: Transformation fails

**Solution**: Ensure projected coordinates are in meters:
```python
x:units = "m" ;
y:units = "m" ;
```

### Issue: Coordinates Outside Valid Range

**Problem**: Transformation produces invalid results

**Solution**: Verify coordinates are within CRS valid bounds
- Check EPSG code documentation
- Ensure data is in correct projection zone

---

## Reference

### Useful Links

- [CF Conventions Grid Mapping](http://cfconventions.org/Data/cf-conventions/cf-conventions-1.8/cf-conventions.html#appendix-grid-mappings)
- [EPSG Registry](https://epsg.io/)
- [Proj.org Documentation](https://proj.org/)
- [pyproj Documentation](https://pyproj4.github.io/pyproj/)

### Support

For questions or issues with CRS detection:
1. Check CloudWatch logs: `/ecs/zarr-conversion`
2. Review [NetCDF Metadata Enhancement Guide](NETCDF_METADATA_ENHANCEMENT.md)
3. Validate NetCDF file with CF checker

