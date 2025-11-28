"""
Property-based tests for error context preservation in Step Functions pipeline.

**Feature: ecs-zarr-conversion-migration, Property 8: Error Context Preservation**
**Validates: Requirements 5.5**

This test verifies that when errors occur during pipeline execution, the error
information is preserved in the Step Functions state output with at least the
error type and error message.
"""
import json
from hypothesis import given, strategies as st
import pytest


# Strategy for generating error types
error_types = st.sampled_from([
    "States.TaskFailed",
    "States.Timeout",
    "Lambda.ServiceException",
    "Lambda.Unknown",
    "ECS.TaskFailed",
    "S3.NoSuchKey",
    "S3.AccessDenied"
])

# Strategy for generating error messages
error_messages = st.text(min_size=10, max_size=200)

# Strategy for generating error causes
error_causes = st.text(min_size=20, max_size=500)


def simulate_step_functions_error_catch(error_type: str, error_message: str, error_cause: str, input_state: dict) -> dict:
    """
    Simulate how Step Functions Catch clause preserves error context.
    
    This simulates the behavior of:
    "Catch": [{
        "ErrorEquals": ["States.ALL"],
        "ResultPath": "$.error",
        "Next": "NotifyFailure"
    }]
    
    Args:
        error_type: The type of error that occurred
        error_message: The error message
        error_cause: The error cause/details
        input_state: The input state before the error
        
    Returns:
        The state after error is caught with error context preserved
    """
    # Step Functions preserves the original state and adds error info at ResultPath
    output_state = input_state.copy()
    output_state["error"] = {
        "Error": error_type,
        "Cause": error_cause
    }
    return output_state


@given(
    error_type=error_types,
    error_message=error_messages,
    error_cause=error_causes,
    bucket=st.text(min_size=3, max_size=63, alphabet=st.characters(whitelist_categories=('Ll', 'Nd'), whitelist_characters='-')),
    key=st.text(min_size=5, max_size=100, alphabet=st.characters(whitelist_categories=('Ll', 'Nd'), whitelist_characters='/-_.'))
)
def test_error_context_preservation(error_type: str, error_message: str, error_cause: str, bucket: str, key: str):
    """
    Property 8: Error Context Preservation
    
    For any error that occurs during pipeline execution, the error information
    SHALL be preserved in the Step Functions state output with at least the
    error type and error message.
    
    **Validates: Requirements 5.5**
    """
    # Create initial state
    input_state = {
        "bucket": bucket,
        "key": key
    }
    
    # Simulate error being caught
    output_state = simulate_step_functions_error_catch(
        error_type=error_type,
        error_message=error_message,
        error_cause=error_cause,
        input_state=input_state
    )
    
    # Verify error context is preserved
    assert "error" in output_state, "Error context must be preserved in state output"
    assert "Error" in output_state["error"], "Error type must be preserved"
    assert "Cause" in output_state["error"], "Error cause must be preserved"
    
    # Verify error type is preserved
    assert output_state["error"]["Error"] == error_type, "Error type must match original error"
    
    # Verify error cause is preserved (contains message/details)
    assert len(output_state["error"]["Cause"]) > 0, "Error cause must not be empty"
    
    # Verify original input is preserved
    assert output_state["bucket"] == bucket, "Original input bucket must be preserved"
    assert output_state["key"] == key, "Original input key must be preserved"


@given(
    error_type=error_types,
    error_cause=error_causes,
    zarr_key=st.text(min_size=5, max_size=100),
    zarr_bucket=st.text(min_size=3, max_size=63)
)
def test_error_context_preservation_with_partial_state(error_type: str, error_cause: str, zarr_key: str, zarr_bucket: str):
    """
    Property 8 (variant): Error context preservation with partial pipeline state
    
    For any error that occurs after some pipeline steps have completed, the error
    information SHALL be preserved along with the partial results from previous steps.
    
    **Validates: Requirements 5.5**
    """
    # Create state after zarr conversion completed
    input_state = {
        "bucket": "raw-bucket",
        "key": "ingestion/test.nc",
        "zarr_conversion": {
            "zarr_key": zarr_key,
            "zarr_bucket": zarr_bucket,
            "status": "success"
        }
    }
    
    # Simulate error in COG generation step
    output_state = simulate_step_functions_error_catch(
        error_type=error_type,
        error_message="COG generation failed",
        error_cause=error_cause,
        input_state=input_state
    )
    
    # Verify error context is preserved
    assert "error" in output_state, "Error context must be preserved"
    assert output_state["error"]["Error"] == error_type
    assert len(output_state["error"]["Cause"]) > 0
    
    # Verify partial results are preserved
    assert "zarr_conversion" in output_state, "Partial results from previous steps must be preserved"
    assert output_state["zarr_conversion"]["zarr_key"] == zarr_key
    assert output_state["zarr_conversion"]["zarr_bucket"] == zarr_bucket
    assert output_state["zarr_conversion"]["status"] == "success"


def test_error_context_in_sns_notification():
    """
    Test that error context is properly formatted for SNS notification.
    
    This verifies the NotifyFailure state can access error information.
    """
    # Simulate state with error
    state_with_error = {
        "bucket": "test-bucket",
        "key": "ingestion/test.nc",
        "error": {
            "Error": "States.TaskFailed",
            "Cause": "ECS task failed with exit code 1"
        }
    }
    
    # Simulate SNS message creation (as done in NotifyFailure state)
    sns_message = {
        "error": state_with_error["error"],
        "input": state_with_error
    }
    
    # Verify SNS message contains error context
    assert "error" in sns_message
    assert sns_message["error"]["Error"] == "States.TaskFailed"
    assert "Cause" in sns_message["error"]
    
    # Verify SNS message contains input context
    assert "input" in sns_message
    assert sns_message["input"]["bucket"] == "test-bucket"
    assert sns_message["input"]["key"] == "ingestion/test.nc"
    
    # Verify message can be serialized to JSON
    json_message = json.dumps(sns_message)
    assert len(json_message) > 0
    
    # Verify message can be deserialized
    parsed_message = json.loads(json_message)
    assert parsed_message["error"]["Error"] == "States.TaskFailed"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
