#!/usr/bin/env python3
"""
Zarr Converter for NetCDF to Zarr conversion in ECS tasks
"""
import json
import logging
import os
import sys
from pathlib import Path
from typing import List, Tuple, Optional

import boto3
import numpy as np
import s3fs
import xarray as xr
import zarr

try:
    from .crs_utils import CRSDetector, CoordinateTransformer
    from .metadata_extractor import MetadataExtractor, STACMetadataBuilder
except ImportError:
    # Handle case when run as script
    from crs_utils import CRSDetector, CoordinateTransformer
    from metadata_extractor import MetadataExtractor, STACMetadataBuilder

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def get_coordinate_arrays(ds: xr.Dataset) -> Tuple[Optional[np.ndarray], Optional[np.ndarray]]:
    """
    Find and extract x/y or lon/lat coordinate variables from dataset.
    
    Handles various dimension names commonly used in NetCDF files:
    - Geographic: lon/longitude, lat/latitude
    - Projected: x, y
    - Other variants: X, Y, LON, LAT
    
    Args:
        ds: xarray Dataset to extract coordinates from
        
    Returns:
        Tuple of (x_coords, y_coords) as numpy arrays, or (None, None) if not found
    """
    # Try common coordinate variable names
    x_names = ['x', 'X', 'lon', 'longitude', 'LON', 'LONGITUDE']
    y_names = ['y', 'Y', 'lat', 'latitude', 'LAT', 'LATITUDE']
    
    x_coords = None
    y_coords = None
    
    # Look for x coordinate
    for name in x_names:
        if name in ds.coords:
            x_coords = ds.coords[name].values
            logger.debug(f"Found x coordinate: {name}")
            break
        elif name in ds.variables:
            x_coords = ds[name].values
            logger.debug(f"Found x coordinate in variables: {name}")
            break
    
    # Look for y coordinate
    for name in y_names:
        if name in ds.coords:
            y_coords = ds.coords[name].values
            logger.debug(f"Found y coordinate: {name}")
            break
        elif name in ds.variables:
            y_coords = ds[name].values
            logger.debug(f"Found y coordinate in variables: {name}")
            break
    
    if x_coords is None:
        logger.debug(f"X coordinate not found. Tried: {x_names}")
    if y_coords is None:
        logger.debug(f"Y coordinate not found. Tried: {y_names}")
    
    return x_coords, y_coords


def sample_coordinates(coords: np.ndarray, max_samples: int = 1000) -> np.ndarray:
    """
    Sample coordinates uniformly if array is large.
    
    For large coordinate arrays (> 10,000 points), sampling provides
    a good approximation of the bounds while being much faster.
    
    Args:
        coords: Coordinate array to sample
        max_samples: Maximum number of samples to take
        
    Returns:
        Sampled coordinate array (or original if small enough)
    """
    # Flatten array in case it's multi-dimensional
    coords_flat = coords.flatten()
    
    if len(coords_flat) <= 10000:
        # Small enough, use all points
        return coords_flat
    
    # Sample uniformly
    indices = np.linspace(0, len(coords_flat) - 1, max_samples, dtype=int)
    sampled = coords_flat[indices]
    
    logger.info(f"Sampled {max_samples} points from {len(coords_flat)} coordinates")
    return sampled


def add_sampling_buffer(bbox: List[float], buffer_percent: float = 0.1) -> List[float]:
    """
    Add a small buffer to bounding box to account for sampling error.
    
    Args:
        bbox: Bounding box [west, south, east, north]
        buffer_percent: Buffer size as percentage of extent (default 0.1%)
        
    Returns:
        Buffered bounding box
    """
    west, south, east, north = bbox
    
    # Calculate buffer sizes
    lon_extent = east - west
    lat_extent = north - south
    
    lon_buffer = lon_extent * (buffer_percent / 100.0)
    lat_buffer = lat_extent * (buffer_percent / 100.0)
    
    # Apply buffer
    buffered = [
        west - lon_buffer,
        south - lat_buffer,
        east + lon_buffer,
        north + lat_buffer
    ]
    
    # Clamp to valid geographic ranges
    buffered[0] = max(buffered[0], -180.0)  # west
    buffered[1] = max(buffered[1], -90.0)   # south
    buffered[2] = min(buffered[2], 180.0)   # east
    buffered[3] = min(buffered[3], 90.0)    # north
    
    logger.debug(f"Added {buffer_percent}% buffer to bbox: {bbox} -> {buffered}")
    return buffered


