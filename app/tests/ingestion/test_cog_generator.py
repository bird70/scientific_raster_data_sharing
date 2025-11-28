import pytest
from unittest.mock import Mock, patch
import os


@pytest.mark.ingestion
@patch.dict(os.environ, {
    'ZARR_BUCKET': 'test-zarr-bucket',
    'ZARR_KEY': 'test.zarr',
    'OUTPUT_BUCKET': 'test-cog-bucket'
})
@patch('app.ingestion.cog_generator.boto3')
@patch('app.ingestion.cog_generator.xr')
@patch('app.ingestion.cog_generator.rioxarray')
def test_cog_generator_success(mock_rioxarray, mock_xr, mock_boto3):
    """Test successful Zarr to COG conversion"""
    mock_s3 = Mock()
    mock_boto3.client.return_value = mock_s3
    
    mock_ds = Mock()
    mock_xr.open_zarr.return_value = mock_ds
    mock_ds.rio.to_raster = Mock()
    
    from app.ingestion import cog_generator
    
    mock_xr.open_zarr.assert_called_once()
    mock_ds.rio.to_raster.assert_called()


@pytest.mark.ingestion
@patch.dict(os.environ, {
    'ZARR_BUCKET': 'test-zarr-bucket',
    'ZARR_KEY': 'test.zarr',
    'OUTPUT_BUCKET': 'test-cog-bucket'
})
@patch('app.ingestion.cog_generator.xr')
def test_cog_generator_zarr_error(mock_xr):
    """Test generator handles Zarr read errors"""
    mock_xr.open_zarr.side_effect = Exception("Zarr error")
    
    with pytest.raises(Exception):
        from app.ingestion import cog_generator
