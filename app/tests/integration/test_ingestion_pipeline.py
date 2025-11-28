import pytest
from unittest.mock import Mock, patch
import boto3
from moto import mock_aws
import os
import json
import time
from pathlib import Path


@mock_aws
def test_s3_upload_trigger():
    """Test S3 upload triggers ingestion pipeline"""
    # Create mock S3 bucket
    s3 = boto3.client('s3', region_name='ap-southeast-2')
    s3.create_bucket(
        Bucket='test-raw-bucket',
        CreateBucketConfiguration={'LocationConstraint': 'ap-southeast-2'}
    )
    
    # Upload test file
    s3.put_object(
        Bucket='test-raw-bucket',
        Key='ingestion/test.nc',
        Body=b'test data'
    )
    
    # Verify file exists
    response = s3.head_object(Bucket='test-raw-bucket', Key='ingestion/test.nc')
    assert response['ContentLength'] == 9


@pytest.mark.integration
@mock_aws
def test_step_functions_execution():
    """Test Step Functions state machine execution"""
    client = boto3.client('stepfunctions', region_name='ap-southeast-2')
    
    # Create mock state machine
    response = client.create_state_machine(
        name='test-ingestion-pipeline',
        definition='{"Comment": "Test", "StartAt": "Pass", "States": {"Pass": {"Type": "Pass", "End": true}}}',
        roleArn='arn:aws:iam::123456789012:role/test-role'
    )
    
    state_machine_arn = response['stateMachineArn']
    
    # Start execution
    exec_response = client.start_execution(
        stateMachineArn=state_machine_arn,
        input='{"test": true}'
    )
    
    assert 'executionArn' in exec_response


