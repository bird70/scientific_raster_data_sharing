"""
Unit tests for DynamoDB STAC client.

Tests cover:
- get_item with existing and non-existing items
- search_by_collection with various filters
- search_by_datetime with range queries
- search_by_bbox with intersection logic
- list_collections aggregation
- error handling (throttling, validation errors)
"""

import pytest
from moto import mock_aws
import boto3
from botocore.exceptions import ClientError
from decimal import Decimal
from app.stac_lookup_dynamodb import DynamoDBSTACClient, bbox_intersects


@pytest.fixture
def dynamodb_table():
    """Create a mock DynamoDB table for testing."""
    with mock_aws():
        # Create DynamoDB resource
        dynamodb = boto3.resource('dynamodb', region_name='ap-southeast-2')
        
        # Create table with GSIs
        table = dynamodb.create_table(
            TableName='test-stac-items',
            KeySchema=[
                {'AttributeName': 'id', 'KeyType': 'HASH'}
            ],
            AttributeDefinitions=[
                {'AttributeName': 'id', 'AttributeType': 'S'},
                {'AttributeName': 'collection', 'AttributeType': 'S'},
                {'AttributeName': 'datetime', 'AttributeType': 'S'}
            ],
            GlobalSecondaryIndexes=[
                {
                    'IndexName': 'collection-index',
                    'KeySchema': [
                        {'AttributeName': 'collection', 'KeyType': 'HASH'},
                        {'AttributeName': 'datetime', 'KeyType': 'RANGE'}
                    ],
                    'Projection': {'ProjectionType': 'ALL'}
                },
                {
                    'IndexName': 'datetime-index',
                    'KeySchema': [
                        {'AttributeName': 'datetime', 'KeyType': 'HASH'},
                        {'AttributeName': 'id', 'KeyType': 'RANGE'}
                    ],
                    'Projection': {'ProjectionType': 'ALL'}
                }
            ],
            BillingMode='PAY_PER_REQUEST'
        )
        
        yield table


@pytest.fixture
def stac_client(dynamodb_table):
    """Create a DynamoDB STAC client for testing."""
    return DynamoDBSTACClient('test-stac-items', region_name='ap-southeast-2')


@pytest.fixture
def sample_stac_items(dynamodb_table):
    """Insert sample STAC items into the test table."""
    items = [
        {
            'id': 'item-1',
            'type': 'Feature',
            'collection': 'sst-daily',
            'datetime': '2024-01-01T00:00:00Z',
            'geometry': {
                'type': 'Polygon',
                'coordinates': [[[Decimal('150'), Decimal('-35')], [Decimal('151'), Decimal('-35')], 
                                 [Decimal('151'), Decimal('-34')], [Decimal('150'), Decimal('-34')], 
                                 [Decimal('150'), Decimal('-35')]]]
            },
            'bbox': [Decimal('150.0'), Decimal('-35.0'), Decimal('151.0'), Decimal('-34.0')],
            'properties': {
                'datetime': '2024-01-01T00:00:00Z',
                'title': 'SST Day 1'
            },
            'assets': {
                'zarr': {'href': 's3://bucket/item-1.zarr', 'type': 'application/vnd+zarr'}
            },
            'stac_version': '1.0.0'
        },
        {
            'id': 'item-2',
            'type': 'Feature',
            'collection': 'sst-daily',
            'datetime': '2024-01-02T00:00:00Z',
            'geometry': {
                'type': 'Polygon',
                'coordinates': [[[Decimal('150'), Decimal('-35')], [Decimal('151'), Decimal('-35')], 
                                 [Decimal('151'), Decimal('-34')], [Decimal('150'), Decimal('-34')], 
                                 [Decimal('150'), Decimal('-35')]]]
            },
            'bbox': [Decimal('150.0'), Decimal('-35.0'), Decimal('151.0'), Decimal('-34.0')],
            'properties': {
                'datetime': '2024-01-02T00:00:00Z',
                'title': 'SST Day 2'
            },
            'assets': {
                'zarr': {'href': 's3://bucket/item-2.zarr', 'type': 'application/vnd+zarr'}
            },
            'stac_version': '1.0.0'
        },
        {
            'id': 'item-3',
            'type': 'Feature',
            'collection': 'chlorophyll',
            'datetime': '2024-01-01T00:00:00Z',
            'geometry': {
                'type': 'Polygon',
                'coordinates': [[[Decimal('152'), Decimal('-36')], [Decimal('153'), Decimal('-36')], 
                                 [Decimal('153'), Decimal('-35')], [Decimal('152'), Decimal('-35')], 
                                 [Decimal('152'), Decimal('-36')]]]
            },
            'bbox': [Decimal('152.0'), Decimal('-36.0'), Decimal('153.0'), Decimal('-35.0')],
            'properties': {
                'datetime': '2024-01-01T00:00:00Z',
                'title': 'Chlorophyll Day 1'
            },
            'assets': {
                'zarr': {'href': 's3://bucket/item-3.zarr', 'type': 'application/vnd+zarr'}
            },
            'stac_version': '1.0.0'
        },
        {
            'id': 'item-4',
            'type': 'Feature',
            'collection': 'sst-daily',
            'datetime': '2024-01-15T00:00:00Z',
            'geometry': {
                'type': 'Polygon',
                'coordinates': [[[Decimal('150'), Decimal('-35')], [Decimal('151'), Decimal('-35')], 
                                 [Decimal('151'), Decimal('-34')], [Decimal('150'), Decimal('-34')], 
                                 [Decimal('150'), Decimal('-35')]]]
            },
            'bbox': [Decimal('150.0'), Decimal('-35.0'), Decimal('151.0'), Decimal('-34.0')],
            'properties': {
                'datetime': '2024-01-15T00:00:00Z',
                'title': 'SST Day 15'
            },
            'assets': {
                'zarr': {'href': 's3://bucket/item-4.zarr', 'type': 'application/vnd+zarr'}
            },
            'stac_version': '1.0.0'
        }
    ]
    
    # Insert items
    for item in items:
        dynamodb_table.put_item(Item=item)
    
    return items


