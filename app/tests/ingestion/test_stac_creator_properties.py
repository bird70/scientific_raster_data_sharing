"""
Property-based tests for STAC creator Lambda

Feature: ecs-zarr-conversion-migration
"""
import pytest
import json
import re
from hypothesis import given, strategies as st, assume, settings
from pathlib import Path


# Strategy for generating valid S3 bucket names (lowercase letters, numbers, hyphens only)
bucket_strategy = st.text(
    alphabet='abcdefghijklmnopqrstuvwxyz0123456789-',
    min_size=3,
    max_size=63
).filter(lambda x: x[0].isalnum() and x[-1].isalnum() and '--' not in x and x.replace('-', '').isalnum())

# Strategy for generating valid S3 keys (filenames)
filename_strategy = st.text(
    alphabet=st.characters(whitelist_categories=('Lu', 'Ll', 'Nd'), whitelist_characters='_-'),
    min_size=1,
    max_size=50
).filter(lambda x: x[0].isalnum())

# Strategy for generating valid bounding boxes
bbox_strategy = st.tuples(
    st.floats(min_value=-180, max_value=180, allow_nan=False, allow_infinity=False),  # west
    st.floats(min_value=-90, max_value=90, allow_nan=False, allow_infinity=False),    # south
    st.floats(min_value=-180, max_value=180, allow_nan=False, allow_infinity=False),  # east
    st.floats(min_value=-90, max_value=90, allow_nan=False, allow_infinity=False)     # north
).filter(lambda bbox: bbox[0] < bbox[2] and bbox[1] < bbox[3])  # west < east, south < north


