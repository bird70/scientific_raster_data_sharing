import logging
from datetime import datetime, timezone

import structlog
from fastapi import FastAPI

from .auth import require_auth
from .metrics import router as metrics_router
from .stac_lookup import stac_search_collections
from .tiles import router as tiles_router
from .timeseries import router as ts_router


def configure_logging():
    logging.basicConfig(level=logging.INFO)
    structlog.configure(logger_factory=structlog.stdlib.LoggerFactory())


configure_logging()
app = FastAPI(
    title="Scientific Raster Data Platform",
    version="1.0.0",
    description="API for accessing scientific raster data via tiles and timeseries",
    docs_url="/docs",
    openapi_url="/openapi.json",
)

app.include_router(tiles_router)
app.include_router(ts_router)
app.include_router(metrics_router)


@app.get("/health")
async def health():
    try:
        collections = stac_search_collections()
        return {
            "status": "healthy",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "collections_count": len(collections),
        }
    except Exception as e:
        return {
            "status": "degraded",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "error": str(e),
        }


@app.get("/api/collections")
def get_collections():
    """Get available STAC collections"""
    try:
        collections = stac_search_collections()
        return {"collections": collections}
    except Exception as e:
        return {"collections": [], "error": str(e)}


@app.get("/api/variables")
def get_variables():
    """Get available variables from all collections"""
    try:
        from .stac_lookup import get_available_variables

        variables = get_available_variables()
        return {"variables": variables}
    except Exception as e:
        return {"variables": [], "error": str(e)}


@app.get("/")
def root():
    return {
        "title": "Scientific Raster Data Platform",
        "description": "API for accessing scientific raster data",
        "version": "1.0.0",
        "endpoints": {
            "health": "/health",
            "docs": "/docs",
            "metrics": "/metrics",
            "collections": "/api/collections",
            "variables": "/api/variables",
            "timeseries": "/api/timeseries",
            "tiles": "/tiles/{collection}/{z}/{x}/{y}.png",
        },
    }
