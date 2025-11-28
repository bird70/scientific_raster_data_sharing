# Create test_cog.py
import os
import rioxarray
import xarray as xr
import sys

os.environ["AWS_PROFILE"] = "DEVcloud"

try:
    # Open zarr from S3
    ds = xr.open_zarr(
        "s3://cloud-scientific-raster-sharing-zarr-2e6c448c/zarr/test-file_MC_SST.zarr"
    )
except Exception as e:
    if "Token has expired" in str(e):
        print("AWS SSO token expired. Run: aws sso login")
        sys.exit(1)
    raise
da = ds[list(ds.data_vars.keys())[0]]

# Fix metadata
if "missing_value" in da.attrs:
    da.attrs.pop("missing_value", None)
if "missing_value" in da.encoding:
    da.encoding.pop("missing_value", None)

# Add CRS
da = da.rio.write_crs("EPSG:4326")

# Save locally
da.rio.to_raster("test_output.tif", driver="COG", compress="lzw")
print("Success!")