def handle_antimeridian(bbox: List[float]) -> List[float]:
    """
    Handle antimeridian crossing in bounding box.
    
    If the bounding box crosses the antimeridian (180/-180 longitude line),
    adjust the coordinates appropriately.
    
    Args:
        bbox: Bounding box [west, south, east, north]
        
    Returns:
        Adjusted bounding box
    """
    west, south, east, north = bbox
    
    # Check if bbox crosses antimeridian (west > east)
    if west > east:
        logger.info(f"Detected antimeridian crossing: west={west}, east={east}")
        # For STAC, we represent this as spanning from west to 180, and -180 to east
        # But for a single bbox, we use the convention of keeping west > east
        # Most systems handle this correctly
        pass
    
    return bbox


def handle_polar_regions(bbox: List[float]) -> List[float]:
    """
    Handle polar region edge cases in bounding box.
    
    Ensures latitude values are within valid range [-90, 90].
    
    Args:
        bbox: Bounding box [west, south, east, north]
        
    Returns:
        Adjusted bounding box
    """
    west, south, east, north = bbox
    
    # Clamp latitude to valid range
    if south < -90 or north > 90:
        logger.info(f"Clamping polar coordinates: south={south}, north={north}")
        south = max(south, -90.0)
        north = min(north, 90.0)
    
    return [west, south, east, north]


