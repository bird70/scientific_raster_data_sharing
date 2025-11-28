"""
Unit tests for STAC creator Lambda

Feature: ecs-zarr-conversion-migration, netcdf-metadata-enhancement
Tests: metadata file reading, bbox inclusion, geometry generation, asset URI generation,
       metadata validation, special character escaping, collection management
Requirements: 4.1, 4.2, 4.3, 4.5, 4.6, 6.5, 7.4, 7.5, 8.1, 8.2, 8.3, 8.4, 8.5
"""
import pytest
import json
import boto3
from moto import mock_aws
from pathlib import Path
from datetime import datetime, timezone
import sys
import os

# Add the lambda directory to the path so we can import the handler
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../../terraform/modules/ingestion/lambda/stac_creator'))

from handler import (
    escape_special_characters,
    validate_metadata_structure,
    build_stac_properties,
    create_or_update_collection,
    handle_multiple_variables
)


# Mock STAC creator functions (will be implemented in the Lambda)
def read_metadata_from_s3(s3_client, bucket, key):
    """Read metadata file from S3"""
    try:
        response = s3_client.get_object(Bucket=bucket, Key=key)
        metadata = json.loads(response['Body'].read().decode('utf-8'))
        return metadata
    except Exception as e:
        raise ValueError(f"Failed to read metadata from s3://{bucket}/{key}: {e}")


def create_stac_item_with_bbox(zarr_bucket, zarr_key, cog_bucket, cog_key, bbox):
    """Create STAC item with bounding box"""
    basename = Path(zarr_key).stem
    
    stac_item = {
        "type": "Feature",
        "stac_version": "1.0.0",
        "id": basename,
        "bbox": bbox,
        "geometry": create_geometry_from_bbox(bbox),
        "properties": {
            "datetime": datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
        },
        "assets": {
            "zarr": {
                "href": f"s3://{zarr_bucket}/{zarr_key}",
                "type": "application/vnd+zarr",
                "roles": ["data"]
            },
            "cog": {
                "href": f"s3://{cog_bucket}/{cog_key}",
                "type": "image/tiff; application=geotiff; profile=cloud-optimized",
                "roles": ["visual"]
            }
        }
    }
    
    return stac_item


def create_geometry_from_bbox(bbox):
    """Create GeoJSON polygon geometry from bounding box"""
    west, south, east, north = bbox
    
    return {
        "type": "Polygon",
        "coordinates": [[
            [west, south],   # SW corner
            [east, south],   # SE corner
            [east, north],   # NE corner
            [west, north],   # NW corner
            [west, south]    # Close the polygon
        ]]
    }


def derive_stac_key_from_input(input_key):
    """Derive STAC key from input filename"""
    basename = Path(input_key).stem
    return f"stac/{basename}.json"


@mock_aws
def test_read_metadata_from_s3():
    """Test metadata file reading from S3"""
    # Setup mock S3
    s3_client = boto3.client('s3', region_name='us-east-1')
    bucket = 'test-zarr-bucket'
    s3_client.create_bucket(Bucket=bucket)
    
    # Create metadata file
    metadata = {
        "bbox": [142.5, -38.5, 155.0, -28.0],
        "zarr_key": "zarr/test_file.zarr",
        "zarr_bucket": bucket
    }
    
    metadata_key = "zarr/test_file_metadata.json"
    s3_client.put_object(
        Bucket=bucket,
        Key=metadata_key,
        Body=json.dumps(metadata),
        ContentType='application/json'
    )
    
    # Read metadata
    result = read_metadata_from_s3(s3_client, bucket, metadata_key)
    
    # Verify
    assert result == metadata
    assert "bbox" in result
    assert len(result["bbox"]) == 4


@mock_aws
def test_read_metadata_missing_file():
    """Test metadata reading with missing file"""
    s3_client = boto3.client('s3', region_name='us-east-1')
    bucket = 'test-zarr-bucket'
    s3_client.create_bucket(Bucket=bucket)
    
    # Try to read non-existent file
    with pytest.raises(ValueError, match="Failed to read metadata"):
        read_metadata_from_s3(s3_client, bucket, "nonexistent.json")


