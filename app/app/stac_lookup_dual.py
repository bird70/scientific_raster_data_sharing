"""
Dual backend STAC catalog client.

This module provides a client that supports both DynamoDB and OpenSearch backends,
enabling zero-downtime migration. It reads from DynamoDB first and falls back to
OpenSearch if the item is not found, while tracking metrics for backend usage.
"""

import logging
from typing import Optional, List, Dict
import boto3
from .stac_lookup_dynamodb import DynamoDBSTACClient
from opensearchpy import OpenSearch, RequestsHttpConnection
from tenacity import retry, stop_after_attempt, wait_exponential

logger = logging.getLogger(__name__)

# Initialize CloudWatch client for custom metrics
cloudwatch = boto3.client('cloudwatch')


class OpenSearchSTACClient:
    """
    OpenSearch-based STAC catalog client.
    
    This client wraps the existing OpenSearch functionality to provide
    a consistent interface with the DynamoDB client.
    """
    
    def __init__(self, host: str, index: str = "stac"):
        """
        Initialize OpenSearch STAC client.
        
        Args:
            host: OpenSearch host endpoint
            index: OpenSearch index name
        """
        self.host = host
        self.index = index
        self.client = self._make_client()
        logger.info(f"Initialized OpenSearch STAC client for host: {host}")
    
    @retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=0.5))
    def _make_client(self):
        """Create OpenSearch client with retry logic."""
        return OpenSearch(
            hosts=[{"host": self.host, "port": 443}],
            use_ssl=True,
            verify_certs=True,
            connection_class=RequestsHttpConnection,
            http_auth=None
        )
    
    def get_item(self, item_id: str) -> Optional[Dict]:
        """
        Get a single STAC item by ID.
        
        Args:
            item_id: STAC item ID
        
        Returns:
            STAC item as dictionary, or None if not found
        """
        try:
            response = self.client.get(index=self.index, id=item_id)
            if response.get('found'):
                logger.debug(f"Retrieved STAC item from OpenSearch: {item_id}")
                return response.get('_source')
            return None
        except Exception as e:
            logger.debug(f"STAC item not found in OpenSearch: {item_id}")
            return None
    
    def search_by_collection(
        self,
        collection: str,
        start_datetime: Optional[str] = None,
        end_datetime: Optional[str] = None,
        limit: int = 100
    ) -> List[Dict]:
        """
        Search for STAC items in a collection.
        
        Args:
            collection: Collection name to search
            start_datetime: Optional start datetime (ISO format)
            end_datetime: Optional end datetime (ISO format)
            limit: Maximum number of items to return
        
        Returns:
            List of STAC items matching the criteria
        """
        try:
            must_clauses = [
                {"term": {"collection.keyword": collection}}
            ]
            
            if start_datetime and end_datetime:
                must_clauses.append({
                    "range": {
                        "properties.datetime": {
                            "gte": start_datetime,
                            "lte": end_datetime
                        }
                    }
                })
            elif start_datetime:
                must_clauses.append({
                    "range": {"properties.datetime": {"gte": start_datetime}}
                })
            elif end_datetime:
                must_clauses.append({
                    "range": {"properties.datetime": {"lte": end_datetime}}
                })
            
            body = {
                "query": {"bool": {"must": must_clauses}},
                "size": limit
            }
            
            response = self.client.search(index=self.index, body=body)
            hits = response.get("hits", {}).get("hits", [])
            items = [hit["_source"] for hit in hits]
            
            logger.debug(f"Found {len(items)} items in collection '{collection}' from OpenSearch")
            return items
            
        except Exception as e:
            logger.error(f"Error searching collection '{collection}' in OpenSearch: {e}")
            raise
    
    def search_by_datetime(
        self,
        start_datetime: str,
        end_datetime: str,
        collections: Optional[List[str]] = None,
        limit: int = 100
    ) -> List[Dict]:
        """
        Search for STAC items by datetime range.
        
        Args:
            start_datetime: Start datetime (ISO format)
            end_datetime: End datetime (ISO format)
            collections: Optional list of collections to filter by
            limit: Maximum number of items to return
        
        Returns:
            List of STAC items within the datetime range
        """
        try:
            must_clauses = [
                {
                    "range": {
                        "properties.datetime": {
                            "gte": start_datetime,
                            "lte": end_datetime
                        }
                    }
                }
            ]
            
            if collections:
                must_clauses.append({
                    "terms": {"collection.keyword": collections}
                })
            
            body = {
                "query": {"bool": {"must": must_clauses}},
                "size": limit
            }
            
            response = self.client.search(index=self.index, body=body)
            hits = response.get("hits", {}).get("hits", [])
            items = [hit["_source"] for hit in hits]
            
            logger.debug(f"Found {len(items)} items in datetime range from OpenSearch")
            return items
            
        except Exception as e:
            logger.error(f"Error searching by datetime in OpenSearch: {e}")
            raise
    
    def search_by_bbox(
        self,
        bbox: List[float],
        collections: Optional[List[str]] = None,
        start_datetime: Optional[str] = None,
        end_datetime: Optional[str] = None,
        limit: int = 100
    ) -> List[Dict]:
        """
        Search for STAC items intersecting a bounding box.
        
        Args:
            bbox: Bounding box [minx, miny, maxx, maxy]
            collections: Optional list of collections to filter by
            start_datetime: Optional start datetime (ISO format)
            end_datetime: Optional end datetime (ISO format)
            limit: Maximum number of items to return
        
        Returns:
            List of STAC items intersecting the bounding box
        """
        try:
            must_clauses = [
                {
                    "geo_bounding_box": {
                        "geometry": {
                            "top_left": {"lon": bbox[0], "lat": bbox[3]},
                            "bottom_right": {"lon": bbox[2], "lat": bbox[1]}
                        }
                    }
                }
            ]
            
            if collections:
                must_clauses.append({
                    "terms": {"collection.keyword": collections}
                })
            
            if start_datetime and end_datetime:
                must_clauses.append({
                    "range": {
                        "properties.datetime": {
                            "gte": start_datetime,
                            "lte": end_datetime
                        }
                    }
                })
            
            body = {
                "query": {"bool": {"must": must_clauses}},
                "size": limit
            }
            
            response = self.client.search(index=self.index, body=body)
            hits = response.get("hits", {}).get("hits", [])
            items = [hit["_source"] for hit in hits]
            
            logger.debug(f"Found {len(items)} items intersecting bbox from OpenSearch")
            return items
            
        except Exception as e:
            logger.error(f"Error searching by bbox in OpenSearch: {e}")
            raise
    
    def list_collections(self) -> List[str]:
        """
        List all unique collection names in the catalog.
        
        Returns:
            List of unique collection names
        """
        try:
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
            
            response = self.client.search(index=self.index, body=body)
            buckets = response.get("aggregations", {}).get("collections", {}).get("buckets", [])
            collections = [bucket["key"] for bucket in buckets]
            
            logger.debug(f"Found {len(collections)} collections from OpenSearch")
            return collections
            
        except Exception as e:
            logger.error(f"Error listing collections in OpenSearch: {e}")
            raise