def extract_bounding_box(ds: xr.Dataset) -> Tuple[List[float], bool]:
    """
    Extract bounding box from NetCDF dataset with CRS detection and transformation.
    
    This function implements a multi-strategy approach:
    1. Detect CRS from metadata (if projected, transform to WGS84)
    2. Try coordinate variables (lon/lat or x/y)
    3. Try global attributes
    4. Fall back to global extent
    
    For projected CRS, coordinates are transformed to WGS84 (EPSG:4326).
    For large coordinate arrays, sampling is used for efficiency.
    
    Args:
        ds: xarray Dataset to extract bounding box from
        
    Returns:
        Tuple of (bbox, is_default) where:
        - bbox is [west, south, east, north] in decimal degrees (WGS84)
        - is_default is True if fallback was used, False otherwise
    """
    try:
        # Step 1: Try to detect CRS
        detector = CRSDetector()
        crs = detector.detect_crs(ds)
        
        if crs is not None:
            logger.info(f"Detected CRS: {crs.to_string()}")
            
            # Check if CRS is projected (not geographic)
            if not crs.is_geographic:
                logger.info(f"Detected projected CRS: {crs.name}")
                
                # Get coordinate arrays
                x_coords, y_coords = get_coordinate_arrays(ds)
                
                if x_coords is not None and y_coords is not None:
                    # Sample coordinates if arrays are large
                    x_sampled = sample_coordinates(x_coords)
                    y_sampled = sample_coordinates(y_coords)
                    
                    # Get bounds from sampled coordinates
                    x_min, x_max = float(x_sampled.min()), float(x_sampled.max())
                    y_min, y_max = float(y_sampled.min()), float(y_sampled.max())
                    
                    logger.info(
                        f"Original projected bounds: "
                        f"x=[{x_min}, {x_max}], y=[{y_min}, {y_max}]"
                    )
                    
                    # Transform to WGS84
                    try:
                        transformer = CoordinateTransformer(crs)
                        lon_min, lat_min, lon_max, lat_max = transformer.transform_bounds(
                            x_min, y_min, x_max, y_max
                        )
                        
                        bbox = [lon_min, lat_min, lon_max, lat_max]
                        
                        # Add buffer if coordinates were sampled
                        if len(x_coords.flatten()) > 10000 or len(y_coords.flatten()) > 10000:
                            bbox = add_sampling_buffer(bbox)
                        
                        # Handle special cases
                        bbox = handle_antimeridian(bbox)
                        bbox = handle_polar_regions(bbox)
                        
                        logger.info(
                            f"Transformed bounds to WGS84: {bbox}"
                        )
                        logger.info(
                            f"CRS details - Source: {crs.name}, Target: WGS84"
                        )
                        
                        return bbox, False
                        
                    except Exception as e:
                        # Log detailed transformation error with diagnostic info
                        logger.error("=" * 60)
                        logger.error("COORDINATE TRANSFORMATION FAILED")
                        logger.error(f"Error: {e}")
                        logger.error(f"CRS Name: {crs.name}")
                        logger.error(f"CRS String: {crs.to_string()}")
                        try:
                            epsg = crs.to_epsg()
                            if epsg:
                                logger.error(f"EPSG Code: {epsg}")
                        except Exception:
                            logger.error("EPSG Code: Not available")
                        logger.error(f"Original bounds: x=[{x_min}, {x_max}], y=[{y_min}, {y_max}]")
                        logger.error(f"Coordinate array sizes: x={len(x_coords.flatten())}, y={len(y_coords.flatten())}")
                        logger.error("Falling back to alternative methods")
                        logger.error("=" * 60)
                        # Fall through to try other methods
                else:
                    # Log detailed information about missing coordinates
                    missing_coords = []
                    if x_coords is None:
                        missing_coords.append('x')
                    if y_coords is None:
                        missing_coords.append('y')
                    
                    logger.warning("=" * 60)
                    logger.warning("COORDINATE VARIABLES NOT FOUND")
                    logger.warning(f"Projected CRS detected: {crs.name}")
                    logger.warning(f"Missing coordinate dimensions: {', '.join(missing_coords)}")
                    logger.warning(f"Available variables: {list(ds.variables.keys())}")
                    logger.warning(f"Available coordinates: {list(ds.coords.keys())}")
                    logger.warning("Cannot transform coordinates without coordinate arrays")
                    logger.warning("=" * 60)
            else:
                logger.info(f"Detected geographic CRS: {crs.name}, using coordinates directly")
        else:
            logger.debug("No CRS detected, trying coordinate variables")
        
        # Step 2: Try geographic coordinate variables (existing logic)
        if 'lon' in ds.coords and 'lat' in ds.coords:
            lon = ds.coords['lon'].values
            lat = ds.coords['lat'].values
            
            # Sample if large
            lon_sampled = sample_coordinates(lon)
            lat_sampled = sample_coordinates(lat)
            
            bbox = [
                float(lon_sampled.min()),
                float(lat_sampled.min()),
                float(lon_sampled.max()),
                float(lat_sampled.max())
            ]
            
            # Add buffer if sampled
            if len(lon.flatten()) > 10000 or len(lat.flatten()) > 10000:
                bbox = add_sampling_buffer(bbox)
            
            # Handle special cases
            bbox = handle_antimeridian(bbox)
            bbox = handle_polar_regions(bbox)
            
            logger.info(f"Extracted bounding box from coordinate variables: {bbox}")
            return bbox, False
        
        # Try alternative coordinate names
        x_coords, y_coords = get_coordinate_arrays(ds)
        if x_coords is not None and y_coords is not None:
            # Assume these are geographic if no CRS was detected
            x_sampled = sample_coordinates(x_coords)
            y_sampled = sample_coordinates(y_coords)
            
            bbox = [
                float(x_sampled.min()),
                float(y_sampled.min()),
                float(x_sampled.max()),
                float(y_sampled.max())
            ]
            
            # Add buffer if sampled
            if len(x_coords.flatten()) > 10000 or len(y_coords.flatten()) > 10000:
                bbox = add_sampling_buffer(bbox)
            
            # Handle special cases
            bbox = handle_antimeridian(bbox)
            bbox = handle_polar_regions(bbox)
            
            logger.info(f"Extracted bounding box from coordinate arrays: {bbox}")
            return bbox, False
        
        # Step 3: Try global attributes
        required_attrs = [
            'geospatial_lon_min',
            'geospatial_lat_min',
            'geospatial_lon_max',
            'geospatial_lat_max'
        ]
        if all(attr in ds.attrs for attr in required_attrs):
            bbox = [
                float(ds.attrs['geospatial_lon_min']),
                float(ds.attrs['geospatial_lat_min']),
                float(ds.attrs['geospatial_lon_max']),
                float(ds.attrs['geospatial_lat_max'])
            ]
            
            # Handle special cases
            bbox = handle_antimeridian(bbox)
            bbox = handle_polar_regions(bbox)
            
            logger.info(f"Extracted bounding box from global attributes: {bbox}")
            return bbox, False
            
    except Exception as e:
        logger.error("=" * 60)
        logger.error("BOUNDING BOX EXTRACTION FAILED")
        logger.error(f"Error: {e}")
        logger.error("=" * 60)
        logger.warning(f"Failed to extract bounding box: {e}", exc_info=True)
    
    # Step 4: Fallback to global extent
    logger.warning("=" * 60)
    logger.warning("USING DEFAULT BOUNDING BOX")
    logger.warning("Default bbox: [-180, -90, 180, 90] (global extent)")
    logger.warning("Reason: Could not extract spatial metadata from dataset")
    logger.warning("Impact: Spatial queries may be inaccurate")
    logger.warning("Recommendation: Add CRS metadata or coordinate variables to NetCDF file")
    logger.warning("=" * 60)
    return [-180, -90, 180, 90], True