def test_bbox_inclusion_in_stac_item():
    """Test that bbox is included in STAC item"""
    bbox = [142.5, -38.5, 155.0, -28.0]
    
    stac_item = create_stac_item_with_bbox(
        zarr_bucket="test-zarr",
        zarr_key="zarr/test_file.zarr",
        cog_bucket="test-cog",
        cog_key="cog/test_file.tif",
        bbox=bbox
    )
    
    # Verify bbox field
    assert "bbox" in stac_item
    assert stac_item["bbox"] == bbox
    assert len(stac_item["bbox"]) == 4
    
    # Verify bbox format [west, south, east, north]
    west, south, east, north = stac_item["bbox"]
    assert west < east, "West should be less than East"
    assert south < north, "South should be less than North"


def test_geometry_polygon_generation():
    """Test geometry polygon generation from bbox"""
    bbox = [142.5, -38.5, 155.0, -28.0]
    
    geometry = create_geometry_from_bbox(bbox)
    
    # Verify geometry structure
    assert geometry["type"] == "Polygon"
    assert "coordinates" in geometry
    
    # Verify polygon coordinates
    coords = geometry["coordinates"][0]
    assert len(coords) == 5, "Polygon should have 5 points (closed)"
    
    # Verify corners match bbox
    west, south, east, north = bbox
    assert coords[0] == [west, south], "First point should be SW corner"
    assert coords[1] == [east, south], "Second point should be SE corner"
    assert coords[2] == [east, north], "Third point should be NE corner"
    assert coords[3] == [west, north], "Fourth point should be NW corner"
    assert coords[4] == [west, south], "Fifth point should close the polygon"
    
    # Verify polygon is closed
    assert coords[0] == coords[4], "Polygon must be closed"


def test_geometry_with_different_bboxes():
    """Test geometry generation with various bounding boxes"""
    test_cases = [
        [0, 0, 10, 10],           # Simple positive
        [-180, -90, 180, 90],     # Global extent
        [140, -40, 160, -20],     # Australia region
        [-10, 50, 2, 60],         # Europe region
    ]
    
    for bbox in test_cases:
        geometry = create_geometry_from_bbox(bbox)
        coords = geometry["coordinates"][0]
        
        west, south, east, north = bbox
        assert coords[0] == [west, south]
        assert coords[1] == [east, south]
        assert coords[2] == [east, north]
        assert coords[3] == [west, north]
        assert coords[0] == coords[4]


def test_asset_uri_generation():
    """Test S3 URI generation for assets"""
    zarr_bucket = "my-zarr-bucket"
    zarr_key = "zarr/test_file.zarr"
    cog_bucket = "my-cog-bucket"
    cog_key = "cog/test_file.tif"
    bbox = [142.5, -38.5, 155.0, -28.0]
    
    stac_item = create_stac_item_with_bbox(
        zarr_bucket, zarr_key, cog_bucket, cog_key, bbox
    )
    
    # Verify assets exist
    assert "assets" in stac_item
    assert "zarr" in stac_item["assets"]
    assert "cog" in stac_item["assets"]
    
    # Verify zarr asset URI
    zarr_asset = stac_item["assets"]["zarr"]
    assert zarr_asset["href"] == f"s3://{zarr_bucket}/{zarr_key}"
    assert zarr_asset["type"] == "application/vnd+zarr"
    assert "roles" in zarr_asset
    
    # Verify cog asset URI
    cog_asset = stac_item["assets"]["cog"]
    assert cog_asset["href"] == f"s3://{cog_bucket}/{cog_key}"
    assert cog_asset["type"] == "image/tiff; application=geotiff; profile=cloud-optimized"
    assert "roles" in cog_asset


def test_stac_key_derivation():
    """Test STAC key derivation from input filename"""
    test_cases = [
        ("test_file.nc", "stac/test_file.json"),
        ("ingestion/test_file.nc", "stac/test_file.json"),
        ("zarr/test_file.zarr", "stac/test_file.json"),
        ("cog/test_file.tif", "stac/test_file.json"),
        ("A2002070120230731_MC_SST_std_coastal_v05.nc", "stac/A2002070120230731_MC_SST_std_coastal_v05.json"),
    ]
    
    for input_key, expected_stac_key in test_cases:
        result = derive_stac_key_from_input(input_key)
        assert result == expected_stac_key, \
            f"For input {input_key}, expected {expected_stac_key}, got {result}"