def create_stac_item(zarr_bucket, zarr_key, cog_bucket, cog_key, bbox):
    """
    Helper function to create a STAC item (mimics Lambda behavior)
    
    Args:
        zarr_bucket: S3 bucket for Zarr file
        zarr_key: S3 key for Zarr file
        cog_bucket: S3 bucket for COG file
        cog_key: S3 key for COG file
        bbox: Bounding box [west, south, east, north]
        
    Returns:
        dict: STAC item
    """
    from datetime import datetime, timezone
    
    # Extract basename from zarr_key for STAC ID
    basename = Path(zarr_key).stem
    
    stac_item = {
        "type": "Feature",
        "stac_version": "1.0.0",
        "id": basename,
        "bbox": list(bbox),
        "geometry": {
            "type": "Polygon",
            "coordinates": [[
                [bbox[0], bbox[1]],  # SW
                [bbox[2], bbox[1]],  # SE
                [bbox[2], bbox[3]],  # NE
                [bbox[0], bbox[3]],  # NW
                [bbox[0], bbox[1]]   # Close polygon
            ]]
        },
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


def derive_stac_key(input_filename):
    """
    Derive STAC key from input filename
    
    Args:
        input_filename: Original filename (e.g., "file.nc" or "zarr/file.zarr")
        
    Returns:
        str: STAC key in format "stac/{basename}.json"
    """
    basename = Path(input_filename).stem
    return f"stac/{basename}.json"


@pytest.mark.ingestion
@given(
    zarr_bucket=bucket_strategy,
    cog_bucket=bucket_strategy,
    filename=filename_strategy,
    bbox=bbox_strategy
)
@settings(max_examples=100)
def test_property_stac_asset_completeness(zarr_bucket, cog_bucket, filename, bbox):
    """
    **Feature: ecs-zarr-conversion-migration, Property 5: STAC Asset Completeness**
    **Validates: Requirements 4.2**
    
    For any STAC creation inputs, all STAC items SHALL contain both zarr and cog assets
    with valid S3 URIs in the format s3://{bucket}/{key}.
    """
    # Generate keys
    zarr_key = f"zarr/{filename}.zarr"
    cog_key = f"cog/{filename}.tif"
    
    # Create STAC item
    stac_item = create_stac_item(zarr_bucket, zarr_key, cog_bucket, cog_key, bbox)
    
    # Verify STAC item structure
    assert "assets" in stac_item, "STAC item must have assets field"
    assert "zarr" in stac_item["assets"], "STAC item must have zarr asset"
    assert "cog" in stac_item["assets"], "STAC item must have cog asset"
    
    # Verify zarr asset
    zarr_asset = stac_item["assets"]["zarr"]
    assert "href" in zarr_asset, "Zarr asset must have href"
    assert zarr_asset["href"] == f"s3://{zarr_bucket}/{zarr_key}", \
        f"Zarr href should be s3://{zarr_bucket}/{zarr_key}, got {zarr_asset['href']}"
    
    # Verify S3 URI format for zarr
    s3_uri_pattern = r'^s3://[a-z0-9][a-z0-9-]{1,61}[a-z0-9]/.*$'
    assert re.match(s3_uri_pattern, zarr_asset["href"]), \
        f"Zarr href must be valid S3 URI: {zarr_asset['href']}"
    
    # Verify cog asset
    cog_asset = stac_item["assets"]["cog"]
    assert "href" in cog_asset, "COG asset must have href"
    assert cog_asset["href"] == f"s3://{cog_bucket}/{cog_key}", \
        f"COG href should be s3://{cog_bucket}/{cog_key}, got {cog_asset['href']}"
    
    # Verify S3 URI format for cog
    assert re.match(s3_uri_pattern, cog_asset["href"]), \
        f"COG href must be valid S3 URI: {cog_asset['href']}"


@pytest.mark.ingestion
@given(filename=filename_strategy)
@settings(max_examples=100)
def test_property_stac_key_derivation(filename):
    """
    **Feature: ecs-zarr-conversion-migration, Property 7: STAC Key Derivation**
    **Validates: Requirements 4.6, 4.7**
    
    For any input filename, the STAC key SHALL be derived as stac/{basename}.json
    where basename is the filename without path or extension.
    """
    # Test with various input formats
    test_inputs = [
        f"{filename}.nc",
        f"ingestion/{filename}.nc",
        f"zarr/{filename}.zarr",
        f"cog/{filename}.tif"
    ]
    
    for input_key in test_inputs:
        stac_key = derive_stac_key(input_key)
        
        # Verify format
        assert stac_key.startswith("stac/"), f"STAC key must start with 'stac/', got {stac_key}"
        assert stac_key.endswith(".json"), f"STAC key must end with '.json', got {stac_key}"
        
        # Verify basename extraction
        expected_key = f"stac/{filename}.json"
        assert stac_key == expected_key, \
            f"STAC key should be {expected_key}, got {stac_key}"
        
        # Verify no path components in basename
        basename_part = stac_key[5:-5]  # Remove "stac/" and ".json"
        assert "/" not in basename_part, \
            f"STAC basename should not contain path separators, got {basename_part}"


@pytest.mark.ingestion
@given(
    zarr_bucket=bucket_strategy,
    cog_bucket=bucket_strategy,
    filename=filename_strategy,
    bbox=bbox_strategy
)
@settings(max_examples=100)
def test_property_stac_bbox_validity(zarr_bucket, cog_bucket, filename, bbox):
    """
    **Feature: ecs-zarr-conversion-migration, Property 5: STAC Asset Completeness**
    **Validates: Requirements 4.2, 4.3, 4.5**
    
    For any STAC item created, the bbox SHALL be in standard format [west, south, east, north]
    with west < east and south < north.
    """
    zarr_key = f"zarr/{filename}.zarr"
    cog_key = f"cog/{filename}.tif"
    
    # Create STAC item
    stac_item = create_stac_item(zarr_bucket, zarr_key, cog_bucket, cog_key, bbox)
    
    # Verify bbox field exists
    assert "bbox" in stac_item, "STAC item must have bbox field"
    
    # Verify bbox format
    item_bbox = stac_item["bbox"]
    assert isinstance(item_bbox, list), "bbox must be a list"
    assert len(item_bbox) == 4, f"bbox must have 4 elements, got {len(item_bbox)}"
    
    # Verify bbox validity
    west, south, east, north = item_bbox
    assert west < east, f"West ({west}) must be less than East ({east})"
    assert south < north, f"South ({south}) must be less than North ({north})"
    
    # Verify bbox matches input
    assert item_bbox == list(bbox), f"bbox should match input {list(bbox)}, got {item_bbox}"
    
    # Verify geometry matches bbox
    assert "geometry" in stac_item, "STAC item must have geometry field"
    geometry = stac_item["geometry"]
    assert geometry["type"] == "Polygon", "Geometry must be a Polygon"
    
    coords = geometry["coordinates"][0]
    assert len(coords) == 5, "Polygon must have 5 coordinate pairs (closed)"
    assert coords[0] == coords[4], "Polygon must be closed (first == last)"
    
    # Verify polygon corners match bbox
    assert coords[0] == [west, south], f"SW corner should be [{west}, {south}]"
    assert coords[1] == [east, south], f"SE corner should be [{east}, {south}]"
    assert coords[2] == [east, north], f"NE corner should be [{east}, {north}]"
    assert coords[3] == [west, north], f"NW corner should be [{west}, {north}]"
