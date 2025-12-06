"""
Unit tests for the /api/search endpoint.

Tests the STAC search functionality with various filter combinations.
"""

import pytest
from fastapi.testclient import TestClient
from unittest.mock import Mock, patch
from app.main import app

client = TestClient(app)


class TestSearchEndpoint:
    """Test suite for /api/search endpoint"""
    
    def test_search_with_no_filters_returns_empty(self):
        """Test that search with no filters returns empty results"""
        response = client.get("/api/search")
        assert response.status_code == 200
        data = response.json()
        assert data["items"] == []
        assert data["total"] == 0
        assert data["limit"] == 50
        assert data["offset"] == 0
    
    @patch('app.main.stac_client')
    def test_search_with_collection_filter(self, mock_client):
        """Test search with collection filter"""
        # Mock the search_by_collection method
        mock_items = [
            {"id": "item1", "collection": "test-collection", "properties": {}},
            {"id": "item2", "collection": "test-collection", "properties": {}}
        ]
        mock_client.search_by_collection.return_value = mock_items
        
        response = client.get("/api/search?collections=test-collection")
        assert response.status_code == 200
        data = response.json()
        assert len(data["items"]) == 2
        assert data["total"] == 2
        
        # Verify the mock was called correctly
        mock_client.search_by_collection.assert_called_once()
    
    @patch('app.main.stac_client')
    def test_search_with_bbox_filter(self, mock_client):
        """Test search with bounding box filter"""
        mock_items = [
            {"id": "item1", "bbox": [170, -45, 175, -40], "properties": {}}
        ]
        mock_client.search_by_bbox.return_value = mock_items
        
        response = client.get("/api/search?bbox=170,-45,175,-40")
        assert response.status_code == 200
        data = response.json()
        assert len(data["items"]) == 1
        assert data["total"] == 1
        
        # Verify bbox was parsed correctly
        mock_client.search_by_bbox.assert_called_once()
        call_args = mock_client.search_by_bbox.call_args
        assert call_args[1]["bbox"] == [170.0, -45.0, 175.0, -40.0]
    
    @patch('app.main.stac_client')
    def test_search_with_temporal_filter(self, mock_client):
        """Test search with date range filter"""
        mock_items = [
            {"id": "item1", "properties": {"datetime": "2023-01-15T00:00:00Z"}}
        ]
        mock_client.search_by_datetime.return_value = mock_items
        
        response = client.get(
            "/api/search?start_date=2023-01-01T00:00:00Z&end_date=2023-12-31T23:59:59Z"
        )
        assert response.status_code == 200
        data = response.json()
        assert len(data["items"]) == 1
        
        # Verify temporal parameters were passed
        mock_client.search_by_datetime.assert_called_once()
    
    @patch('app.main.stac_client')
    def test_search_with_pagination(self, mock_client):
        """Test pagination with limit and offset"""
        # Create 10 mock items
        mock_items = [
            {"id": f"item{i}", "properties": {}} for i in range(10)
        ]
        mock_client.search_by_collection.return_value = mock_items
        
        # Request with limit=5, offset=3
        response = client.get("/api/search?collections=test&limit=5&offset=3")
        assert response.status_code == 200
        data = response.json()
        
        # Should return items 3-7 (5 items starting from offset 3)
        assert len(data["items"]) == 5
        assert data["total"] == 10
        assert data["limit"] == 5
        assert data["offset"] == 3
        assert data["items"][0]["id"] == "item3"
        assert data["items"][4]["id"] == "item7"
    
    def test_search_with_invalid_bbox(self):
        """Test that invalid bbox format returns empty results"""
        response = client.get("/api/search?bbox=invalid")
        assert response.status_code == 200
        data = response.json()
        assert data["items"] == []
        assert data["total"] == 0
    
    @patch('app.main.stac_client')
    def test_search_with_variable_filter(self, mock_client):
        """Test filtering by variable name"""
        mock_items = [
            {"id": "item1", "properties": {"variables": ["temperature", "humidity"]}},
            {"id": "item2", "properties": {"variable": "temperature"}},
            {"id": "item3", "properties": {"variables": ["pressure"]}}
        ]
        mock_client.search_by_collection.return_value = mock_items
        
        response = client.get("/api/search?collections=test&variables=temperature")
        assert response.status_code == 200
        data = response.json()
        
        # Should return only items with temperature variable
        assert len(data["items"]) == 2
        assert data["items"][0]["id"] == "item1"
        assert data["items"][1]["id"] == "item2"
    
    @patch('app.main.stac_client')
    def test_search_with_multiple_collections(self, mock_client):
        """Test search with multiple collections"""
        def mock_search_by_collection(collection, **kwargs):
            if collection == "collection1":
                return [{"id": "item1", "collection": "collection1"}]
            elif collection == "collection2":
                return [{"id": "item2", "collection": "collection2"}]
            return []
        
        mock_client.search_by_collection.side_effect = mock_search_by_collection
        
        response = client.get("/api/search?collections=collection1&collections=collection2")
        assert response.status_code == 200
        data = response.json()
        
        # Should combine results from both collections
        assert len(data["items"]) == 2
        assert data["total"] == 2


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