def test_stac_item_structure():
    """Test complete STAC item structure"""
    bbox = [142.5, -38.5, 155.0, -28.0]
    
    stac_item = create_stac_item_with_bbox(
        zarr_bucket="test-zarr",
        zarr_key="zarr/test_file.zarr",
        cog_bucket="test-cog",
        cog_key="cog/test_file.tif",
        bbox=bbox
    )
    
    # Verify required STAC fields
    assert stac_item["type"] == "Feature"
    assert stac_item["stac_version"] == "1.0.0"
    assert "id" in stac_item
    assert "bbox" in stac_item
    assert "geometry" in stac_item
    assert "properties" in stac_item
    assert "assets" in stac_item
    
    # Verify properties
    assert "datetime" in stac_item["properties"]
    
    # Verify STAC item is valid JSON
    json_str = json.dumps(stac_item)
    parsed = json.loads(json_str)
    assert parsed == stac_item


def test_stac_id_from_zarr_key():
    """Test STAC ID is derived from zarr key basename"""
    test_cases = [
        ("zarr/test_file.zarr", "test_file"),
        ("zarr/A2002070120230731_MC_SST_std_coastal_v05.zarr", "A2002070120230731_MC_SST_std_coastal_v05"),
        ("zarr/subdir/file.zarr", "file"),
    ]
    
    for zarr_key, expected_id in test_cases:
        stac_item = create_stac_item_with_bbox(
            zarr_bucket="test-zarr",
            zarr_key=zarr_key,
            cog_bucket="test-cog",
            cog_key="cog/test.tif",
            bbox=[0, 0, 10, 10]
        )
        
        assert stac_item["id"] == expected_id, \
            f"For zarr_key {zarr_key}, expected ID {expected_id}, got {stac_item['id']}"


@mock_aws
def test_complete_stac_creation_workflow():
    """Test complete workflow: read metadata, create STAC item"""
    # Setup mock S3
    s3_client = boto3.client('s3', region_name='us-east-1')
    zarr_bucket = 'test-zarr-bucket'
    s3_client.create_bucket(Bucket=zarr_bucket)
    
    # Create metadata file
    metadata = {
        "bbox": [142.5, -38.5, 155.0, -28.0],
        "zarr_key": "zarr/test_file.zarr",
        "zarr_bucket": zarr_bucket
    }
    
    metadata_key = "zarr/test_file_metadata.json"
    s3_client.put_object(
        Bucket=zarr_bucket,
        Key=metadata_key,
        Body=json.dumps(metadata),
        ContentType='application/json'
    )
    
    # Read metadata
    read_metadata = read_metadata_from_s3(s3_client, zarr_bucket, metadata_key)
    
    # Create STAC item
    stac_item = create_stac_item_with_bbox(
        zarr_bucket=zarr_bucket,
        zarr_key=read_metadata["zarr_key"],
        cog_bucket="test-cog-bucket",
        cog_key="cog/test_file.tif",
        bbox=read_metadata["bbox"]
    )
    
    # Verify complete STAC item
    assert stac_item["id"] == "test_file"
    assert stac_item["bbox"] == metadata["bbox"]
    assert stac_item["assets"]["zarr"]["href"] == f"s3://{zarr_bucket}/zarr/test_file.zarr"
    assert stac_item["assets"]["cog"]["href"] == "s3://test-cog-bucket/cog/test_file.tif"
    assert stac_item["geometry"]["type"] == "Polygon"


# ============================================================================
# New tests for metadata enhancement (Requirements 6.5, 7.4, 7.5, 8.1-8.5)
# ============================================================================

def test_escape_special_characters_string():
    """Test escaping special characters in strings (Requirement 8.5)"""
    # Test backslashes
    assert escape_special_characters('path\\to\\file') == 'path\\\\to\\\\file'
    
    # Test quotes
    assert escape_special_characters('He said "hello"') == 'He said \\"hello\\"'
    assert escape_special_characters("It's working") == "It\\'s working"
    
    # Test newlines and tabs
    assert escape_special_characters('line1\nline2') == 'line1\\nline2'
    assert escape_special_characters('col1\tcol2') == 'col1\\tcol2'


def test_escape_special_characters_nested():
    """Test escaping in nested structures (Requirement 8.5)"""
    # Test list
    input_list = ['normal', 'with\nnewline', 'with"quote']
    result = escape_special_characters(input_list)
    assert result == ['normal', 'with\\nnewline', 'with\\"quote']
    
    # Test dict
    input_dict = {
        'key1': 'value with\ttab',
        'key2': 'value with "quotes"'
    }
    result = escape_special_characters(input_dict)
    assert result['key1'] == 'value with\\ttab'
    assert result['key2'] == 'value with \\"quotes\\"'


