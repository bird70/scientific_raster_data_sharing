from fastapi import APIRouter, Query, HTTPException, Depends
from .stac_lookup import stac_search_point
from .config import settings
from .cache import get_cached, set_cached
import xarray as xr
import s3fs
import numpy as np
import asyncio
from tenacity import retry, stop_after_attempt, wait_exponential
import logging
import hashlib
import json

router = APIRouter()
logger = logging.getLogger("timeseries")

# Track Dask availability
_dask_available = False
_dask_client = None

try:
    from dask.distributed import Client
    _dask_available = True
except ImportError:
    logger.warning("Dask not available - will use local processing only")

@retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=0.5))
def open_zarr_mapper(zarr_href: str):
    fs = s3fs.S3FileSystem(anon=False)
    return fs.get_mapper(zarr_href.replace("s3://", ""))

async def ensure_dask_client():
    """
    Attempt to connect to Dask scheduler if configured.
    Returns None if Dask is unavailable or connection fails.
    Processing will fall back to local execution.
    """
    global _dask_client
    
    # Return existing client if available
    if _dask_client is not None:
        return _dask_client
    
    # Check if Dask is available and configured
    if not _dask_available:
        logger.info("Dask library not available - using local processing")
        return None
    
    if not settings.DASK_SCHEDULER:
        logger.info("DASK_SCHEDULER not configured - using local processing")
        return None
    
    # Attempt to connect to Dask scheduler
    try:
        logger.info(f"Attempting to connect to Dask scheduler at {settings.DASK_SCHEDULER}")
        _dask_client = Client(settings.DASK_SCHEDULER, timeout="5s")
        logger.info("Successfully connected to Dask scheduler")
        return _dask_client
    except Exception as e:
        logger.warning(f"Failed to connect to Dask scheduler: {e}. Using local processing.")
        return None

def _make_cache_key(lon, lat, start, end, variable):
    key = f"ts:{variable}:{lon:.6f}:{lat:.6f}:{start}:{end}"
    return hashlib.sha256(key.encode("utf-8")).hexdigest()

@router.get("/api/timeseries")
async def timeseries(lon: float = Query(...), lat: float = Query(...),
                     start: str = Query(...), end: str = Query(...),
                     variable: str = Query(...)):
    cache_key = _make_cache_key(lon, lat, start, end, variable)
    cached = await get_cached(cache_key)
    if cached:
        return cached

    hits = stac_search_point(variable, lon, lat, start, end, size=200)
    if not hits:
        return {
            "times": [],
            "values": [],
            "metadata": {
                "variable": variable,
                "units": "unknown",
                "long_name": variable,
                "coordinates": {"longitude": lon, "latitude": lat},
                "temporal_extent": {"start": start, "end": end}
            }
        }

    # Attempt to connect to Dask scheduler if available
    # If Dask is unavailable, processing will fall back to local execution
    dask_client = await ensure_dask_client()
    if dask_client:
        logger.info(f"Processing {len(hits)} hits with Dask distributed computing")
    else:
        logger.info(f"Processing {len(hits)} hits with local execution")

    # Extract metadata from first hit
    metadata = {
        "variable": variable,
        "units": "unknown",
        "long_name": variable,
        "coordinates": {"longitude": lon, "latitude": lat},
        "temporal_extent": {"start": start, "end": end}
    }
    
    if hits:
        first_hit = hits[0]["_source"]
        properties = first_hit.get("properties", {})
        
        # Try to get variable metadata
        var_metadata = properties.get("variable_metadata", {}).get(variable, {})
        if var_metadata:
            metadata["units"] = var_metadata.get("units", "unknown")
            metadata["long_name"] = var_metadata.get("long_name", variable)
            metadata["description"] = var_metadata.get("description", "")
        else:
            # Fallback to top-level properties
            metadata["units"] = properties.get("units", "unknown")
            metadata["long_name"] = properties.get("long_name", variable)
        
        # Add collection info
        metadata["collection"] = first_hit.get("collection", "unknown")

    async def read_hit(hit):
        href = hit["_source"]["assets"]["zarr"]["href"]
        try:
            mapper = open_zarr_mapper(href)
            ds = xr.open_zarr(mapper, consolidated=True)
            
            # Extract units from dataset if not already set
            if variable in ds.variables:
                var_attrs = ds[variable].attrs
                if metadata["units"] == "unknown" and "units" in var_attrs:
                    metadata["units"] = var_attrs["units"]
                if metadata["long_name"] == variable and "long_name" in var_attrs:
                    metadata["long_name"] = var_attrs["long_name"]
            
            # assumes dimensions named 'time' and coords 'lon','lat' or 'x','y' — adjust per dataset
            try:
                sel = ds[variable].sel(longitude=lon, latitude=lat, method="nearest")
            except Exception:
                # try alternate names
                sel = ds[variable].sel(x=lon, y=lat, method="nearest")
            times = sel["time"].values
            values = sel.values
            
            # Convert times to ISO 8601 format
            times_iso = []
            for t in times:
                try:
                    # Convert numpy datetime64 to ISO 8601 string
                    times_iso.append(np.datetime_as_string(t, unit='s') + 'Z')
                except:
                    # Fallback to string conversion
                    times_iso.append(str(t))
            
            return times_iso, list(map(float, np.array(values).tolist()))
        except Exception as e:
            logger.error(f"Error reading hit from {href}: {e}")
            return [], []

    # Process hits concurrently using asyncio executor
    # This works with or without Dask - if Dask is available, xarray operations
    # within read_hit will use Dask for chunked array operations
    loop = asyncio.get_event_loop()
    tasks = [loop.run_in_executor(None, lambda h=hit: read_hit(h)) for hit in hits]
    results = await asyncio.gather(*tasks, return_exceptions=True)
    
    times = []
    values = []
    for result in results:
        if isinstance(result, Exception):
            logger.error(f"Error processing hit: {result}")
            continue
        t_list, v_list = result
        times.extend(t_list)
        values.extend(v_list)
    
    # sort and return
    pairs = sorted(zip(times, values), key=lambda p: p[0])
    if pairs:
        times_sorted, values_sorted = zip(*pairs)
    else:
        times_sorted, values_sorted = (), ()
    
    out = {
        "times": list(times_sorted),
        "values": list(values_sorted),
        "metadata": metadata
    }
    await set_cached(cache_key, out, ttl=600)
    return out