@pytest.mark.integration
@pytest.mark.skipif(
    os.environ.get('RUN_INTEGRATION_TESTS') != 'true',
    reason="Integration tests require RUN_INTEGRATION_TESTS=true and real AWS resources"
)
def test_end_to_end_pipeline():
    """
    Integration test for end-to-end ingestion pipeline.
    
    This test:
    - Uploads test NetCDF file to S3
    - Waits for Step Functions execution to complete
    - Verifies execution status is SUCCEEDED
    - Verifies all output files exist (Zarr, COG, STAC)
    - Verifies STAC item contains bounding box
    - Verifies STAC item contains both assets
    
    Requirements: All
    """
    # Get AWS configuration from environment
    region = os.environ.get('AWS_REGION', 'ap-southeast-2')
    raw_bucket = os.environ.get('RAW_BUCKET')
    zarr_bucket = os.environ.get('ZARR_BUCKET')
    cog_bucket = os.environ.get('COG_BUCKET')
    stac_bucket = os.environ.get('STAC_BUCKET', zarr_bucket)
    state_machine_arn = os.environ.get('STATE_MACHINE_ARN')
    
    # Validate required environment variables
    required_vars = {
        'RAW_BUCKET': raw_bucket,
        'ZARR_BUCKET': zarr_bucket,
        'COG_BUCKET': cog_bucket,
        'STATE_MACHINE_ARN': state_machine_arn
    }
    
    missing_vars = [k for k, v in required_vars.items() if not v]
    if missing_vars:
        pytest.skip(f"Missing required environment variables: {', '.join(missing_vars)}")
    
    # Initialize AWS clients
    s3 = boto3.client('s3', region_name=region)
    sfn = boto3.client('stepfunctions', region_name=region)
    
    # Use test NetCDF file from data directory
    test_file_path = Path(__file__).parent.parent.parent.parent / 'data' / 'A2002070120230731_MC_SST_std_coastal_v05.nc'
    
    if not test_file_path.exists():
        pytest.skip(f"Test NetCDF file not found: {test_file_path}")
    
    test_filename = test_file_path.name
    s3_key = f'ingestion/{test_filename}'
    
    try:
        # Step 1: Upload test NetCDF file to S3
        print(f"Uploading test file to s3://{raw_bucket}/{s3_key}")
        with open(test_file_path, 'rb') as f:
            s3.put_object(
                Bucket=raw_bucket,
                Key=s3_key,
                Body=f
            )
        
        # Verify upload
        s3.head_object(Bucket=raw_bucket, Key=s3_key)
        print(f"✓ Test file uploaded successfully")
        
        # Step 2: Start Step Functions execution
        execution_input = json.dumps({
            'bucket': raw_bucket,
            'key': s3_key
        })
        
        print(f"Starting Step Functions execution")
        exec_response = sfn.start_execution(
            stateMachineArn=state_machine_arn,
            input=execution_input
        )
        
        execution_arn = exec_response['executionArn']
        print(f"✓ Execution started: {execution_arn}")
        
        # Step 3: Wait for Step Functions execution to complete
        max_wait_time = 1800  # 30 minutes
        poll_interval = 30  # 30 seconds
        elapsed_time = 0
        
        print(f"Waiting for execution to complete (max {max_wait_time}s)...")
        
        while elapsed_time < max_wait_time:
            exec_status = sfn.describe_execution(executionArn=execution_arn)
            status = exec_status['status']
            
            if status == 'SUCCEEDED':
                print(f"✓ Execution succeeded after {elapsed_time}s")
                break
            elif status in ['FAILED', 'TIMED_OUT', 'ABORTED']:
                # Get execution history for debugging
                history = sfn.get_execution_history(executionArn=execution_arn)
                error_events = [
                    event for event in history['events']
                    if event['type'] in ['ExecutionFailed', 'TaskFailed', 'LambdaFunctionFailed']
                ]
                pytest.fail(f"Execution {status}: {error_events}")
            
            time.sleep(poll_interval)
            elapsed_time += poll_interval
            print(f"  Status: {status} ({elapsed_time}s elapsed)")
        
        # Verify execution status is SUCCEEDED
        final_status = sfn.describe_execution(executionArn=execution_arn)
        assert final_status['status'] == 'SUCCEEDED', f"Execution did not succeed: {final_status['status']}"
        
        # Derive expected output keys
        basename = test_filename.replace('.nc', '')
        zarr_key = f'zarr/{basename}.zarr'
        cog_key = f'cog/{basename}.tif'
        stac_key = f'stac/{basename}.json'
        
        # Step 4: Verify all output files exist
        print(f"Verifying output files...")
        
        # Verify Zarr directory exists (Zarr is stored as a directory structure)
        zarr_prefix = f'zarr/{basename}.zarr/'
        zarr_objects = s3.list_objects_v2(Bucket=zarr_bucket, Prefix=zarr_prefix, MaxKeys=1)
        if zarr_objects.get('KeyCount', 0) == 0:
            pytest.fail(f"Zarr directory not found: s3://{zarr_bucket}/{zarr_prefix}")
        print(f"✓ Zarr directory exists: s3://{zarr_bucket}/{zarr_prefix}")
        
        # Verify COG file exists
        try:
            s3.head_object(Bucket=cog_bucket, Key=cog_key)
            print(f"✓ COG file exists: s3://{cog_bucket}/{cog_key}")
        except s3.exceptions.NoSuchKey:
            pytest.fail(f"COG file not found: s3://{cog_bucket}/{cog_key}")
        
        # Verify STAC item exists
        try:
            stac_response = s3.get_object(Bucket=stac_bucket, Key=stac_key)
            stac_item = json.loads(stac_response['Body'].read())
            print(f"✓ STAC item exists: s3://{stac_bucket}/{stac_key}")
        except s3.exceptions.NoSuchKey:
            pytest.fail(f"STAC item not found: s3://{stac_bucket}/{stac_key}")
        
        # Step 5: Verify STAC item contains bounding box
        assert 'bbox' in stac_item, "STAC item missing 'bbox' field"
        assert isinstance(stac_item['bbox'], list), "STAC bbox must be a list"
        assert len(stac_item['bbox']) == 4, "STAC bbox must have 4 elements [west, south, east, north]"
        
        bbox = stac_item['bbox']
        assert bbox[0] < bbox[2], f"Invalid bbox: west ({bbox[0]}) must be < east ({bbox[2]})"
        assert bbox[1] < bbox[3], f"Invalid bbox: south ({bbox[1]}) must be < north ({bbox[3]})"
        print(f"✓ STAC item has valid bounding box: {bbox}")
        
        # Step 6: Verify STAC item contains both assets
        assert 'assets' in stac_item, "STAC item missing 'assets' field"
        assert 'zarr' in stac_item['assets'], "STAC item missing 'zarr' asset"
        assert 'cog' in stac_item['assets'], "STAC item missing 'cog' asset"
        
        # Verify asset URIs
        zarr_asset = stac_item['assets']['zarr']
        cog_asset = stac_item['assets']['cog']
        
        assert 'href' in zarr_asset, "Zarr asset missing 'href'"
        assert 'href' in cog_asset, "COG asset missing 'href'"
        
        expected_zarr_uri = f's3://{zarr_bucket}/{zarr_key}'
        expected_cog_uri = f's3://{cog_bucket}/{cog_key}'
        
        assert zarr_asset['href'] == expected_zarr_uri, \
            f"Zarr asset URI mismatch: expected {expected_zarr_uri}, got {zarr_asset['href']}"
        assert cog_asset['href'] == expected_cog_uri, \
            f"COG asset URI mismatch: expected {expected_cog_uri}, got {cog_asset['href']}"
        
        print(f"✓ STAC item has both assets with correct URIs")
        print(f"  Zarr: {zarr_asset['href']}")
        print(f"  COG: {cog_asset['href']}")
        
        print("\n✅ End-to-end integration test PASSED")
        
    finally:
        # Cleanup: Remove test files (optional, comment out to inspect results)
        cleanup = os.environ.get('CLEANUP_TEST_FILES', 'false').lower() == 'true'
        if cleanup:
            print("\nCleaning up test files...")
            try:
                s3.delete_object(Bucket=raw_bucket, Key=s3_key)
                print(f"✓ Deleted: s3://{raw_bucket}/{s3_key}")
            except Exception as e:
                print(f"⚠ Failed to delete raw file: {e}")
            
            try:
                s3.delete_object(Bucket=zarr_bucket, Key=zarr_key)
                print(f"✓ Deleted: s3://{zarr_bucket}/{zarr_key}")
            except Exception as e:
                print(f"⚠ Failed to delete zarr file: {e}")
            
            try:
                s3.delete_object(Bucket=cog_bucket, Key=cog_key)
                print(f"✓ Deleted: s3://{cog_bucket}/{cog_key}")
            except Exception as e:
                print(f"⚠ Failed to delete cog file: {e}")
            
            try:
                s3.delete_object(Bucket=stac_bucket, Key=stac_key)
                print(f"✓ Deleted: s3://{stac_bucket}/{stac_key}")
            except Exception as e:
                print(f"⚠ Failed to delete stac file: {e}")