def test_escape_special_characters_non_string():
    """Test that non-strings are not modified"""
    assert escape_special_characters(42) == 42
    assert escape_special_characters(3.14) == 3.14
    assert escape_special_characters(True) is True
    assert escape_special_characters(None) is None


def test_validate_metadata_structure_valid():
    """Test metadata validation with valid input (Requirement 7.5)"""
    metadata = {
        'bbox': [142.5, -38.5, 155.0, -28.0],
        'zarr_key': 'zarr/test.zarr',
        'variables': [
            {'name': 'SST', 'units': 'degC'},
            {'name': 'CHL', 'units': 'mg/m^3'}
        ],
        'global_attributes': {
            'institution': '[YOURORG]',
            'title': 'Test Dataset'
        },
        'collections': [
            {'name': 'sst', 'description': 'Sea Surface Temperature'}
        ],
        'collection_id': 'sst'
    }
    
    result = validate_metadata_structure(metadata)
    
    assert result['bbox'] == [142.5, -38.5, 155.0, -28.0]
    assert result['zarr_key'] == 'zarr/test.zarr'
    assert len(result['variables']) == 2
    assert len(result['global_attributes']) == 2
    assert len(result['collections']) == 1


def test_validate_metadata_structure_invalid_bbox():
    """Test metadata validation with invalid bbox (Requirement 7.5)"""
    # Invalid bbox structure
    metadata = {'bbox': [1, 2, 3]}  # Only 3 values
    result = validate_metadata_structure(metadata)
    assert result['bbox'] == [-180, -90, 180, 90]  # Default
    
    # Non-numeric bbox
    metadata = {'bbox': ['a', 'b', 'c', 'd']}
    result = validate_metadata_structure(metadata)
    assert result['bbox'] == [-180, -90, 180, 90]  # Default
    
    # Missing bbox
    metadata = {}
    result = validate_metadata_structure(metadata)
    assert result['bbox'] == [-180, -90, 180, 90]  # Default


def test_validate_metadata_structure_filters_none():
    """Test that None values are filtered out (Requirement 7.5)"""
    metadata = {
        'bbox': [0, 0, 10, 10],
        'variables': [
            {'name': 'SST', 'units': 'degC'},
            None,  # Should be filtered
            {'name': 'CHL', 'units': None}  # units=None should be kept
        ],
        'global_attributes': {
            'institution': '[YOURORG]',
            'title': None,  # Should be filtered
            'summary': ''  # Empty string should be filtered
        }
    }
    
    result = validate_metadata_structure(metadata)
    
    assert len(result['variables']) == 2  # None filtered out
    assert len(result['global_attributes']) == 1  # Only institution remains


def test_build_stac_properties_basic():
    """Test building STAC properties from metadata (Requirement 8.1, 8.2)"""
    metadata = {
        'variables': [
            {'name': 'SST', 'units': 'degC', 'long_name': 'Sea Surface Temperature'}
        ],
        'global_attributes': {
            'institution': '[YOURORG]',
            'title': 'Test Dataset'
        }
    }
    
    properties = build_stac_properties(metadata)
    
    # Check required datetime fields
    assert 'datetime' in properties
    assert 'created' in properties
    assert 'updated' in properties
    
    # Check variable names (Requirement 8.2)
    assert 'variables' in properties
    assert properties['variables'] == ['SST']
    
    # Check variable metadata
    assert 'variable_metadata' in properties
    assert len(properties['variable_metadata']) == 1
    
    # Check global attributes (Requirement 8.4)
    assert properties['institution'] == '[YOURORG]'
    assert properties['title'] == 'Test Dataset'


def test_build_stac_properties_units_searchable():
    """Test that units are searchable (Requirement 8.3)"""
    metadata = {
        'variables': [
            {'name': 'SST', 'units': 'degC'},
            {'name': 'temp', 'units': 'degC'},
            {'name': 'CHL', 'units': 'mg/m^3'}
        ]
    }
    
    properties = build_stac_properties(metadata)
    
    # Check units are extracted and deduplicated
    assert 'units' in properties
    assert set(properties['units']) == {'degC', 'mg/m^3'}


def test_build_stac_properties_escapes_values():
    """Test that special characters are escaped (Requirement 8.5)"""
    metadata = {
        'global_attributes': {
            'title': 'Dataset with "quotes"',
            'summary': 'Line 1\nLine 2'
        }
    }
    
    properties = build_stac_properties(metadata)
    
    assert properties['title'] == 'Dataset with \\"quotes\\"'
    assert properties['summary'] == 'Line 1\\nLine 2'


