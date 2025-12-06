#!/usr/bin/env python3
"""
COG Generator for converting Zarr to Cloud Optimized GeoTIFF in ECS tasks
"""
import logging
import os
import sys
from pathlib import Path as PathlibPath

import boto3
import rioxarray
import xarray as xr

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def generate_cog():
    """Generate Cloud Optimized GeoTIFF from Zarr data"""

    # Get environment variables
    zarr_bucket = os.environ.get("ZARR_BUCKET")
    zarr_key = os.environ.get("ZARR_KEY")
    input_key = os.environ.get("INPUT_KEY")
    output_bucket = os.environ.get("OUTPUT_BUCKET")

    # Compute zarr_key from input_key if not provided
    if not zarr_key and input_key:
        filename = input_key.split("/")[-1]
        zarr_filename = filename.replace(".nc", ".zarr")
        zarr_key = f"zarr/{zarr_filename}"
        logger.info(f"Computed zarr_key from input_key: {zarr_key}")

    # LOCAL MODE: Only allowed if explicitly requested (for local testing)
    local_mode = not zarr_bucket or not output_bucket
    if local_mode:
        # Check for ECS/production environment
        running_in_ecs = os.environ.get("ECS_CONTAINER_METADATA_URI") or os.environ.get(
            "AWS_EXECUTION_ENV"
        )
        if running_in_ecs:
            logger.error(
                "Local mode is not allowed in ECS or production environments. Please set ZARR_BUCKET and OUTPUT_BUCKET."
            )
            sys.exit(1)
        if not zarr_key:
            logger.error("Missing ZARR_KEY for local mode.")
            sys.exit(1)
        logger.warning(
            "COG generator running in LOCAL mode: using direct file paths. This is ONLY for local testing. Zarr=%s",
            zarr_key,
        )
    else:
        if not all([zarr_bucket, zarr_key, output_bucket]):
            logger.error(
                "Missing required environment variables: ZARR_BUCKET, ZARR_KEY (or INPUT_KEY), OUTPUT_BUCKET"
            )
            sys.exit(1)
        logger.info(f"Generating COG from {zarr_bucket}/{zarr_key}")

    try:
        # Open Zarr dataset
        if local_mode:
            ds = xr.open_zarr(zarr_key)
            output_key = zarr_key.replace(".zarr", ".tif")
            local_output = output_key
        else:
            zarr_store = f"s3://{zarr_bucket}/{zarr_key}"
            ds = xr.open_zarr(zarr_store)
            output_key = zarr_key.replace(".zarr", ".tif").replace("zarr/", "cog/")
            import tempfile

            temp_dir = tempfile.gettempdir()
            local_output = os.path.join(temp_dir, PathlibPath(output_key).name)

        # Convert to COG format
        data_vars = list(ds.data_vars.keys())
        if not data_vars:
            raise ValueError("No data variables found in Zarr dataset")

        da = ds[data_vars[0]]

        # If data has a time dimension, select the latest time slice for COG
        time_dims = ["time", "Time", "TIME", "t", "T"]
        time_dim = None
        for dim in time_dims:
            if dim in da.dims:
                time_dim = dim
                break

        if time_dim:
            latest_time_idx = da.sizes[time_dim] - 1
            logger.info(
                f"Dataset has time dimension '{time_dim}' with {da.sizes[time_dim]} time steps. Selecting latest time slice (index {latest_time_idx}) for COG."
            )
            da = da.isel({time_dim: latest_time_idx})

        # Fix conflicting fill value metadata
        if "missing_value" in da.attrs:
            da.attrs.pop("missing_value", None)
        if "missing_value" in da.encoding:
            da.encoding.pop("missing_value", None)

        # Normalize dimension names to x/y for rioxarray compatibility
        dim_mapping = {}
        y_variants = [
            "lat",
            "latitude",
            "Lat",
            "Latitude",
            "LAT",
            "LATITUDE",
            "y_coord",
            "northing",
        ]
        x_variants = [
            "lon",
            "longitude",
            "Lon",
            "Longitude",
            "LON",
            "LONGITUDE",
            "x_coord",
            "easting",
        ]
        if "y" not in da.dims:
            for dim in da.dims:
                if dim in y_variants:
                    dim_mapping[dim] = "y"
                    break
        if "x" not in da.dims:
            for dim in da.dims:
                if dim in x_variants:
                    dim_mapping[dim] = "x"
                    break
        if dim_mapping:
            logger.info(
                f"Renaming dimensions for rioxarray compatibility: {dim_mapping}"
            )
            da = da.rename(dim_mapping)

        # Transpose dimensions to expected order if needed
        if "time" in da.dims and "y" in da.dims and "x" in da.dims:
            expected_order = ("time", "y", "x")
            if da.dims != expected_order:
                logger.info(
                    f"Transposing dimensions from {da.dims} to {expected_order}"
                )
                da = da.transpose(*expected_order)
        elif "y" in da.dims and "x" in da.dims:
            expected_order = ("y", "x")
            if da.dims != expected_order:
                logger.info(
                    f"Transposing dimensions from {da.dims} to {expected_order}"
                )
                da = da.transpose(*expected_order)

        # Use CRSDetector to detect CRS from Zarr dataset
        # Import using relative path for ECS execution context
        script_dir = PathlibPath(__file__).parent
        if str(script_dir) not in sys.path:
            sys.path.insert(0, str(script_dir))
        from crs_utils import CRSDetector

        detector = CRSDetector()
        crs = detector.detect_crs(ds)
        if crs is not None:
            logger.info(f"Writing detected CRS to COG: {crs.to_string()}")
            da = da.rio.write_crs(crs.to_string())
        else:
            logger.warning("No CRS detected, defaulting to WGS84 (EPSG:4326)")
            da = da.rio.write_crs("EPSG:4326")

        # Save as COG
        da.rio.to_raster(local_output, driver="COG", compress="lzw")

        if not local_mode:
            # Upload to S3
            s3 = boto3.client("s3")
            s3.upload_file(local_output, output_bucket, output_key)
            logger.info(
                f"Successfully generated COG: s3://{output_bucket}/{output_key}"
            )
            # Clean up local file
            os.remove(local_output)
            return {
                "cog_key": output_key,
                "cog_bucket": output_bucket,
                "status": "success",
            }
        else:
            logger.info(f"Successfully generated local COG: {local_output}")
            return {"cog_key": local_output, "cog_bucket": None, "status": "success"}

    except Exception as e:
        logger.error(f"COG generation failed: {str(e)}", exc_info=True)
        sys.exit(1)


if __name__ == "__main__":
    generate_cog()