# Test bbox_intersects helper function
class TestBboxIntersects:
    """Tests for bounding box intersection logic."""
    
    def test_intersecting_boxes(self):
        """Test that overlapping bounding boxes are detected."""
        bbox1 = [0, 0, 10, 10]
        bbox2 = [5, 5, 15, 15]
        assert bbox_intersects(bbox1, bbox2) is True
    
    def test_non_intersecting_boxes_east(self):
        """Test that non-overlapping boxes (east) are detected."""
        bbox1 = [0, 0, 10, 10]
        bbox2 = [15, 0, 25, 10]
        assert bbox_intersects(bbox1, bbox2) is False
    
    def test_non_intersecting_boxes_west(self):
        """Test that non-overlapping boxes (west) are detected."""
        bbox1 = [15, 0, 25, 10]
        bbox2 = [0, 0, 10, 10]
        assert bbox_intersects(bbox1, bbox2) is False
    
    def test_non_intersecting_boxes_north(self):
        """Test that non-overlapping boxes (north) are detected."""
        bbox1 = [0, 0, 10, 10]
        bbox2 = [0, 15, 10, 25]
        assert bbox_intersects(bbox1, bbox2) is False
    
    def test_non_intersecting_boxes_south(self):
        """Test that non-overlapping boxes (south) are detected."""
        bbox1 = [0, 15, 10, 25]
        bbox2 = [0, 0, 10, 10]
        assert bbox_intersects(bbox1, bbox2) is False
    
    def test_contained_box(self):
        """Test that a contained box intersects."""
        bbox1 = [0, 0, 20, 20]
        bbox2 = [5, 5, 15, 15]
        assert bbox_intersects(bbox1, bbox2) is True
    
    def test_touching_boxes(self):
        """Test that touching boxes (edge case) intersect."""
        bbox1 = [0, 0, 10, 10]
        bbox2 = [10, 0, 20, 10]
        assert bbox_intersects(bbox1, bbox2) is True


