import io
import logging

import matplotlib.pyplot as plt
import numpy as np
from fastapi import APIRouter, HTTPException, Query
from rio_tiler.errors import TileOutsideBounds
from rio_tiler.io import COGReader
from starlette.responses import Response
from tenacity import retry, stop_after_attempt, wait_exponential

from .config import settings
from .stac_lookup import client, make_client

router = APIRouter()
logger = logging.getLogger("tiles")


@retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=0.5))
def lookup_cog_href(collection: str) -> str:
    # Use DynamoDB STAC client if configured
    if settings.STAC_BACKEND.lower() == "dynamodb":
        from .stac_lookup_dynamodb import DynamoDBSTACClient

        dynamo_client = DynamoDBSTACClient(table_name=settings.DYNAMODB_STAC_TABLE)
        items = dynamo_client.search_by_collection(collection, limit=1)
        if not items:
            raise HTTPException(status_code=404, detail="Collection not found")
        item = items[0]
        cog_href = item.get("assets", {}).get("cog", {}).get("href")
        if not cog_href:
            raise HTTPException(
                status_code=404, detail="COG asset not found in collection"
            )
        return cog_href
    # Legacy OpenSearch fallback (if needed)
    # q = {"query": {"bool": {"must": [{"match": {"collection": collection}}]}}}
    # res = client.search(index=settings.OPENSEARCH_INDEX, body=q, size=1)
    # hits = res.get("hits", {}).get("hits", [])
    # if not hits:
    #     raise HTTPException(status_code=404, detail="Collection not found")
    # return hits[0]["_source"]["assets"]["cog"]["href"]


@router.get("/tiles/{collection}/{z}/{x}/{y}.png")
def get_tile(
    collection: str, z: int, x: int, y: int, resampling: str = Query("bilinear")
):
    href = lookup_cog_href(collection)
    try:
        with COGReader(href) as cog:
            try:
                tile, mask = cog.tile(
                    tile_x=x, tile_y=y, tile_z=z, resampling_method=resampling
                )
            except TileOutsideBounds:
                logger.warning(
                    f"Tile ({x}, {y}, {z}) is outside bounds for asset {href}"
                )
                return Response(status_code=204)
            arr = np.moveaxis(tile, 0, -1)
            # Normalize for PNG
            arr = arr.astype(np.float32)
            arr_min, arr_max = np.nanpercentile(arr, (2, 98))
            arr = (arr - arr_min) / max(1e-6, (arr_max - arr_min))
            
            # Handle single-band (grayscale) rasters with grayscale colormap
            buf = io.BytesIO()
            if arr.ndim == 2 or (arr.ndim == 3 and arr.shape[2] == 1):
                if arr.ndim == 3:
                    arr = arr.squeeze(axis=2)
                # Use grayscale colormap for single-band data (more efficient)
                plt.imsave(buf, arr, format="png", cmap="gray", vmin=0, vmax=1)
            else:
                plt.imsave(buf, arr, format="png")
            return Response(content=buf.getvalue(), media_type="image/png")
    except Exception as exc:
        logger.exception("tile_error")
        from fastapi.responses import JSONResponse

        return JSONResponse(
            status_code=500,
            content={"error": "Tile generation failed", "detail": str(exc)},
        )


@router.get("/api/cog_metadata")
def get_cog_metadata(collection: str):
    """Return COG asset metadata (CRS, bounds, etc.) for inspection."""
    href = lookup_cog_href(collection)
    try:
        with COGReader(href) as cog:
            meta = {
                "href": href,
                "crs": str(cog.crs),
                "bounds": cog.bounds,
                "width": cog.width,
                "height": cog.height,
                "minzoom": cog.minzoom,
                "maxzoom": cog.maxzoom,
                "nodata": getattr(cog, "nodata", None),
                "dtype": str(getattr(cog, "dtypes", [None])[0]),
            }
            return meta
    except Exception as e:
        logger.error(f"cog_metadata_error: {e}")
        raise HTTPException(status_code=500, detail=str(e))
