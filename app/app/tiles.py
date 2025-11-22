from fastapi import APIRouter, Query, HTTPException
from starlette.responses import Response
from rio_tiler.io import COGReader
from .stac_lookup import client, make_client
from .config import settings
import io
import numpy as np
import matplotlib.pyplot as plt
import logging
from tenacity import retry, stop_after_attempt, wait_exponential

router = APIRouter()
logger = logging.getLogger("tiles")

@retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=0.5))
def lookup_cog_href(collection: str) -> str:
    q = {"query": {"bool": {"must": [{"match": {"collection": collection}}]}}}
    res = client.search(index=settings.OPENSEARCH_INDEX, body=q, size=1)
    hits = res.get("hits", {}).get("hits", [])
    if not hits:
        raise HTTPException(status_code=404, detail="Collection not found")
    return hits[0]["_source"]["assets"]["cog"]["href"]

@router.get("/tiles/{collection}/{z}/{x}/{y}.png")
def get_tile(collection: str, z: int, x: int, y: int, resampling: str = Query("bilinear")):
    href = lookup_cog_href(collection)
    try:
        with COGReader(href) as cog:
            tile, mask = cog.tile(x=x, y=y, z=z, resampling_method=resampling)
            arr = np.moveaxis(tile, 0, -1)
            # Normalize for PNG
            arr = arr.astype(np.float32)
            arr_min, arr_max = np.nanpercentile(arr, (2,98))
            arr = (arr - arr_min) / max(1e-6, (arr_max - arr_min))
            buf = io.BytesIO()
            plt.imsave(buf, arr, format="png")
            return Response(content=buf.getvalue(), media_type="image/png")
    except Exception as exc:
        logger.exception("tile_error")
        raise HTTPException(status_code=500, detail="Tile generation failed")