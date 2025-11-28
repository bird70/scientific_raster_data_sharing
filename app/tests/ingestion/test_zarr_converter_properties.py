"""
Property-based tests for zarr_converter.py

Feature: ecs-zarr-conversion-migration
"""
import pytest
import numpy as np
import xarray as xr
from hypothesis import given, strategies as st, assume, settings
from unittest.mock import patch
import sys
import os

# Mock environment variables to prevent script execution on import
with patch.dict(os.environ, {
    'INPUT_BUCKET': 'test-bucket',
    'INPUT_KEY': 'test.nc',
    'OUTPUT_BUCKET': 'test-output'
}):
    from app.ingestion.zarr_converter import extract_bounding_box


# Strategy for generating valid latitude values
lat_strategy = st.floats(min_value=-90, max_value=90, allow_nan=False, allow_infinity=False)

# Strategy for generating valid longitude values
lon_strategy = st.floats(min_value=-180, max_value=180, allow_nan=False, allow_infinity=False)


@pytest.mark.ingestion
@given(
    west=lon_strategy,
    east=lon_strategy,
    south=lat_strategy,
    north=lat_strategy
)
@settings(max_examples=100)
def test_property_bounding_box_extraction_with_coordinates(west, east, south, north):
    """
    **Feature: ecs-zarr-conversion-migration, Property 6: Bounding Box Extraction**
    **Validates: Requirements 4.3, 4.5**
    
    For any NetCDF dataset with coordinate variables (lat, lon), the extracted
    bounding box SHALL be [west, south, east, north] where west < east and south < north.
    """
    # Ensure west < east and south < north
    assume(west < east)
    assume(south < north)
    
    # Create a test dataset with coordinate variables
    lons = np.linspace(west, east, 10)
    lats = np.linspace(south, north, 10)
    
    data = np.random.rand(10, 10)
    
    ds = xr.Dataset(
        {
            'temperature': (['lat', 'lon'], data)
        },
        coords={
            'lon': lons,
            'lat': lats
        }
    )
    
    # Extract bounding box
    bbox, is_default = extract_bounding_box(ds)
    
    # Verify properties
    assert len(bbox) == 4, "Bounding box should have 4 elements"
    assert bbox[0] < bbox[2], f"West ({bbox[0]}) should be less than East ({bbox[2]})"
    assert bbox[1] < bbox[3], f"South ({bbox[1]}) should be less than North ({bbox[3]})"
    assert not is_default, "Should not use default bbox when coordinates are present"
    
    # Verify bbox matches input coordinates (with small tolerance for floating point)
    assert abs(bbox[0] - west) < 0.01, f"West should be approximately {west}, got {bbox[0]}"
    assert abs(bbox[1] - south) < 0.01, f"South should be approximately {south}, got {bbox[1]}"
    assert abs(bbox[2] - east) < 0.01, f"East should be approximately {east}, got {bbox[2]}"
    assert abs(bbox[3] - north) < 0.01, f"North should be approximately {north}, got {bbox[3]}"


@pytest.mark.ingestion
@given(
    west=lon_strategy,
    east=lon_strategy,
    south=lat_strategy,
    north=lat_strategy
)
@settings(max_examples=100)
def test_property_bounding_box_extraction_with_attributes(west, east, south, north):
    """
    **Feature: ecs-zarr-conversion-migration, Property 6: Bounding Box Extraction**
    **Validates: Requirements 4.3, 4.5**
    
    For any NetCDF dataset with global attributes, the extracted bounding box
    SHALL be [west, south, east, north] where west < east and south < north.
    """
    # Ensure west < east and south < north
    assume(west < east)
    assume(south < north)
    
    # Create a test dataset with global attributes (no coordinate variables)
    data = np.random.rand(10, 10)
    
    ds = xr.Dataset(
        {
            'temperature': (['y', 'x'], data)
        },
        attrs={
            'geospatial_lon_min': west,
            'geospatial_lat_min': south,
            'geospatial_lon_max': east,
            'geospatial_lat_max': north
        }
    )
    
    # Extract bounding box
    bbox, is_default = extract_bounding_box(ds)
    
    # Verify properties
    assert len(bbox) == 4, "Bounding box should have 4 elements"
    assert bbox[0] < bbox[2], f"West ({bbox[0]}) should be less than East ({bbox[2]})"
    assert bbox[1] < bbox[3], f"South ({bbox[1]}) should be less than North ({bbox[3]})"
    assert not is_default, "Should not use default bbox when attributes are present"
    
    # Verify bbox matches input attributes
    assert bbox[0] == west, f"West should be {west}, got {bbox[0]}"
    assert bbox[1] == south, f"South should be {south}, got {bbox[1]}"
    assert bbox[2] == east, f"East should be {east}, got {bbox[2]}"
    assert bbox[3] == north, f"North should be {north}, got {bbox[3]}"


@pytest.mark.ingestion
def test_property_bounding_box_fallback():
    """
    **Feature: ecs-zarr-conversion-migration, Property 6: Bounding Box Extraction**
    **Validates: Requirements 4.3, 4.5**
    
    For any NetCDF dataset without geospatial metadata, the extracted bounding box
    SHALL be the global extent [-180, -90, 180, 90] with is_default=True.
    """
    # Create a dataset with no geospatial metadata
    data = np.random.rand(10, 10)
    
    ds = xr.Dataset(
        {
            'temperature': (['y', 'x'], data)
        }
    )
    
    # Extract bounding box
    bbox, is_default = extract_bounding_box(ds)
    
    # Verify fallback behavior
    assert len(bbox) == 4, "Bounding box should have 4 elements"
    assert bbox == [-180, -90, 180, 90], f"Should use global extent, got {bbox}"
    assert is_default, "Should indicate default bbox was used"
    assert bbox[0] < bbox[2], "West should be less than East"
    assert bbox[1] < bbox[3], "South should be less than North"
