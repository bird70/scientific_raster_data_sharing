import logging
import os
from datetime import datetime, timezone
from typing import List, Optional

import structlog
from fastapi import FastAPI, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from .export import router as export_router
from .metrics import router as metrics_router
from .stac_lookup import stac_client, stac_search_collections
from .tiles import router as tiles_router
from .timeseries import router as ts_router


def configure_logging():
    logging.basicConfig(level=logging.INFO)
    structlog.configure(logger_factory=structlog.stdlib.LoggerFactory())


configure_logging()


# Response models for API endpoints
class SearchResponse(BaseModel):
    """Response model for STAC search endpoint"""

    items: List[dict]
    total: int
    limit: int
    offset: int


class CollectionsResponse(BaseModel):
    """Response model for collections endpoint"""

    collections: List[str]


class VariablesResponse(BaseModel):
    """Response model for variables endpoint"""

    variables: List[dict]


app = FastAPI(
    title="Scientific Raster Data Platform",
    version="1.0.0",
    description=("API for accessing scientific raster data via tiles and timeseries"),
    docs_url="/docs",
    openapi_url="/openapi.json",
)

# Configure CORS for frontend - TEMPORARY: Allow all origins for debugging
logging.info(f"FRONTEND_WEBSITE_ENDPOINT: {os.getenv('FRONTEND_WEBSITE_ENDPOINT')}")
logging.info(f"ALB_DOMAIN: {os.getenv('ALB_DOMAIN')}")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # TEMPORARY: Allow all origins
    allow_credentials=False,  # Must be False when using wildcard
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["*"],
    expose_headers=["*"],
    max_age=3600,
)

app.include_router(tiles_router)
app.include_router(ts_router)
app.include_router(export_router)
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


@app.get("/api/search", response_model=SearchResponse)
async def search_datasets(
    start_date: Optional[str] = Query(
        None, description="Start date in ISO 8601 format"
    ),
    end_date: Optional[str] = Query(None, description="End date in ISO 8601 format"),
    bbox: Optional[str] = Query(
        None, description="Bounding box as 'minx,miny,maxx,maxy'"
    ),
    variables: Optional[List[str]] = Query(
        None, description="List of variable names to filter by"
    ),
    collections: Optional[List[str]] = Query(
        None, description="List of collection names to filter by"
    ),
    limit: int = Query(
        50, ge=1, le=100, description="Maximum number of results to return"
    ),
    offset: int = Query(
        0, ge=0, description="Number of results to skip for pagination"
    ),
) -> SearchResponse:
    """
    Search STAC catalog with filters.

    This endpoint allows searching for datasets using various filters:
    - Temporal: start_date and end_date
    - Spatial: bbox (bounding box)
    - Attribute: variables and collections

    Returns paginated results with metadata.
    """
    try:
        items = []

        # Parse bbox if provided
        bbox_list = None
        if bbox:
            try:
                bbox_list = [float(x) for x in bbox.split(",")]
                if len(bbox_list) != 4:
                    raise ValueError("bbox must have exactly 4 values")
            except (ValueError, AttributeError) as e:
                return SearchResponse(items=[], total=0, limit=limit, offset=offset)

        # Defensive: validate date range
        if start_date and end_date:
            try:
                start_dt = start_date
                end_dt = end_date
                # If ISO strings, parse to datetime
                from dateutil.parser import isoparse

                start_dt = isoparse(start_date)
                end_dt = isoparse(end_date)
                if start_dt > end_dt:
                    from fastapi.responses import JSONResponse

                    return JSONResponse(
                        status_code=400,
                        content={
                            "detail": "Start date must be before or equal to end date."
                        },
                    )
            except Exception:
                pass
        if bbox_list:
            # Spatial search with optional temporal and collection filters
            items = stac_client.search_by_bbox(
                bbox=bbox_list,
                collections=collections,
                start_datetime=start_date,
                end_datetime=end_date,
                limit=limit + offset,  # Get more to handle offset
            )
        elif collections and len(collections) == 1:
            # Single collection search with optional temporal filter
            items = stac_client.search_by_collection(
                collection=collections[0],
                start_datetime=start_date,
                end_datetime=end_date,
                limit=limit + offset,
            )
        elif start_date and end_date:
            # Temporal search with optional collection filter
            items = stac_client.search_by_datetime(
                start_datetime=start_date,
                end_datetime=end_date,
                collections=collections,
                limit=limit + offset,
            )
        elif collections:
            # Multiple collections - query each and combine
            for collection in collections:
                collection_items = stac_client.search_by_collection(
                    collection=collection,
                    start_datetime=start_date,
                    end_datetime=end_date,
                    limit=limit + offset,
                )
                items.extend(collection_items)
        else:
            # No filters - return empty for now (could implement full scan if needed)
            # Full table scan would be expensive, so we require at least one filter
            return SearchResponse(items=[], total=0, limit=limit, offset=offset)

        # Filter by variables if specified
        if variables:
            items = [
                item
                for item in items
                if any(
                    var in item.get("properties", {}).get("variables", [])
                    or item.get("properties", {}).get("variable") == var
                    for var in variables
                )
            ]

        # Apply pagination
        total = len(items)
        paginated_items = items[offset : offset + limit]

        return SearchResponse(
            items=paginated_items, total=total, limit=limit, offset=offset
        )

    except Exception as e:
        logging.error(f"Error in search endpoint: {e}", exc_info=True)
        return SearchResponse(items=[], total=0, limit=limit, offset=offset)


