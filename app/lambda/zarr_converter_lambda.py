#!/usr/bin/env python3
"""Lambda function for NetCDF to Zarr conversion"""
import json
import logging
from pathlib import Path

import boto3
import s3fs
import xarray as xr
import zarr

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def lambda_handler(event, context):
    """Lambda handler for NetCDF to Zarr conversion"""
    try:
        input_bucket = event["bucket"]
        input_key = event["key"]
        output_bucket = event["output_bucket"]

        logger.info(f"Converting {input_bucket}/{input_key}")

        s3 = boto3.client("s3")
        local_input = f"/tmp/{Path(input_key).name}"
        s3.download_file(input_bucket, input_key, local_input)

        ds = xr.open_dataset(local_input, engine="netcdf4")
        output_key = input_key.replace(".nc", ".zarr").replace("ingestion/", "zarr/")

        fs = s3fs.S3FileSystem()
        zarr_store = s3fs.S3Map(root=f"{output_bucket}/{output_key}", s3=fs)
        ds.to_zarr(zarr_store, mode="w")

        return {
            "zarr_key": output_key,
            "zarr_bucket": output_bucket,
            "status": "success",
        }
    except Exception as e:
        logger.error(f"Failed: {str(e)}", exc_info=True)
        raise