# Test DynamoDBSTACClient
class TestDynamoDBSTACClient:
    """Tests for DynamoDB STAC client operations."""
    
    def test_get_item_existing(self, stac_client, sample_stac_items):
        """Test retrieving an existing STAC item by ID."""
        item = stac_client.get_item('item-1')
        
        assert item is not None
        assert item['id'] == 'item-1'
        assert item['type'] == 'Feature'
        assert item['collection'] == 'sst-daily'
        assert item['properties']['title'] == 'SST Day 1'
    
    def test_get_item_non_existing(self, stac_client, sample_stac_items):
        """Test retrieving a non-existing STAC item returns None."""
        item = stac_client.get_item('non-existent-item')
        
        assert item is None
    
    def test_search_by_collection_basic(self, stac_client, sample_stac_items):
        """Test searching items by collection name."""
        items = stac_client.search_by_collection('sst-daily')
        
        assert len(items) == 3
        assert all(item['collection'] == 'sst-daily' for item in items)
        assert set(item['id'] for item in items) == {'item-1', 'item-2', 'item-4'}
    
    def test_search_by_collection_with_start_datetime(self, stac_client, sample_stac_items):
        """Test searching items by collection with start datetime filter."""
        items = stac_client.search_by_collection(
            'sst-daily',
            start_datetime='2024-01-02T00:00:00Z'
        )
        
        assert len(items) == 2
        assert all(item['collection'] == 'sst-daily' for item in items)
        assert set(item['id'] for item in items) == {'item-2', 'item-4'}
    
    def test_search_by_collection_with_end_datetime(self, stac_client, sample_stac_items):
        """Test searching items by collection with end datetime filter."""
        items = stac_client.search_by_collection(
            'sst-daily',
            end_datetime='2024-01-02T00:00:00Z'
        )
        
        assert len(items) == 2
        assert all(item['collection'] == 'sst-daily' for item in items)
        assert set(item['id'] for item in items) == {'item-1', 'item-2'}
    
    def test_search_by_collection_with_datetime_range(self, stac_client, sample_stac_items):
        """Test searching items by collection with datetime range."""
        items = stac_client.search_by_collection(
            'sst-daily',
            start_datetime='2024-01-01T00:00:00Z',
            end_datetime='2024-01-02T00:00:00Z'
        )
        
        assert len(items) == 2
        assert all(item['collection'] == 'sst-daily' for item in items)
        assert set(item['id'] for item in items) == {'item-1', 'item-2'}
    
    def test_search_by_collection_empty_result(self, stac_client, sample_stac_items):
        """Test searching for non-existent collection returns empty list."""
        items = stac_client.search_by_collection('non-existent-collection')
        
        assert items == []
    
    def test_search_by_collection_with_limit(self, stac_client, sample_stac_items):
        """Test that limit parameter restricts results."""
        items = stac_client.search_by_collection('sst-daily', limit=2)
        
        assert len(items) <= 2
    
    def test_search_by_datetime_range(self, stac_client, sample_stac_items):
        """Test searching items by datetime range."""
        items = stac_client.search_by_datetime(
            start_datetime='2024-01-01T00:00:00Z',
            end_datetime='2024-01-02T00:00:00Z'
        )
        
        assert len(items) == 3
        assert set(item['id'] for item in items) == {'item-1', 'item-2', 'item-3'}
    
    def test_search_by_datetime_with_collection_filter(self, stac_client, sample_stac_items):
        """Test searching by datetime with collection filter."""
        items = stac_client.search_by_datetime(
            start_datetime='2024-01-01T00:00:00Z',
            end_datetime='2024-01-02T00:00:00Z',
            collections=['sst-daily']
        )
        
        assert len(items) == 2
        assert all(item['collection'] == 'sst-daily' for item in items)
        assert set(item['id'] for item in items) == {'item-1', 'item-2'}
    
    def test_search_by_datetime_empty_result(self, stac_client, sample_stac_items):
        """Test searching datetime range with no matches."""
        items = stac_client.search_by_datetime(
            start_datetime='2025-01-01T00:00:00Z',
            end_datetime='2025-01-02T00:00:00Z'
        )
        
        assert items == []
    
    def test_search_by_bbox_intersecting(self, stac_client, sample_stac_items):
        """Test searching items by bounding box."""
        # Query bbox that intersects with item-1 and item-2
        bbox = [149.5, -35.5, 151.5, -33.5]
        items = stac_client.search_by_bbox(bbox)
        
        assert len(items) >= 2
        item_ids = set(item['id'] for item in items)
        assert 'item-1' in item_ids
        assert 'item-2' in item_ids
    
    def test_search_by_bbox_non_intersecting(self, stac_client, sample_stac_items):
        """Test searching with non-intersecting bounding box."""
        # Query bbox that doesn't intersect with any items
        bbox = [0, 0, 10, 10]
        items = stac_client.search_by_bbox(bbox)
        
        assert items == []
    
    def test_search_by_bbox_with_collection_filter(self, stac_client, sample_stac_items):
        """Test searching by bbox with collection filter."""
        bbox = [149.5, -35.5, 151.5, -33.5]
        items = stac_client.search_by_bbox(bbox, collections=['sst-daily'])
        
        assert len(items) >= 2
        assert all(item['collection'] == 'sst-daily' for item in items)
    
    def test_search_by_bbox_with_datetime_filter(self, stac_client, sample_stac_items):
        """Test searching by bbox with datetime filter."""
        bbox = [149.5, -35.5, 151.5, -33.5]
        items = stac_client.search_by_bbox(
            bbox,
            start_datetime='2024-01-01T00:00:00Z',
            end_datetime='2024-01-02T00:00:00Z'
        )
        
        assert len(items) >= 1
        item_ids = set(item['id'] for item in items)
        assert 'item-1' in item_ids or 'item-2' in item_ids
    
    def test_search_by_bbox_with_limit(self, stac_client, sample_stac_items):
        """Test that bbox search respects limit parameter."""
        bbox = [149.5, -35.5, 153.5, -33.5]  # Large bbox
        items = stac_client.search_by_bbox(bbox, limit=2)
        
        assert len(items) <= 2
    
    def test_list_collections(self, stac_client, sample_stac_items):
        """Test listing all unique collections."""
        collections = stac_client.list_collections()
        
        assert len(collections) == 2
        assert 'sst-daily' in collections
        assert 'chlorophyll' in collections
        assert collections == sorted(collections)  # Should be sorted
    
    def test_list_collections_empty_table(self, stac_client):
        """Test listing collections from empty table."""
        collections = stac_client.list_collections()
        
        assert collections == []
    
    def test_get_item_with_decimal_conversion(self, stac_client, dynamodb_table):
        """Test that Decimal values are converted to float."""
        from decimal import Decimal
        
        # Insert item with Decimal values
        item_with_decimals = {
            'id': 'decimal-item',
            'type': 'Feature',
            'collection': 'test',
            'datetime': '2024-01-01T00:00:00Z',
            'geometry': {'type': 'Point', 'coordinates': [Decimal('150.5'), Decimal('-35.5')]},
            'bbox': [Decimal('150.0'), Decimal('-36.0'), Decimal('151.0'), Decimal('-35.0')],
            'properties': {'value': Decimal('123.45')},
            'assets': {},
            'stac_version': '1.0.0'
        }
        dynamodb_table.put_item(Item=item_with_decimals)
        
        # Retrieve and verify conversion
        item = stac_client.get_item('decimal-item')
        
        assert item is not None
        assert isinstance(item['geometry']['coordinates'][0], float)
        assert isinstance(item['geometry']['coordinates'][1], float)
        assert isinstance(item['bbox'][0], float)
        assert isinstance(item['properties']['value'], float)
        assert item['properties']['value'] == 123.45


class TestErrorHandling:
    """Tests for error handling scenarios."""
    
    def test_get_item_with_invalid_table(self):
        """Test that accessing non-existent table raises error."""
        with mock_aws():
            client = DynamoDBSTACClient('non-existent-table', region_name='ap-southeast-2')
            
            with pytest.raises(Exception):
                client.get_item('item-1')
    
    def test_search_by_collection_with_invalid_table(self):
        """Test that searching non-existent table raises error."""
        with mock_aws():
            client = DynamoDBSTACClient('non-existent-table', region_name='ap-southeast-2')
            
            with pytest.raises(Exception):
                client.search_by_collection('test-collection')
    
    def test_search_by_bbox_with_invalid_bbox(self, stac_client, sample_stac_items):
        """Test that invalid bbox format is handled gracefully."""
        # This should not crash, but may return empty results
        items = stac_client.search_by_bbox([])
        
        # Should handle gracefully (empty or error)
        assert isinstance(items, list)
