from opensearchpy import OpenSearch, RequestsHttpConnection
from .config import settings
from tenacity import retry, stop_after_attempt, wait_exponential
import logging

logger = logging.getLogger(__name__)

# Initialize the appropriate STAC client based on configuration
def _initialize_stac_client():
    """
    Initialize the STAC client based on STAC_BACKEND configuration.
    
    Returns:
        Appropriate STAC client instance (OpenSearch, DynamoDB, or Dual)
    """
    backend = settings.STAC_BACKEND.lower()
    
    if backend == "dynamodb":
        from .stac_lookup_dynamodb import DynamoDBSTACClient
        logger.info("Initializing DynamoDB STAC client")
        return DynamoDBSTACClient(
            table_name=settings.DYNAMODB_STAC_TABLE,
            region_name=settings.AWS_REGION
        )
    
    elif backend == "dual":
        from .stac_lookup_dual import DualBackendSTACClient
        logger.info("Initializing Dual Backend STAC client")
        return DualBackendSTACClient(
            dynamodb_table_name=settings.DYNAMODB_STAC_TABLE,
            opensearch_host=settings.OPENSEARCH_HOST,
            opensearch_index=settings.OPENSEARCH_INDEX,
            region_name=settings.AWS_REGION
        )
    
    else:  # Default to opensearch
        logger.info("Initializing OpenSearch STAC client (legacy)")
        return _make_opensearch_client()

@retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=0.5))
def _make_opensearch_client():
    """Create legacy OpenSearch client with retry logic."""
    host = settings.OPENSEARCH_HOST
    return OpenSearch(
        hosts=[{"host": host, "port": 443}],
        use_ssl=True,
        verify_certs=True,
        connection_class=RequestsHttpConnection,
        http_auth=None
    )

# Initialize the client based on configuration
stac_client = _initialize_stac_client()

# For backward compatibility, keep the old 'client' variable for OpenSearch-only mode
if settings.STAC_BACKEND.lower() == "opensearch":
    client = stac_client
else:
    client = None  # Not used in DynamoDB or dual mode

def make_client():
    """
    Create a new STAC client instance.
    
    This function is provided for backward compatibility with code that
    expects to call make_client(). New code should use the stac_client
    module variable directly.
    
    Returns:
        Appropriate STAC client instance based on STAC_BACKEND configuration
    """
    return _initialize_stac_client()

def stac_search_point(variable: str, lon: float, lat: float, start: str, end: str, size: int = 100):
    """
    Search for STAC items by point location and variable.
    
    This function works with both OpenSearch and DynamoDB backends.
    For DynamoDB, it uses a small bounding box around the point.
    """
    # Use DynamoDB or dual backend client
    if hasattr(stac_client, 'search_by_bbox'):
        # Create a small bounding box around the point (approximately 1km radius)
        # 1km ≈ 0.009 degrees at the equator
        buffer = 0.009
        bbox = [lon - buffer, lat - buffer, lon + buffer, lat + buffer]
        
        # Search using DynamoDB client
        items = stac_client.search_by_bbox(
            bbox=bbox,
            start_datetime=start,
            end_datetime=end,
            limit=size * 2  # Get more items to filter by variable
        )
        
        # Filter by variable if present in properties
        filtered_items = []
        for item in items:
            properties = item.get('properties', {})
            
            # Check if variable is in the variables list
            variables_list = properties.get('variables', [])
            if variable in variables_list:
                # Convert to OpenSearch-like format for backward compatibility
                filtered_items.append({
                    "_source": item
                })
                if len(filtered_items) >= size:
                    break
                continue
            
            # Check variable_metadata list for matching variable name
            variable_metadata = properties.get('variable_metadata', [])
            if isinstance(variable_metadata, list):
                for var_meta in variable_metadata:
                    if isinstance(var_meta, dict):
                        if var_meta.get('name') == variable:
                            filtered_items.append({
                                "_source": item
                            })
                            break
            
            if len(filtered_items) >= size:
                break
        
        logger.info(f"DynamoDB search found {len(filtered_items)} items for variable '{variable}' at ({lon}, {lat})")
        return filtered_items
    
    # Fallback to OpenSearch for backward compatibility
    if client is None:
        raise RuntimeError("stac_search_point requires STAC_BACKEND='opensearch' or DynamoDB client")
    
    body = {
      "query": {
        "bool": {
          "must": [
            {"term": {"properties.variable.keyword": variable}},
            {"range": {"properties.start_datetime": {"lte": end}}},
            {"range": {"properties.end_datetime": {"gte": start}}},
            {"geo_distance": {"distance": "1km", "geometry": {"lat": lat, "lon": lon}}}
          ]
        }
      },
      "size": size
    }
    res = client.search(index=settings.OPENSEARCH_INDEX, body=body)
    return res.get("hits", {}).get("hits", [])

def stac_search_collections():
    """Get all available collections from STAC catalog"""
    try:
        # Use the new client interface if available
        if hasattr(stac_client, 'list_collections'):
            return stac_client.list_collections()
        
        # Fallback to OpenSearch-specific implementation
        body = {
            "aggs": {
                "collections": {
                    "terms": {
                        "field": "collection.keyword",
                        "size": 100
                    }
                }
            },
            "size": 0
        }
        res = client.search(index=settings.OPENSEARCH_INDEX, body=body)
        buckets = res.get("aggregations", {}).get("collections", {}).get("buckets", [])
        return [bucket["key"] for bucket in buckets]
    except Exception as e:
        logger.error(f"Error searching collections: {e}")
        return []

def get_available_variables():
    """
    Get all available variables from STAC catalog.
    
    Note: This function uses OpenSearch-specific aggregations and requires STAC_BACKEND="opensearch".
    """
    try:
        if client is None:
            logger.warning("get_available_variables requires STAC_BACKEND='opensearch'")
            return []
        
        body = {
            "aggs": {
                "variables": {
                    "terms": {
                        "field": "properties.variable.keyword",
                        "size": 100
                    }
                }
            },
            "size": 0
        }
        res = client.search(index=settings.OPENSEARCH_INDEX, body=body)
        buckets = res.get("aggregations", {}).get("variables", {}).get("buckets", [])
        variables = []
        for bucket in buckets:
            variables.append({
                "name": bucket["key"],
                "count": bucket["doc_count"]
            })
        return variables
    except Exception as e:
        logger.error(f"Error searching variables: {e}")
        return []