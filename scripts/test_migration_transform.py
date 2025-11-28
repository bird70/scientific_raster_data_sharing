#!/usr/bin/env python3
"""
Quick test to verify the migration transform function works correctly.
"""

import sys
sys.path.insert(0, 'scripts')

from migrate_stac_to_dynamodb import transform_item

# Sample OpenSearch STAC item
opensearch_item = {
    'id': 'test-item-123',
    'type': 'Feature',
    'geometry': {
        'type': 'Polygon',
        'coordinates': [[[150, -35], [151, -35], [151, -34], [150, -34], [150, -35]]]
    },
    'bbox': [150.0, -35.0, 151.0, -34.0],
    'properties': {
        'datetime': '2024-01-01T00:00:00Z',
        'title': 'Test Dataset'
    },
    'assets': {
        'zarr': {
            'href': 's3://bucket/test.zarr',
            'type': 'application/vnd+zarr'
        }
    },
    'collection': 'test-collection',
    'stac_version': '1.0.0'
}

# Transform to DynamoDB format
dynamodb_item = transform_item(opensearch_item)

# Verify transformation
assert dynamodb_item['id'] == 'test-item-123', "ID mismatch"
assert dynamodb_item['collection'] == 'test-collection', "Collection mismatch"
assert dynamodb_item['datetime'] == '2024-01-01T00:00:00Z', "Datetime mismatch"
assert 'geometry' in dynamodb_item, "Missing geometry"
assert 'bbox' in dynamodb_item, "Missing bbox"
assert 'properties' in dynamodb_item, "Missing properties"
assert 'assets' in dynamodb_item, "Missing assets"
assert dynamodb_item['type'] == 'Feature', "Type mismatch"
assert dynamodb_item['stac_version'] == '1.0.0', "STAC version mismatch"

print('✓ Transform function works correctly')
print(f'✓ Transformed item has {len(dynamodb_item)} fields')
print(f'✓ Collection: {dynamodb_item["collection"]}')
print(f'✓ Datetime: {dynamodb_item["datetime"]}')
print('✓ All required STAC fields present')
print('\nTest passed!')