def convert_netcdf_to_zarr():
    """Convert NetCDF file from S3 to Zarr format"""

    # Get environment variables
    input_bucket = os.environ.get("INPUT_BUCKET")
    input_key = os.environ.get("INPUT_KEY")
    output_bucket = os.environ.get("OUTPUT_BUCKET")

    if not all([input_bucket, input_key, output_bucket]):
        logger.error("Missing required environment variables")
        sys.exit(1)

    logger.info(f"Starting conversion - Input: s3://{input_bucket}/{input_key}, Output bucket: {output_bucket}")

    try:
        # Initialize S3 client
        s3 = boto3.client("s3")

        # Download NetCDF file
        local_input = f"/tmp/{Path(input_key).name}"
        logger.info(f"Downloading NetCDF file to {local_input}")
        s3.download_file(input_bucket, input_key, local_input)

        # Open with xarray and extract metadata
        logger.info("Opening NetCDF dataset")
        ds = xr.open_dataset(local_input, engine="netcdf4")
        
        # Extract bounding box
        logger.info("Extracting bounding box")
        bbox, is_default = extract_bounding_box(ds)
        
        if is_default:
            logger.warning("Using default bounding box - geospatial metadata may be incomplete")
        
        # Extract scientific metadata
        logger.info("Extracting scientific metadata")
        metadata_extractor = MetadataExtractor()
        extracted_metadata = metadata_extractor.extract_all_metadata(ds, Path(input_key).name)
        
        # Build STAC metadata
        stac_builder = STACMetadataBuilder()
        stac_properties = stac_builder.build_stac_properties(extracted_metadata)
        collection_id = stac_builder.determine_collection_id(
            extracted_metadata, 
            Path(input_key).name
        )

        # Generate output key (replace .nc with .zarr)
        output_key = input_key.replace(".nc", ".zarr").replace("ingestion/", "zarr/")
        logger.info(f"Output Zarr key: {output_key}")

        # Save to Zarr format in S3 using s3fs
        logger.info("Converting to Zarr format")
        fs = s3fs.S3FileSystem()
        zarr_store = s3fs.S3Map(root=f"{output_bucket}/{output_key}", s3=fs)
        ds.to_zarr(zarr_store, mode="w")

        logger.info(f"Successfully converted to s3://{output_bucket}/{output_key}")

        # Create metadata for STAC creation
        metadata = {
            "bbox": bbox,
            "zarr_key": output_key,
            "zarr_bucket": output_bucket,
            "is_default_bbox": is_default,
            "variables": extracted_metadata.get("variables", []),
            "global_attributes": extracted_metadata.get("global_attributes", {}),
            "collections": extracted_metadata.get("collections", []),
            "stac_properties": stac_properties,
            "collection_id": collection_id,
            "temporal": extracted_metadata.get("temporal")
        }
        
        # Write metadata to S3 for STAC creator to read
        metadata_key = output_key.replace(".zarr", "_metadata.json")
        logger.info(f"Writing metadata to s3://{output_bucket}/{metadata_key}")
        s3.put_object(
            Bucket=output_bucket,
            Key=metadata_key,
            Body=json.dumps(metadata),
            ContentType="application/json"
        )

        logger.info(f"Conversion complete - Zarr: {output_key}, Metadata: {metadata_key}, BBox: {bbox}")
        
        return metadata

    except Exception as e:
        logger.error(f"Conversion failed: {str(e)}", exc_info=True)
        sys.exit(1)


if __name__ == "__main__":
    convert_netcdf_to_zarr()
