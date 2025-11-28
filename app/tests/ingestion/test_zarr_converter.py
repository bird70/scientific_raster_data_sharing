import pytest
from unittest.mock import Mock, patch
import os
import numpy as np
import xarray as xr

# Import with mocked environment to prevent script execution
with patch.dict(os.environ, {
    'INPUT_BUCKET': 'test-bucket',
    'INPUT_KEY': 'test.nc',
    'OUTPUT_BUCKET': 'test-output'
}):
    from app.ingestion.zarr_converter import extract_bounding_box


@pytest.mark.ingestion
def test_bounding_box_extraction_with_coordinate_variables():
    """
    Test bounding box extraction with coordinate variables
    Requirements: 4.3, 4.4, 4.5
    """
    # Create a test dataset with coordinate variables
    lons = np.array([142.5, 145.0, 147.5, 150.0, 152.5, 155.0])
    lats = np.array([-38.5, -36.0, -33.5, -31.0, -28.5])
    
    data = np.random.rand(5, 6)
    
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
    
    # Verify
    assert bbox == [142.5, -38.5, 155.0, -28.5]
    assert not is_default
    assert bbox[0] < bbox[2]  # west < east
    assert bbox[1] < bbox[3]  # south < north


@pytest.mark.ingestion
def test_bounding_box_extraction_with_global_attributes():
    """
    Test bounding box extraction with global attributes
    Requirements: 4.3, 4.4, 4.5
    """
    # Create a test dataset with global attributes (no coordinate variables)
    data = np.random.rand(10, 10)
    
    ds = xr.Dataset(
        {
            'temperature': (['y', 'x'], data)
        },
        attrs={
            'geospatial_lon_min': 142.5,
            'geospatial_lat_min': -38.5,
            'geospatial_lon_max': 155.0,
            'geospatial_lat_max': -28.0
        }
    )
    
    # Extract bounding box
    bbox, is_default = extract_bounding_box(ds)
    
    # Verify
    assert bbox == [142.5, -38.5, 155.0, -28.0]
    assert not is_default
    assert bbox[0] < bbox[2]  # west < east
    assert bbox[1] < bbox[3]  # south < north


@pytest.mark.ingestion
def test_bounding_box_fallback_when_metadata_missing():
    """
    Test fallback behavior when metadata is missing
    Requirements: 4.3, 4.4, 4.5
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
    
    # Verify fallback to global extent
    assert bbox == [-180, -90, 180, 90]
    assert is_default
    assert bbox[0] < bbox[2]  # west < east
    assert bbox[1] < bbox[3]  # south < north


@pytest.mark.ingestion
@patch.dict(os.environ, {
    'INPUT_BUCKET': 'test-raw-bucket',
    'INPUT_KEY': 'ingestion/test.nc',
    'OUTPUT_BUCKET': 'test-zarr-bucket'
})
@patch('app.ingestion.zarr_converter.boto3')
@patch('app.ingestion.zarr_converter.xr')
@patch('app.ingestion.zarr_converter.s3fs')
def test_metadata_file_creation(mock_s3fs, mock_xr, mock_boto3):
    """
    Test metadata file creation
    Requirements: 4.3, 4.4, 4.5
    """
    # Setup mocks
    mock_s3 = Mock()
    mock_boto3.client.return_value = mock_s3
    
    # Create a mock dataset with coordinates and data_vars
    mock_ds = Mock()
    mock_ds.coords = {
        'lon': Mock(values=np.array([142.5, 155.0])),
        'lat': Mock(values=np.array([-38.5, -28.0]))
    }
    mock_ds.data_vars = []  # Empty list for data variables
    mock_ds.attrs = {}  # Empty dict for attributes
    mock_xr.open_dataset.return_value = mock_ds
    
    # Mock S3FileSystem
    mock_fs = Mock()
    mock_s3fs.S3FileSystem.return_value = mock_fs
    mock_s3fs.S3Map.return_value = Mock()
    
    # Import and run the converter
    from app.ingestion.zarr_converter import convert_netcdf_to_zarr
    
    result = convert_netcdf_to_zarr()
    
    # Verify S3 operations
    mock_s3.download_file.assert_called_once()
    mock_xr.open_dataset.assert_called_once()
    mock_ds.to_zarr.assert_called_once()
    
    # Verify metadata was written to S3
    put_object_calls = [call for call in mock_s3.put_object.call_args_list]
    assert len(put_object_calls) > 0
    
    # Check that metadata contains required fields
    assert result is not None
    assert 'bbox' in result
    assert 'zarr_key' in result
    assert 'zarr_bucket' in result
    assert result['zarr_bucket'] == 'test-zarr-bucket'
    assert result['zarr_key'] == 'zarr/test.zarr'
    
    # Check that new metadata fields are present
    assert 'variables' in result
    assert 'global_attributes' in result
    assert 'collections' in result
    assert 'stac_properties' in result
    assert 'collection_id' in result
