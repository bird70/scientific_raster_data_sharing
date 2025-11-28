#!/usr/bin/env python3
"""Lambda function for Zarr to COG conversion"""
import logging
from pathlib import Path

import boto3
import s3fs
import xarray as xr
import rioxarray

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def lambda_handler(event, context):
    """Lambda handler for Zarr to COG conversion"""
    try:
        zarr_bucket = event["zarr_bucket"]
        zarr_key = event["zarr_key"]
        output_bucket = event["output_bucket"]

        logger.info(f"Converting {zarr_bucket}/{zarr_key} to COG")

        # Open Zarr dataset from S3
        zarr_store = f"s3://{zarr_bucket}/{zarr_key}"
        ds = xr.open_zarr(zarr_store)

        # Generate output key
        output_key = zarr_key.replace(".zarr", ".tif").replace("zarr/", "cog/")

        # Get first data variable
        data_vars = list(ds.data_vars.keys())
        if not data_vars:
            raise ValueError("No data variables found in Zarr dataset")

        da = ds[data_vars[0]]

        # Fix conflicting fill value metadata
        if "missing_value" in da.attrs:
            da.attrs.pop("missing_value", None)
        if "missing_value" in da.encoding:
            da.encoding.pop("missing_value", None)

        # Add CRS if not present
        if not hasattr(da, "rio") or da.rio.crs is None:
            da = da.rio.write_crs("EPSG:4326")

        # Save as COG to local file
        local_output = f"/tmp/{Path(output_key).name}"
        da.rio.to_raster(local_output, driver="COG", compress="lzw")

        # Upload to S3
        s3 = boto3.client("s3")
        s3.upload_file(local_output, output_bucket, output_key)

        logger.info(f"Successfully generated COG: s3://{output_bucket}/{output_key}")

        return {
            "cog_key": output_key,
            "cog_bucket": output_bucket,
            "status": "success",
        }
    except Exception as e:
        logger.error(f"Failed: {str(e)}", exc_info=True)
        raise
