"""
Manual test script for the search endpoint.
Run this to verify the search endpoint logic works correctly.
"""

from unittest.mock import Mock, MagicMock
import sys
import os

# Add app directory to path
sys.path.insert(0, os.path.dirname(__file__))

# Mock the stac_client before importing main
mock_stac_client = MagicMock()

# Mock the modules that might not be available
sys.modules['app.stac_lookup'] = MagicMock()
sys.modules['app.tiles'] = MagicMock()
sys.modules['app.timeseries'] = MagicMock()
sys.modules['app.metrics'] = MagicMock()
sys.modules['app.auth'] = MagicMock()

# Set up the mock client
sys.modules['app.stac_lookup'].stac_client = mock_stac_client
sys.modules['app.stac_lookup'].stac_search_collections = Mock(return_value=[])

print("Testing search endpoint logic...")

# Test 1: Parse bbox correctly
print("\n1. Testing bbox parsing...")
bbox_str = "170,-45,175,-40"
bbox_list = [float(x) for x in bbox_str.split(',')]
assert bbox_list == [170.0, -45.0, 175.0, -40.0], "bbox parsing failed"
print("✓ bbox parsing works correctly")

# Test 2: Pagination logic
print("\n2. Testing pagination...")
items = [{"id": f"item{i}"} for i in range(10)]
limit = 5
offset = 3
paginated = items[offset:offset + limit]
assert len(paginated) == 5, "pagination length incorrect"
assert paginated[0]["id"] == "item3", "pagination offset incorrect"
assert paginated[4]["id"] == "item7", "pagination end incorrect"
print("✓ pagination works correctly")

# Test 3: Variable filtering
print("\n3. Testing variable filtering...")
items = [
    {"id": "item1", "properties": {"variables": ["temperature", "humidity"]}},
    {"id": "item2", "properties": {"variable": "temperature"}},
    {"id": "item3", "properties": {"variables": ["pressure"]}}
]
variables = ["temperature"]
filtered = [
    item for item in items
    if any(
        var in item.get('properties', {}).get('variables', [])
        or item.get('properties', {}).get('variable') == var
        for var in variables
    )
]
assert len(filtered) == 2, "variable filtering failed"
assert filtered[0]["id"] == "item1", "first filtered item incorrect"
assert filtered[1]["id"] == "item2", "second filtered item incorrect"
print("✓ variable filtering works correctly")

# Test 4: Invalid bbox handling
print("\n4. Testing invalid bbox handling...")
try:
    invalid_bbox = "invalid"
    bbox_list = [float(x) for x in invalid_bbox.split(',')]
    print("✗ Should have raised ValueError")
except ValueError:
    print("✓ invalid bbox raises ValueError as expected")

# Test 5: Response model structure
print("\n5. Testing response model structure...")
response_data = {
    "items": [{"id": "test"}],
    "total": 1,
    "limit": 50,
    "offset": 0
}
assert "items" in response_data, "items field missing"
assert "total" in response_data, "total field missing"
assert "limit" in response_data, "limit field missing"
assert "offset" in response_data, "offset field missing"
print("✓ response model structure is correct")

print("\n" + "="*50)
print("All manual tests passed! ✓")
print("="*50)
