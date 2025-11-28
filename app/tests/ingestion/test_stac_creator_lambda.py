"""
Test the actual STAC creator Lambda handler

Feature: ecs-zarr-conversion-migration
"""
import pytest
import json
import sys
import os
from pathlib import Path
from moto import mock_aws
import boto3
from unittest.mock import patch

# Add the Lambda handler directory to the path
lambda_dir = Path(__file__).parent.parent.parent.parent / "terraform" / "modules" / "ingestion" / "lambda" / "stac_creator"
sys.path.insert(0, str(lambda_dir))


@mock_aws
def test_lambda_handler_with_metadata():
    """Test Lambda handler with complete metadata"""
    # Setup mock S3
    mock_s3 = boto3.client('s3', region_name='us-east-1')
    zarr_bucket = 'test-zarr-bucket'
    cog_bucket = 'test-cog-bucket'
    mock_s3.create_bucket(Bucket=zarr_bucket)
    mock_s3.create_bucket(Bucket=cog_bucket)
    
    # Create metadata file
    metadata = {
        "bbox": [142.5, -38.5, 155.0, -28.0],
        "zarr_key": "zarr/test_file.zarr",
        "zarr_bucket": zarr_bucket
    }
    
    metadata_key = "zarr/test_file_metadata.json"
    mock_s3.put_object(
        Bucket=zarr_bucket,
        Key=metadata_key,
        Body=json.dumps(metadata),
        ContentType='application/json'
    )
    
    # Create Lambda event
    event = {
        'zarr_bucket': zarr_bucket,
        'zarr_key': 'zarr/test_file.zarr',
        'cog_bucket': cog_bucket,
        'cog_key': 'cog/test_file.tif'
    }
    
    # Set environment variable
    os.environ['STAC_BUCKET'] = zarr_bucket
    
    # Patch the s3_client in the handler module
    with patch('handler.s3_client', mock_s3):
        # Import after patching
        from handler import lambda_handler
        
        # Invoke Lambda handler
        response = lambda_handler(event, None)
    
    # Verify response
    assert response['statusCode'] == 200
    assert 'stac_key' in response
    assert response['stac_key'] == 'stac/test_file.json'
    
    # Verify STAC item was written to S3
    stac_obj = mock_s3.get_object(Bucket=zarr_bucket, Key=response['stac_key'])
    stac_item = json.loads(stac_obj['Body'].read().decode('utf-8'))
    
    # Verify STAC item structure
    assert stac_item['id'] == 'test_file'
    assert stac_item['bbox'] == metadata['bbox']
    assert stac_item['geometry']['type'] == 'Polygon'
    assert stac_item['assets']['zarr']['href'] == f"s3://{zarr_bucket}/zarr/test_file.zarr"
    assert stac_item['assets']['cog']['href'] == f"s3://{cog_bucket}/cog/test_file.tif"


def test_create_geometry_from_bbox():
    """Test geometry creation function"""
    from handler import create_geometry_from_bbox
    
    bbox = [142.5, -38.5, 155.0, -28.0]
    geometry = create_geometry_from_bbox(bbox)
    
    assert geometry['type'] == 'Polygon'
    coords = geometry['coordinates'][0]
    assert len(coords) == 5
    assert coords[0] == coords[4]  # Closed polygon


def test_derive_stac_key():
    """Test STAC key derivation"""
    from handler import derive_stac_key
    
    assert derive_stac_key('zarr/test.zarr') == 'stac/test.json'
    assert derive_stac_key('zarr/A2002070120230731_MC_SST_std_coastal_v05.zarr') == 'stac/A2002070120230731_MC_SST_std_coastal_v05.json'


@mock_aws
def test_read_metadata_from_s3():
    """Test metadata reading function"""
    from handler import read_metadata_from_s3
    
    s3 = boto3.client('s3', region_name='us-east-1')
    bucket = 'test-bucket'
    s3.create_bucket(Bucket=bucket)
    
    metadata = {"bbox": [0, 0, 10, 10]}
    s3.put_object(
        Bucket=bucket,
        Key='test.json',
        Body=json.dumps(metadata)
    )
    
    result = read_metadata_from_s3(bucket, 'test.json', client=s3)
    assert result == metadata