class DualBackendSTACClient:
    """
    Dual backend STAC catalog client.
    
    This client supports both DynamoDB and OpenSearch backends, enabling
    zero-downtime migration. It reads from DynamoDB first and falls back
    to OpenSearch if the item is not found or if DynamoDB queries fail.
    
    Metrics are tracked for backend usage to monitor the migration progress.
    """
    
    def __init__(
        self,
        dynamodb_table_name: str,
        opensearch_host: str,
        opensearch_index: str = "stac",
        region_name: str = "ap-southeast-2"
    ):
        """
        Initialize dual backend STAC client.
        
        Args:
            dynamodb_table_name: Name of the DynamoDB table
            opensearch_host: OpenSearch host endpoint
            opensearch_index: OpenSearch index name
            region_name: AWS region for DynamoDB
        """
        self.dynamodb_client = DynamoDBSTACClient(dynamodb_table_name, region_name)
        self.opensearch_client = OpenSearchSTACClient(opensearch_host, opensearch_index)
        
        # Metrics tracking
        self.metrics = {
            "dynamodb_hits": 0,
            "opensearch_fallbacks": 0,
            "dynamodb_errors": 0
        }
        
        logger.info("Initialized dual backend STAC client")
    
    def _emit_backend_metric(self, backend: str, operation: str):
        """
        Emit a CloudWatch metric for backend usage.
        
        Args:
            backend: Backend used ("DynamoDB" or "OpenSearch")
            operation: Operation performed
        """
        try:
            cloudwatch.put_metric_data(
                Namespace='STAC/DualBackend',
                MetricData=[
                    {
                        'MetricName': f'{backend}Usage',
                        'Value': 1.0,
                        'Unit': 'Count',
                        'Dimensions': [
                            {
                                'Name': 'Operation',
                                'Value': operation
                            }
                        ]
                    }
                ]
            )
        except Exception as e:
            logger.warning(f"Failed to emit CloudWatch metric for {backend}: {e}")
    
    def get_item(self, item_id: str) -> Optional[Dict]:
        """
        Get a single STAC item by ID.
        
        Tries DynamoDB first, falls back to OpenSearch if not found or on error.
        
        Args:
            item_id: STAC item ID
        
        Returns:
            STAC item as dictionary, or None if not found in either backend
        """
        # Try DynamoDB first
        try:
            item = self.dynamodb_client.get_item(item_id)
            if item:
                self.metrics["dynamodb_hits"] += 1
                self._emit_backend_metric("DynamoDB", "GetItem")
                logger.debug(f"Retrieved item {item_id} from DynamoDB")
                return item
        except Exception as e:
            self.metrics["dynamodb_errors"] += 1
            logger.warning(f"DynamoDB query failed for item {item_id}: {e}, falling back to OpenSearch")
        
        # Fallback to OpenSearch
        try:
            item = self.opensearch_client.get_item(item_id)
            if item:
                self.metrics["opensearch_fallbacks"] += 1
                self._emit_backend_metric("OpenSearch", "GetItem")
                logger.info(f"Retrieved item {item_id} from OpenSearch (fallback)")
            return item
        except Exception as e:
            logger.error(f"OpenSearch query also failed for item {item_id}: {e}")
            return None
    
    def search_by_collection(
        self,
        collection: str,
        start_datetime: Optional[str] = None,
        end_datetime: Optional[str] = None,
        limit: int = 100
    ) -> List[Dict]:
        """
        Search for STAC items in a collection.
        
        Tries DynamoDB first, falls back to OpenSearch if query fails.
        
        Args:
            collection: Collection name to search
            start_datetime: Optional start datetime (ISO format)
            end_datetime: Optional end datetime (ISO format)
            limit: Maximum number of items to return
        
        Returns:
            List of STAC items matching the criteria
        """
        # Try DynamoDB first
        try:
            items = self.dynamodb_client.search_by_collection(
                collection, start_datetime, end_datetime, limit
            )
            if items:
                self.metrics["dynamodb_hits"] += 1
                self._emit_backend_metric("DynamoDB", "SearchByCollection")
                logger.debug(f"Retrieved {len(items)} items from collection '{collection}' from DynamoDB")
                return items
        except Exception as e:
            self.metrics["dynamodb_errors"] += 1
            logger.warning(f"DynamoDB query failed for collection '{collection}': {e}, falling back to OpenSearch")
        
        # Fallback to OpenSearch
        try:
            items = self.opensearch_client.search_by_collection(
                collection, start_datetime, end_datetime, limit
            )
            if items:
                self.metrics["opensearch_fallbacks"] += 1
                self._emit_backend_metric("OpenSearch", "SearchByCollection")
                logger.info(f"Retrieved {len(items)} items from collection '{collection}' from OpenSearch (fallback)")
            return items
        except Exception as e:
            logger.error(f"OpenSearch query also failed for collection '{collection}': {e}")
            return []
    
    def search_by_datetime(
        self,
        start_datetime: str,
        end_datetime: str,
        collections: Optional[List[str]] = None,
        limit: int = 100
    ) -> List[Dict]:
        """
        Search for STAC items by datetime range.
        
        Tries DynamoDB first, falls back to OpenSearch if query fails.
        
        Args:
            start_datetime: Start datetime (ISO format)
            end_datetime: End datetime (ISO format)
            collections: Optional list of collections to filter by
            limit: Maximum number of items to return
        
        Returns:
            List of STAC items within the datetime range
        """
        # Try DynamoDB first
        try:
            items = self.dynamodb_client.search_by_datetime(
                start_datetime, end_datetime, collections, limit
            )
            if items:
                self.metrics["dynamodb_hits"] += 1
                self._emit_backend_metric("DynamoDB", "SearchByDatetime")
                logger.debug(f"Retrieved {len(items)} items from datetime range from DynamoDB")
                return items
        except Exception as e:
            self.metrics["dynamodb_errors"] += 1
            logger.warning(f"DynamoDB query failed for datetime range: {e}, falling back to OpenSearch")
        
        # Fallback to OpenSearch
        try:
            items = self.opensearch_client.search_by_datetime(
                start_datetime, end_datetime, collections, limit
            )
            if items:
                self.metrics["opensearch_fallbacks"] += 1
                self._emit_backend_metric("OpenSearch", "SearchByDatetime")
                logger.info(f"Retrieved {len(items)} items from datetime range from OpenSearch (fallback)")
            return items
        except Exception as e:
            logger.error(f"OpenSearch query also failed for datetime range: {e}")
            return []
    
    def search_by_bbox(
        self,
        bbox: List[float],
        collections: Optional[List[str]] = None,
        start_datetime: Optional[str] = None,
        end_datetime: Optional[str] = None,
        limit: int = 100
    ) -> List[Dict]:
        """
        Search for STAC items intersecting a bounding box.
        
        Tries DynamoDB first, falls back to OpenSearch if query fails.
        
        Args:
            bbox: Bounding box [minx, miny, maxx, maxy]
            collections: Optional list of collections to filter by
            start_datetime: Optional start datetime (ISO format)
            end_datetime: Optional end datetime (ISO format)
            limit: Maximum number of items to return
        
        Returns:
            List of STAC items intersecting the bounding box
        """
        # Try DynamoDB first
        try:
            items = self.dynamodb_client.search_by_bbox(
                bbox, collections, start_datetime, end_datetime, limit
            )
            if items:
                self.metrics["dynamodb_hits"] += 1
                self._emit_backend_metric("DynamoDB", "SearchByBbox")
                logger.debug(f"Retrieved {len(items)} items from bbox query from DynamoDB")
                return items
        except Exception as e:
            self.metrics["dynamodb_errors"] += 1
            logger.warning(f"DynamoDB query failed for bbox: {e}, falling back to OpenSearch")
        
        # Fallback to OpenSearch
        try:
            items = self.opensearch_client.search_by_bbox(
                bbox, collections, start_datetime, end_datetime, limit
            )
            if items:
                self.metrics["opensearch_fallbacks"] += 1
                self._emit_backend_metric("OpenSearch", "SearchByBbox")
                logger.info(f"Retrieved {len(items)} items from bbox query from OpenSearch (fallback)")
            return items
        except Exception as e:
            logger.error(f"OpenSearch query also failed for bbox: {e}")
            return []
    
    def list_collections(self) -> List[str]:
        """
        List all unique collection names in the catalog.
        
        Tries DynamoDB first, falls back to OpenSearch if query fails.
        
        Returns:
            List of unique collection names
        """
        # Try DynamoDB first
        try:
            collections = self.dynamodb_client.list_collections()
            if collections:
                self.metrics["dynamodb_hits"] += 1
                self._emit_backend_metric("DynamoDB", "ListCollections")
                logger.debug(f"Retrieved {len(collections)} collections from DynamoDB")
                return collections
        except Exception as e:
            self.metrics["dynamodb_errors"] += 1
            logger.warning(f"DynamoDB query failed for collections: {e}, falling back to OpenSearch")
        
        # Fallback to OpenSearch
        try:
            collections = self.opensearch_client.list_collections()
            if collections:
                self.metrics["opensearch_fallbacks"] += 1
                self._emit_backend_metric("OpenSearch", "ListCollections")
                logger.info(f"Retrieved {len(collections)} collections from OpenSearch (fallback)")
            return collections
        except Exception as e:
            logger.error(f"OpenSearch query also failed for collections: {e}")
            return []
    
    def get_metrics(self) -> Dict[str, int]:
        """
        Get backend usage metrics.
        
        Returns:
            Dictionary with metrics:
            - dynamodb_hits: Number of successful DynamoDB queries
            - opensearch_fallbacks: Number of OpenSearch fallback queries
            - dynamodb_errors: Number of DynamoDB errors
        """
        return self.metrics.copy()
    
    def reset_metrics(self):
        """Reset backend usage metrics to zero."""
        self.metrics = {
            "dynamodb_hits": 0,
            "opensearch_fallbacks": 0,
            "dynamodb_errors": 0
        }
        logger.info("Reset backend usage metrics")
