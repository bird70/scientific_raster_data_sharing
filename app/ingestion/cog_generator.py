#!/usr/bin/env python3
"""
COG Generator for converting Zarr to Cloud Optimized GeoTIFF in ECS tasks
"""
import os
import sys
import logging
import boto3
import xarray as xr
import rioxarray
from pathlib import Path

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def generate_cog():
    """Generate Cloud Optimized GeoTIFF from Zarr data"""
    
    # Get environment variables
    zarr_bucket = os.environ.get('ZARR_BUCKET')
    zarr_key = os.environ.get('ZARR_KEY')
    input_key = os.environ.get('INPUT_KEY')
    output_bucket = os.environ.get('OUTPUT_BUCKET')
    
    # Compute zarr_key from input_key if not provided
    if not zarr_key and input_key:
        # Transform ingestion/file.nc -> zarr/file.zarr
        filename = input_key.split('/')[-1]  # Get last part
        zarr_filename = filename.replace('.nc', '.zarr')
        zarr_key = f'zarr/{zarr_filename}'
        logger.info(f"Computed zarr_key from input_key: {zarr_key}")
    
    if not all([zarr_bucket, zarr_key, output_bucket]):
        logger.error("Missing required environment variables: ZARR_BUCKET, ZARR_KEY (or INPUT_KEY), OUTPUT_BUCKET")
        sys.exit(1)
    
    logger.info(f"Generating COG from {zarr_bucket}/{zarr_key}")
    
    try:
        # Open Zarr dataset from S3
        zarr_store = f"s3://{zarr_bucket}/{zarr_key}"
        ds = xr.open_zarr(zarr_store)
        
        # Generate output key (replace .zarr with .tif)
        output_key = zarr_key.replace('.zarr', '.tif').replace('zarr/', 'cog/')
        
        # Convert to COG format
        # For simplicity, take the first data variable if multiple exist
        data_vars = list(ds.data_vars.keys())
        if not data_vars:
            raise ValueError("No data variables found in Zarr dataset")
        
        # Select first data variable and ensure it has spatial dimensions
        da = ds[data_vars[0]]
        
        # If data has a time dimension, select the latest time slice for COG
        # (COGs are 2D, so we can't include the full time series)
        time_dims = ['time', 'Time', 'TIME', 't', 'T']
        time_dim = None
        for dim in time_dims:
            if dim in da.dims:
                time_dim = dim
                break
        
        if time_dim:
            latest_time_idx = da.sizes[time_dim] - 1
            logger.info(f"Dataset has time dimension '{time_dim}' with {da.sizes[time_dim]} time steps. Selecting latest time slice (index {latest_time_idx}) for COG.")
            da = da.isel({time_dim: latest_time_idx})
        
        # Fix conflicting fill value metadata
        if 'missing_value' in da.attrs:
            da.attrs.pop('missing_value', None)
        if 'missing_value' in da.encoding:
            da.encoding.pop('missing_value', None)
        
        # Normalize dimension names to x/y for rioxarray compatibility
        # Check common variations (case-insensitive)
        dim_mapping = {}
        
        # Common Y-axis dimension names
        y_variants = ['lat', 'latitude', 'Lat', 'Latitude', 'LAT', 'LATITUDE', 'y_coord', 'northing']
        # Common X-axis dimension names
        x_variants = ['lon', 'longitude', 'Lon', 'Longitude', 'LON', 'LONGITUDE', 'x_coord', 'easting']
        
        # Find and map Y dimension
        if 'y' not in da.dims:
            for dim in da.dims:
                if dim in y_variants:
                    dim_mapping[dim] = 'y'
                    break
        
        # Find and map X dimension
        if 'x' not in da.dims:
            for dim in da.dims:
                if dim in x_variants:
                    dim_mapping[dim] = 'x'
                    break
        
        if dim_mapping:
            logger.info(f"Renaming dimensions for rioxarray compatibility: {dim_mapping}")
            da = da.rename(dim_mapping)
        
        # Transpose dimensions to expected order if needed
        # rioxarray expects: (time, y, x) or (y, x) for 2D data
        if 'time' in da.dims and 'y' in da.dims and 'x' in da.dims:
            expected_order = ('time', 'y', 'x')
            if da.dims != expected_order:
                logger.info(f"Transposing dimensions from {da.dims} to {expected_order}")
                da = da.transpose(*expected_order)
        elif 'y' in da.dims and 'x' in da.dims:
            expected_order = ('y', 'x')
            if da.dims != expected_order:
                logger.info(f"Transposing dimensions from {da.dims} to {expected_order}")
                da = da.transpose(*expected_order)
        
        # Add CRS if not present (assuming WGS84 for now)
        if not hasattr(da, 'rio') or da.rio.crs is None:
            da = da.rio.write_crs("EPSG:4326")
        
        # Save as COG to local file first
        import tempfile
        temp_dir = tempfile.gettempdir()
        local_output = os.path.join(temp_dir, Path(output_key).name)
        da.rio.to_raster(local_output, driver="COG", compress="lzw")
        
        # Upload to S3
        s3 = boto3.client('s3')
        s3.upload_file(local_output, output_bucket, output_key)
        
        logger.info(f"Successfully generated COG: s3://{output_bucket}/{output_key}")
        
        # Clean up local file
        os.remove(local_output)
        
        # Return result for Step Functions
        return {
            "cog_key": output_key,
            "cog_bucket": output_bucket,
            "status": "success"
        }
        
    except Exception as e:
        logger.error(f"COG generation failed: {str(e)}", exc_info=True)
        sys.exit(1)

if __name__ == "__main__":
    generate_cog()