@mock_aws
def test_create_or_update_collection_new():
    """Test creating a new collection (Requirement 6.5, 7.4)"""
    s3_client = boto3.client('s3', region_name='us-east-1')
    bucket = 'test-stac-bucket'
    s3_client.create_bucket(Bucket=bucket)
    
    collection_metadata = {
        'name': 'sea-surface-temperature',
        'description': 'Sea Surface Temperature',
        'units': 'degC'
    }
    
    create_or_update_collection(
        s3_client,
        bucket,
        'sea-surface-temperature',
        collection_metadata
    )
    
    # Verify collection was created
    response = s3_client.get_object(Bucket=bucket, Key='collections/sea-surface-temperature.json')
    collection = json.loads(response['Body'].read().decode('utf-8'))
    
    assert collection['type'] == 'Collection'
    assert collection['id'] == 'sea-surface-temperature'
    assert collection['description'] == 'Sea Surface Temperature'
    assert 'degC' in collection['summaries']['units']


@mock_aws
def test_create_or_update_collection_update():
    """Test updating an existing collection (Requirement 6.5, 7.5)"""
    s3_client = boto3.client('s3', region_name='us-east-1')
    bucket = 'test-stac-bucket'
    s3_client.create_bucket(Bucket=bucket)
    
    # Create initial collection
    initial_collection = {
        'type': 'Collection',
        'id': 'sst',
        'description': 'Initial description',
        'units': 'unknown'
    }
    
    s3_client.put_object(
        Bucket=bucket,
        Key='collections/sst.json',
        Body=json.dumps(initial_collection),
        ContentType='application/json'
    )
    
    # Update with better metadata
    collection_metadata = {
        'description': 'Sea Surface Temperature',
        'units': 'degC'
    }
    
    create_or_update_collection(s3_client, bucket, 'sst', collection_metadata)
    
    # Verify collection was updated
    response = s3_client.get_object(Bucket=bucket, Key='collections/sst.json')
    collection = json.loads(response['Body'].read().decode('utf-8'))
    
    assert collection['description'] == 'Sea Surface Temperature'
    assert 'degC' in collection['summaries']['units']


@mock_aws
def test_handle_multiple_variables():
    """Test handling files with multiple variables (Requirement 7.4)"""
    s3_client = boto3.client('s3', region_name='us-east-1')
    bucket = 'test-stac-bucket'
    s3_client.create_bucket(Bucket=bucket)
    
    metadata = {
        'variables': [
            {'name': 'SST', 'units': 'degC'},
            {'name': 'CHL', 'units': 'mg/m^3'}
        ],
        'collections': [
            {'name': 'sea-surface-temperature', 'description': 'SST'},
            {'name': 'chlorophyll', 'description': 'Chlorophyll'}
        ]
    }
    
    base_stac_item = {
        'id': 'test_file',
        'bbox': [0, 0, 10, 10],
        'properties': {},
        'assets': {}
    }
    
    created_items = handle_multiple_variables(
        s3_client,
        bucket,
        metadata,
        base_stac_item
    )
    
    # Verify two items were created
    assert len(created_items) == 2
    
    # Verify items exist in S3
    for key in created_items:
        response = s3_client.get_object(Bucket=bucket, Key=key)
        item = json.loads(response['Body'].read().decode('utf-8'))
        assert 'variable' in item['properties']
        assert 'collection' in item


@mock_aws
def test_handle_single_variable():
    """Test that single variable files return empty list"""
    s3_client = boto3.client('s3', region_name='us-east-1')
    bucket = 'test-stac-bucket'
    s3_client.create_bucket(Bucket=bucket)
    
    metadata = {
        'variables': [
            {'name': 'SST', 'units': 'degC'}
        ]
    }
    
    base_stac_item = {'id': 'test_file'}
    
    created_items = handle_multiple_variables(
        s3_client,
        bucket,
        metadata,
        base_stac_item
    )
    
    # Should return empty list for single variable
    assert created_items == []


def test_build_stac_properties_with_collections():
    """Test that collection info is included in properties"""
    metadata = {
        'variables': [{'name': 'SST', 'units': 'degC'}],
        'collections': [
            {'name': 'sea-surface-temperature', 'description': 'SST', 'units': 'degC'}
        ]
    }
    
    properties = build_stac_properties(metadata)
    
    assert 'collections' in properties
    assert len(properties['collections']) == 1
    assert properties['collections'][0]['name'] == 'sea-surface-temperature'
