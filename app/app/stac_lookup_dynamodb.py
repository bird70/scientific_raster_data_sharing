"""
DynamoDB-based STAC catalog client.

This module provides a client for querying STAC items stored in DynamoDB,
replacing the OpenSearch-based implementation with a more cost-effective solution.
"""

import os
import boto3
from boto3.dynamodb.conditions import Key, Attr
from typing import Optional, List, Dict
import logging
from decimal import Decimal
import time

logger = logging.getLogger(__name__)

# Set default region for testing if not already set
# Boto3 looks for AWS_DEFAULT_REGION, so copy AWS_REGION if it exists
if 'AWS_DEFAULT_REGION' not in os.environ:
    if 'AWS_REGION' in os.environ:
        os.environ['AWS_DEFAULT_REGION'] = os.environ['AWS_REGION']
        logger.debug(f"Set AWS_DEFAULT_REGION from AWS_REGION: {os.environ['AWS_REGION']}")
    else:
        os.environ['AWS_DEFAULT_REGION'] = 'ap-southeast-2'
        logger.debug("Set default AWS region to ap-southeast-2 for testing")

# Initialize CloudWatch client for custom metrics
cloudwatch = boto3.client('cloudwatch')


def bbox_intersects(item_bbox: List[float], query_bbox: List[float]) -> bool:
    """
    Check if two bounding boxes intersect.
    
    Args:
        item_bbox: Item bounding box [minx, miny, maxx, maxy]
        query_bbox: Query bounding box [minx, miny, maxx, maxy]
    
    Returns:
        True if bounding boxes intersect, False otherwise
    """
    # Validate bbox format
    if not item_bbox or len(item_bbox) != 4:
        return False
    if not query_bbox or len(query_bbox) != 4:
        return False
    
    # Bounding boxes don't intersect if:
    # - item is east of query (item.minx > query.maxx)
    # - item is west of query (item.maxx < query.minx)
    # - item is north of query (item.miny > query.maxy)
    # - item is south of query (item.maxy < query.miny)
    return not (
        item_bbox[2] < query_bbox[0] or  # item east of query
        item_bbox[0] > query_bbox[2] or  # item west of query
        item_bbox[3] < query_bbox[1] or  # item south of query
        item_bbox[1] > query_bbox[3]     # item north of query
    )