@app.get("/api/collections", response_model=CollectionsResponse)
def get_collections():
    """Get available STAC collections"""
    try:
        collections = stac_search_collections()
        return {"collections": collections}
    except Exception as e:
        return {"collections": [], "error": str(e)}


@app.get("/api/collections/{collection_id}/variables")
async def get_collection_variables(collection_id: str):
    """
    Get available variables for a specific collection.

    Queries DynamoDB for all items in the collection and extracts
    unique variables with their metadata.

    Args:
        collection_id: The collection identifier

    Returns:
        List of variables with metadata (name, units, description)
    """
    try:
        # Query all items in the collection
        items = stac_client.search_by_collection(
            collection=collection_id,
            limit=1000,  # Get enough items to find all variables
        )

        # Extract unique variables from items
        variables_dict = {}

        for item in items:
            properties = item.get("properties", {})

            # Handle both single variable and multiple variables formats
            # Some items have 'variable' (string), others have 'variables' (list)
            item_variables = []
            if "variable" in properties:
                item_variables = [properties["variable"]]
            elif "variables" in properties:
                item_variables = properties.get("variables", [])

            # Extract metadata for each variable
            for var_name in item_variables:
                if var_name not in variables_dict:
                    # Try to get variable metadata from properties
                    var_metadata = properties.get("variable_metadata", {}).get(
                        var_name, {}
                    )

                    variables_dict[var_name] = {
                        "name": var_name,
                        "units": var_metadata.get(
                            "units", properties.get("units", "unknown")
                        ),
                        "long_name": var_metadata.get("long_name", var_name),
                        "description": var_metadata.get("description", ""),
                        "count": 1,
                    }
                else:
                    # Increment count if we've seen this variable before
                    variables_dict[var_name]["count"] += 1

        # Convert to list and sort by name
        variables_list = sorted(variables_dict.values(), key=lambda x: x["name"])

        return {
            "collection": collection_id,
            "variables": variables_list,
            "total": len(variables_list),
        }

    except Exception as e:
        logging.error(
            f"Error getting variables for collection {collection_id}: {e}",
            exc_info=True,
        )
        return {
            "collection": collection_id,
            "variables": [],
            "total": 0,
            "error": str(e),
        }


@app.get("/api/variables", response_model=VariablesResponse)
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
