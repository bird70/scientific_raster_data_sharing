from fastapi import APIRouter, Query, HTTPException, Depends
from .stac_lookup import stac_search_point
from .config import settings
from .cache import get_cached, set_cached
import xarray as xr
import s3fs
import numpy as np
import asyncio
from tenacity import retry, stop_after_attempt, wait_exponential
from dask.distributed import Client, default_client
import logging
import hashlib
import json

router = APIRouter()
logger = logging.getLogger("timeseries")

@retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=0.5))
def open_zarr_mapper(zarr_href: str):
    fs = s3fs.S3FileSystem(anon=False)
    return fs.get_mapper(zarr_href.replace("s3://", ""))

async def ensure_dask_client():
    if settings.DASK_SCHEDULER:
        try:
            return Client(settings.DASK_SCHEDULER, timeout="5s")
        except Exception as e:
            logger.warning("Dask scheduler connect failed, using local")
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
        return {"times": [], "values": []}

    dask_client = await ensure_dask_client()

    async def read_hit(hit):
        href = hit["_source"]["assets"]["zarr"]["href"]
        mapper = open_zarr_mapper(href)
        ds = xr.open_zarr(mapper, consolidated=True)
        # assumes dimensions named 'time' and coords 'lon','lat' or 'x','y' — adjust per dataset
        try:
            sel = ds[variable].sel(longitude=lon, latitude=lat, method="nearest")
        except Exception:
            # try alternate names
            sel = ds[variable].sel(x=lon, y=lat, method="nearest")
        times = sel["time"].values
        values = sel.values
        return list(map(str, times)), list(map(float, np.array(values).tolist()))

    loop = asyncio.get_event_loop()
    tasks = [loop.run_in_executor(None, lambda h=hit: read_hit(h)) for hit in hits]
    results = await asyncio.gather(*tasks)
    times = []
    values = []
    for t_list, v_list in results:
        times.extend(t_list)
        values.extend(v_list)
    # sort and return
    pairs = sorted(zip(times, values), key=lambda p: p[0])
    if pairs:
        times_sorted, values_sorted = zip(*pairs)
    else:
        times_sorted, values_sorted = (), ()
    out = {"times": list(times_sorted), "values": list(values_sorted)}
    await set_cached(cache_key, out, ttl=600)
    return out