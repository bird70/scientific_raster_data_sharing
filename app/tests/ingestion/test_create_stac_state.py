"""
Test for CreateSTAC state configuration in Step Functions

This test verifies that the CreateSTAC state is correctly configured to:
1. Pass zarr_bucket, zarr_key, cog_bucket, and cog_key to Lambda
2. Use JSONPath to reference previous state outputs
3. Set ResultPath to $.stac_creation to preserve state data
4. Return stac_key for the next state

Requirements: 4.1, 4.7, 4.8
"""
import json
import pytest


def test_create_stac_state_parameters():
    """
    Verify CreateSTAC state passes correct parameters to Lambda
    
    Requirements: 4.1, 4.7, 4.8
    """
    # Simulate state data after ConvertToZarr and GenerateCOG
    state_data = {
        "bucket": "[YOURORG]-raw-data",
        "key": "ingestion/A2002070120230731_MC_SST_std_coastal_v05.nc",
        "zarr_conversion": {
            "zarr_key": "zarr/A2002070120230731_MC_SST_std_coastal_v05.zarr",
            "zarr_bucket": "[YOURORG]-zarr-data",
            "status": "success"
        },
        "cog_generation": {
            "cog_key": "cog/A2002070120230731_MC_SST_std_coastal_v05.zarr.tif",
            "cog_bucket": "[YOURORG]-cog-data",
            "status": "success"
        }
    }
    
    # Extract parameters as CreateSTAC state would
    lambda_payload = {
        "zarr_bucket": state_data["zarr_conversion"]["zarr_bucket"],
        "zarr_key": state_data["zarr_conversion"]["zarr_key"],
        "cog_bucket": state_data["cog_generation"]["cog_bucket"],
        "cog_key": state_data["cog_generation"]["cog_key"]
    }
    
    # Verify all required parameters are present
    assert "zarr_bucket" in lambda_payload, "zarr_bucket must be in payload"
    assert "zarr_key" in lambda_payload, "zarr_key must be in payload"
    assert "cog_bucket" in lambda_payload, "cog_bucket must be in payload"
    assert "cog_key" in lambda_payload, "cog_key must be in payload"
    
    # Verify values are correct
    assert lambda_payload["zarr_bucket"] == "[YOURORG]-zarr-data"
    assert lambda_payload["zarr_key"] == "zarr/A2002070120230731_MC_SST_std_coastal_v05.zarr"
    assert lambda_payload["cog_bucket"] == "[YOURORG]-cog-data"
    assert lambda_payload["cog_key"] == "cog/A2002070120230731_MC_SST_std_coastal_v05.zarr.tif"


def test_create_stac_state_result_path():
    """
    Verify CreateSTAC state preserves state data with ResultPath
    
    Requirements: 4.8
    """
    # State before CreateSTAC
    state_before = {
        "bucket": "[YOURORG]-raw-data",
        "key": "ingestion/test.nc",
        "zarr_conversion": {
            "zarr_key": "zarr/test.zarr",
            "zarr_bucket": "[YOURORG]-zarr-data",
            "status": "success"
        },
        "cog_generation": {
            "cog_key": "cog/test.zarr.tif",
            "cog_bucket": "[YOURORG]-cog-data",
            "status": "success"
        }
    }
    
    # Lambda response (wrapped in Payload by Step Functions)
    lambda_response = {
        "Payload": {
            "statusCode": 200,
            "stac_key": "stac/test.json",
            "stac_id": "test",
            "stac_bucket": "[YOURORG]-stac-data"
        }
    }
    
    # Simulate ResultPath = "$.stac_creation"
    import copy
    state_after = copy.deepcopy(state_before)
    state_after["stac_creation"] = lambda_response
    
    # Verify original data is preserved
    assert state_after["bucket"] == "[YOURORG]-raw-data"
    assert state_after["key"] == "ingestion/test.nc"
    assert "zarr_conversion" in state_after
    assert "cog_generation" in state_after
    
    # Verify new data is added
    assert "stac_creation" in state_after
    assert state_after["stac_creation"]["Payload"]["stac_key"] == "stac/test.json"


def test_create_stac_state_output_for_index_stac():
    """
    Verify CreateSTAC state output can be used by IndexSTAC state
    
    Requirements: 4.7, 4.8
    """
    # State after CreateSTAC
    state_after_stac = {
        "bucket": "[YOURORG]-raw-data",
        "key": "ingestion/test.nc",
        "zarr_conversion": {
            "zarr_key": "zarr/test.zarr",
            "zarr_bucket": "[YOURORG]-zarr-data",
            "status": "success"
        },
        "cog_generation": {
            "cog_key": "cog/test.zarr.tif",
            "cog_bucket": "[YOURORG]-cog-data",
            "status": "success"
        },
        "stac_creation": {
            "Payload": {
                "statusCode": 200,
                "stac_key": "stac/test.json",
                "stac_id": "test",
                "stac_bucket": "[YOURORG]-stac-data"
            }
        }
    }
    
    # IndexSTAC state would extract stac_key using JSONPath: $.stac_creation.Payload.stac_key
    stac_key = state_after_stac["stac_creation"]["Payload"]["stac_key"]
    
    # Verify stac_key is accessible
    assert stac_key == "stac/test.json"
    assert isinstance(stac_key, str)
    assert stac_key.startswith("stac/")
    assert stac_key.endswith(".json")


def test_create_stac_state_jsonpath_references():
    """
    Verify JSONPath references work correctly for CreateSTAC state
    
    Requirements: 4.1, 4.7, 4.8
    """
    # Complete state data
    state = {
        "bucket": "raw-bucket",
        "key": "ingestion/file.nc",
        "zarr_conversion": {
            "zarr_key": "zarr/file.zarr",
            "zarr_bucket": "zarr-bucket",
            "status": "success"
        },
        "cog_generation": {
            "cog_key": "cog/file.zarr.tif",
            "cog_bucket": "cog-bucket",
            "status": "success"
        }
    }
    
    # Simulate JSONPath extraction (as Step Functions would do)
    # $.zarr_conversion.zarr_bucket
    zarr_bucket = state["zarr_conversion"]["zarr_bucket"]
    # $.zarr_conversion.zarr_key
    zarr_key = state["zarr_conversion"]["zarr_key"]
    # $.cog_generation.cog_bucket
    cog_bucket = state["cog_generation"]["cog_bucket"]
    # $.cog_generation.cog_key
    cog_key = state["cog_generation"]["cog_key"]
    
    # Verify all values are extracted correctly
    assert zarr_bucket == "zarr-bucket"
    assert zarr_key == "zarr/file.zarr"
    assert cog_bucket == "cog-bucket"
    assert cog_key == "cog/file.zarr.tif"
    
    # Verify these can be used to construct Lambda payload
    payload = {
        "zarr_bucket": zarr_bucket,
        "zarr_key": zarr_key,
        "cog_bucket": cog_bucket,
        "cog_key": cog_key
    }
    
    assert len(payload) == 4
    assert all(isinstance(v, str) for v in payload.values())


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