class DynamoDBSTACClient:
    """
    Client for querying STAC items from DynamoDB.
    
    This client provides methods for retrieving STAC items using various
    query patterns optimized for DynamoDB's key-value and GSI capabilities.
    """
    
    def __init__(self, table_name: str, region_name: str = "ap-southeast-2"):
        """
        Initialize DynamoDB STAC client.
        
        Args:
            table_name: Name of the DynamoDB table containing STAC items
            region_name: AWS region where the table is located
        """
        self.dynamodb = boto3.resource('dynamodb', region_name=region_name)
        self.table = self.dynamodb.Table(table_name)
        self.table_name = table_name
        self.region_name = region_name
        logger.info(f"Initialized DynamoDB STAC client for table: {table_name}")
    
    def _emit_metric(self, metric_name: str, value: float, unit: str = "Count"):
        """
        Emit a custom CloudWatch metric for DynamoDB operations.
        
        Args:
            metric_name: Name of the metric
            value: Metric value
            unit: Metric unit (Count, Milliseconds, etc.)
        """
        try:
            cloudwatch.put_metric_data(
                Namespace='STAC/DynamoDB',
                MetricData=[
                    {
                        'MetricName': metric_name,
                        'Value': value,
                        'Unit': unit,
                        'Dimensions': [
                            {
                                'Name': 'TableName',
                                'Value': self.table_name
                            }
                        ]
                    }
                ]
            )
        except Exception as e:
            logger.warning(f"Failed to emit CloudWatch metric {metric_name}: {e}")
    
    def get_item(self, item_id: str) -> Optional[Dict]:
        """
        Get a single STAC item by ID.
        
        Uses DynamoDB GetItem operation for efficient single-item lookup.
        
        Args:
            item_id: STAC item ID
        
        Returns:
            STAC item as dictionary, or None if not found
        """
        operation = "GetItem"
        start_time = time.time()
        
        try:
            response = self.table.get_item(Key={'id': item_id})
            latency_ms = (time.time() - start_time) * 1000
            
            item = response.get('Item')
            
            # Log operation details
            logger.info(
                f"DynamoDB operation: {operation}, "
                f"item_id: {item_id}, "
                f"latency: {latency_ms:.2f}ms, "
                f"found: {item is not None}"
            )
            
            # Emit metrics
            self._emit_metric(f"{operation}Latency", latency_ms, "Milliseconds")
            self._emit_metric(f"{operation}Success", 1.0, "Count")
            
            if item:
                logger.debug(f"Retrieved STAC item: {item_id}")
                return self._convert_decimals(item)
            else:
                logger.debug(f"STAC item not found: {item_id}")
                return None
                
        except Exception as e:
            latency_ms = (time.time() - start_time) * 1000
            logger.error(
                f"DynamoDB operation failed: {operation}, "
                f"item_id: {item_id}, "
                f"latency: {latency_ms:.2f}ms, "
                f"error: {e}"
            )
            
            # Emit error metric
            self._emit_metric(f"{operation}Error", 1.0, "Count")
            raise
    
    def search_by_collection(
        self,
        collection: str,
        start_datetime: Optional[str] = None,
        end_datetime: Optional[str] = None,
        limit: int = 100
    ) -> List[Dict]:
        """
        Search for STAC items in a collection, optionally filtered by time.
        
        Uses the collection-index GSI for efficient querying.
        
        Args:
            collection: Collection name to search
            start_datetime: Optional start datetime (ISO format)
            end_datetime: Optional end datetime (ISO format)
            limit: Maximum number of items to return
        
        Returns:
            List of STAC items matching the criteria
        """
        operation = "Query"
        start_time = time.time()
        
        try:
            # Build key condition
            key_condition = Key('collection').eq(collection)
            
            # Add datetime range if provided
            if start_datetime and end_datetime:
                key_condition = key_condition & Key('datetime').between(start_datetime, end_datetime)
            elif start_datetime:
                key_condition = key_condition & Key('datetime').gte(start_datetime)
            elif end_datetime:
                key_condition = key_condition & Key('datetime').lte(end_datetime)
            
            # Query the collection-index GSI
            response = self.table.query(
                IndexName='collection-index',
                KeyConditionExpression=key_condition,
                Limit=limit
            )
            
            latency_ms = (time.time() - start_time) * 1000
            items = response.get('Items', [])
            item_count = len(items)
            
            # Log operation details
            logger.info(
                f"DynamoDB operation: {operation}, "
                f"index: collection-index, "
                f"collection: {collection}, "
                f"latency: {latency_ms:.2f}ms, "
                f"item_count: {item_count}"
            )
            
            # Emit metrics
            self._emit_metric(f"{operation}Latency", latency_ms, "Milliseconds")
            self._emit_metric(f"{operation}Success", 1.0, "Count")
            self._emit_metric(f"{operation}ItemCount", float(item_count), "Count")
            
            logger.debug(f"Found {item_count} items in collection '{collection}'")
            
            return [self._convert_decimals(item) for item in items]
            
        except Exception as e:
            latency_ms = (time.time() - start_time) * 1000
            logger.error(
                f"DynamoDB operation failed: {operation}, "
                f"collection: {collection}, "
                f"latency: {latency_ms:.2f}ms, "
                f"error: {e}"
            )
            
            # Emit error metric
            self._emit_metric(f"{operation}Error", 1.0, "Count")
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
        
        Uses the datetime-index GSI for efficient temporal queries.
        
        Args:
            start_datetime: Start datetime (ISO format)
            end_datetime: End datetime (ISO format)
            collections: Optional list of collections to filter by
            limit: Maximum number of items to return
        
        Returns:
            List of STAC items within the datetime range
        """
        operation = "Scan"
        start_time = time.time()
        
        try:
            items = []
            
            # Query datetime-index GSI
            # Note: This queries by exact datetime values, so we need to scan
            # the range. For production, consider date-only partition key.
            response = self.table.scan(
                FilterExpression=Attr('datetime').between(start_datetime, end_datetime),
                Limit=limit
            )
            
            items = response.get('Items', [])
            
            # Filter by collections if specified
            if collections:
                items = [item for item in items if item.get('collection') in collections]
            
            latency_ms = (time.time() - start_time) * 1000
            item_count = len(items)
            
            # Log operation details
            logger.info(
                f"DynamoDB operation: {operation}, "
                f"datetime_range: {start_datetime} to {end_datetime}, "
                f"latency: {latency_ms:.2f}ms, "
                f"item_count: {item_count}"
            )
            
            # Emit metrics
            self._emit_metric(f"{operation}Latency", latency_ms, "Milliseconds")
            self._emit_metric(f"{operation}Success", 1.0, "Count")
            self._emit_metric(f"{operation}ItemCount", float(item_count), "Count")
            
            logger.debug(f"Found {item_count} items in datetime range {start_datetime} to {end_datetime}")
            
            return [self._convert_decimals(item) for item in items]
            
        except Exception as e:
            latency_ms = (time.time() - start_time) * 1000
            logger.error(
                f"DynamoDB operation failed: {operation}, "
                f"datetime_range: {start_datetime} to {end_datetime}, "
                f"latency: {latency_ms:.2f}ms, "
                f"error: {e}"
            )
            
            # Emit error metric
            self._emit_metric(f"{operation}Error", 1.0, "Count")
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
        
        Uses Scan with filter expression since DynamoDB doesn't support
        native geospatial queries. For better performance, consider
        filtering by collection or datetime first.
        
        Args:
            bbox: Bounding box [minx, miny, maxx, maxy]
            collections: Optional list of collections to filter by
            start_datetime: Optional start datetime (ISO format)
            end_datetime: Optional end datetime (ISO format)
            limit: Maximum number of items to return
        
        Returns:
            List of STAC items intersecting the bounding box
        """
        operation = "Scan"
        start_time = time.time()
        
        try:
            # Build filter expression
            filter_expr = None
            
            # Add collection filter if specified
            if collections:
                filter_expr = Attr('collection').is_in(collections)
            
            # Add datetime filter if specified
            if start_datetime and end_datetime:
                datetime_filter = Attr('datetime').between(start_datetime, end_datetime)
                filter_expr = datetime_filter if filter_expr is None else filter_expr & datetime_filter
            elif start_datetime:
                datetime_filter = Attr('datetime').gte(start_datetime)
                filter_expr = datetime_filter if filter_expr is None else filter_expr & datetime_filter
            elif end_datetime:
                datetime_filter = Attr('datetime').lte(end_datetime)
                filter_expr = datetime_filter if filter_expr is None else filter_expr & datetime_filter
            
            # Scan table with filters
            scan_kwargs = {'Limit': limit * 2}  # Get more items to filter by bbox
            if filter_expr:
                scan_kwargs['FilterExpression'] = filter_expr
            
            response = self.table.scan(**scan_kwargs)
            items = response.get('Items', [])
            
            # Filter by bounding box intersection
            matching_items = []
            for item in items:
                item_bbox = item.get('bbox')
                if item_bbox and bbox_intersects(item_bbox, bbox):
                    matching_items.append(self._convert_decimals(item))
                    if len(matching_items) >= limit:
                        break
            
            latency_ms = (time.time() - start_time) * 1000
            item_count = len(matching_items)
            
            # Log operation details
            logger.info(
                f"DynamoDB operation: {operation}, "
                f"bbox: {bbox}, "
                f"latency: {latency_ms:.2f}ms, "
                f"item_count: {item_count}"
            )
            
            # Emit metrics
            self._emit_metric(f"{operation}Latency", latency_ms, "Milliseconds")
            self._emit_metric(f"{operation}Success", 1.0, "Count")
            self._emit_metric(f"{operation}ItemCount", float(item_count), "Count")
            
            logger.debug(f"Found {item_count} items intersecting bbox {bbox}")
            
            return matching_items
            
        except Exception as e:
            latency_ms = (time.time() - start_time) * 1000
            logger.error(
                f"DynamoDB operation failed: {operation}, "
                f"bbox: {bbox}, "
                f"latency: {latency_ms:.2f}ms, "
                f"error: {e}"
            )
            
            # Emit error metric
            self._emit_metric(f"{operation}Error", 1.0, "Count")
            raise
    
    def list_collections(self) -> List[str]:
        """
        List all unique collection names in the catalog.
        
        Uses Scan with projection to retrieve only collection names.
        
        Returns:
            List of unique collection names
        """
        operation = "Scan"
        start_time = time.time()
        
        try:
            collections = set()
            
            # Scan table with projection to get only collection attribute
            # Use ExpressionAttributeNames because 'collection' is a reserved keyword
            response = self.table.scan(
                ProjectionExpression='#coll',
                ExpressionAttributeNames={'#coll': 'collection'}
            )
            
            for item in response.get('Items', []):
                if 'collection' in item:
                    collections.add(item['collection'])
            
            # Handle pagination if needed
            while 'LastEvaluatedKey' in response:
                response = self.table.scan(
                    ProjectionExpression='#coll',
                    ExpressionAttributeNames={'#coll': 'collection'},
                    ExclusiveStartKey=response['LastEvaluatedKey']
                )
                for item in response.get('Items', []):
                    if 'collection' in item:
                        collections.add(item['collection'])
            
            latency_ms = (time.time() - start_time) * 1000
            collection_list = sorted(list(collections))
            collection_count = len(collection_list)
            
            # Log operation details
            logger.info(
                f"DynamoDB operation: {operation}, "
                f"purpose: list_collections, "
                f"latency: {latency_ms:.2f}ms, "
                f"collection_count: {collection_count}"
            )
            
            # Emit metrics
            self._emit_metric(f"{operation}Latency", latency_ms, "Milliseconds")
            self._emit_metric(f"{operation}Success", 1.0, "Count")
            
            logger.debug(f"Found {collection_count} collections")
            
            return collection_list
            
        except Exception as e:
            latency_ms = (time.time() - start_time) * 1000
            logger.error(
                f"DynamoDB operation failed: {operation}, "
                f"purpose: list_collections, "
                f"latency: {latency_ms:.2f}ms, "
                f"error: {e}"
            )
            
            # Emit error metric
            self._emit_metric(f"{operation}Error", 1.0, "Count")
            raise
    
    def _convert_decimals(self, obj):
        """
        Convert DynamoDB Decimal types to float for JSON serialization.
        
        Args:
            obj: Object potentially containing Decimal values
        
        Returns:
            Object with Decimals converted to float
        """
        if isinstance(obj, list):
            return [self._convert_decimals(item) for item in obj]
        elif isinstance(obj, dict):
            return {key: self._convert_decimals(value) for key, value in obj.items()}
        elif isinstance(obj, Decimal):
            return float(obj)
        else:
            return obj
