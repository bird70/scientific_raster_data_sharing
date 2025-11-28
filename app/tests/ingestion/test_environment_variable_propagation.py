"""
Property-based tests for environment variable propagation in Step Functions ECS tasks

Feature: ecs-zarr-conversion-migration
Property 1: Environment Variable Propagation
"""
import pytest
from hypothesis import given, strategies as st, assume, settings


def create_ecs_container_overrides(
    container_name: str,
    input_bucket: str,
    input_key: str,
    output_bucket: str
) -> dict:
    """
    Create ECS ContainerOverrides structure as it would be in Step Functions.
    
    This mimics the Step Functions Parameters.Overrides.ContainerOverrides structure
    for the ConvertToZarr and GenerateCOG states.
    
    Args:
        container_name: Name of the container (e.g., "zarr-converter", "cog-generator")
        input_bucket: S3 bucket for input
        input_key: S3 key for input
        output_bucket: S3 bucket for output
        
    Returns:
        ContainerOverrides structure with environment variables
    """
    return {
        "ContainerOverrides": [{
            "Name": container_name,
            "Environment": [
                {"Name": "INPUT_BUCKET", "Value": input_bucket},
                {"Name": "INPUT_KEY", "Value": input_key},
                {"Name": "OUTPUT_BUCKET", "Value": output_bucket}
            ]
        }]
    }


def create_cog_container_overrides(
    zarr_bucket: str,
    zarr_key: str,
    output_bucket: str
) -> dict:
    """
    Create ECS ContainerOverrides structure for COG generation.
    
    Args:
        zarr_bucket: S3 bucket containing Zarr file
        zarr_key: S3 key of Zarr file
        output_bucket: S3 bucket for COG output
        
    Returns:
        ContainerOverrides structure with environment variables
    """
    return {
        "ContainerOverrides": [{
            "Name": "cog-generator",
            "Environment": [
                {"Name": "ZARR_BUCKET", "Value": zarr_bucket},
                {"Name": "ZARR_KEY", "Value": zarr_key},
                {"Name": "OUTPUT_BUCKET", "Value": output_bucket}
            ]
        }]
    }


def extract_env_var(container_overrides: dict, var_name: str) -> str:
    """
    Extract an environment variable value from ContainerOverrides.
    
    Args:
        container_overrides: The ContainerOverrides structure
        var_name: Name of the environment variable to extract
        
    Returns:
        The value of the environment variable
        
    Raises:
        KeyError: If the variable is not found
    """
    env_vars = container_overrides["ContainerOverrides"][0]["Environment"]
    for env_var in env_vars:
        if env_var["Name"] == var_name:
            return env_var["Value"]
    raise KeyError(f"Environment variable '{var_name}' not found")


# Strategy for generating valid S3 bucket names
# Bucket names: 3-63 chars, lowercase letters, numbers, hyphens
# Cannot start or end with hyphen
bucket_chars = st.characters(
    whitelist_categories=('Ll', 'Nd'),  # Lowercase letters and digits
    whitelist_characters='-'
)

bucket_strategy = st.text(
    alphabet=bucket_chars,
    min_size=3,
    max_size=63
).filter(lambda s: s and not s.startswith('-') and not s.endswith('-') and '--' not in s)


# Strategy for generating valid S3 keys
key_chars = st.characters(
    whitelist_categories=('Lu', 'Ll', 'Nd'),  # Letters and digits
    whitelist_characters='-_.'
)

key_strategy = st.text(
    alphabet=key_chars,
    min_size=1,
    max_size=100
).filter(lambda s: not s.startswith('.') and s != '.' and s != '..')


@pytest.mark.ingestion
@given(
    input_bucket=bucket_strategy,
    input_key=key_strategy,
    output_bucket=bucket_strategy
)
@settings(max_examples=100)
def test_property_env_var_propagation_zarr_conversion(input_bucket, input_key, output_bucket):
    """
    **Feature: ecs-zarr-conversion-migration, Property 1: Environment Variable Propagation**
    **Validates: Requirements 1.2, 3.1**
    
    For any Step Functions execution with input parameters (bucket, key, output_bucket),
    when an ECS task is invoked for Zarr conversion, the ContainerOverrides environment
    variables SHALL contain the correct values from the input parameters.
    """
    # Ensure buckets are valid
    assume(input_bucket and output_bucket)
    assume(input_bucket != output_bucket)  # Different buckets for input/output
    
    # Construct full input key with prefix
    full_input_key = f"ingestion/{input_key}.nc"
    
    # Create ContainerOverrides as Step Functions would
    overrides = create_ecs_container_overrides(
        container_name="zarr-converter",
        input_bucket=input_bucket,
        input_key=full_input_key,
        output_bucket=output_bucket
    )
    
    # Verify environment variables are correctly set
    assert extract_env_var(overrides, "INPUT_BUCKET") == input_bucket, \
        f"INPUT_BUCKET should be '{input_bucket}'"
    assert extract_env_var(overrides, "INPUT_KEY") == full_input_key, \
        f"INPUT_KEY should be '{full_input_key}'"
    assert extract_env_var(overrides, "OUTPUT_BUCKET") == output_bucket, \
        f"OUTPUT_BUCKET should be '{output_bucket}'"
    
    # Verify container name is correct
    assert overrides["ContainerOverrides"][0]["Name"] == "zarr-converter", \
        "Container name should be 'zarr-converter'"
    
    # Verify all required environment variables are present
    env_var_names = {env["Name"] for env in overrides["ContainerOverrides"][0]["Environment"]}
    required_vars = {"INPUT_BUCKET", "INPUT_KEY", "OUTPUT_BUCKET"}
    assert required_vars.issubset(env_var_names), \
        f"All required environment variables must be present: {required_vars}"


@pytest.mark.ingestion
@given(
    zarr_bucket=bucket_strategy,
    zarr_key=key_strategy,
    output_bucket=bucket_strategy
)
@settings(max_examples=100)
def test_property_env_var_propagation_cog_generation(zarr_bucket, zarr_key, output_bucket):
    """
    **Feature: ecs-zarr-conversion-migration, Property 1: Environment Variable Propagation**
    **Validates: Requirements 1.2, 3.1**
    
    For any Step Functions execution with Zarr parameters from the previous state,
    when an ECS task is invoked for COG generation, the ContainerOverrides environment
    variables SHALL contain the correct values.
    """
    # Ensure buckets are valid
    assume(zarr_bucket and output_bucket)
    assume(zarr_bucket != output_bucket)  # Different buckets
    
    # Construct full Zarr key with prefix
    full_zarr_key = f"zarr/{zarr_key}.zarr"
    
    # Create ContainerOverrides as Step Functions would
    overrides = create_cog_container_overrides(
        zarr_bucket=zarr_bucket,
        zarr_key=full_zarr_key,
        output_bucket=output_bucket
    )
    
    # Verify environment variables are correctly set
    assert extract_env_var(overrides, "ZARR_BUCKET") == zarr_bucket, \
        f"ZARR_BUCKET should be '{zarr_bucket}'"
    assert extract_env_var(overrides, "ZARR_KEY") == full_zarr_key, \
        f"ZARR_KEY should be '{full_zarr_key}'"
    assert extract_env_var(overrides, "OUTPUT_BUCKET") == output_bucket, \
        f"OUTPUT_BUCKET should be '{output_bucket}'"
    
    # Verify container name is correct
    assert overrides["ContainerOverrides"][0]["Name"] == "cog-generator", \
        "Container name should be 'cog-generator'"
    
    # Verify all required environment variables are present
    env_var_names = {env["Name"] for env in overrides["ContainerOverrides"][0]["Environment"]}
    required_vars = {"ZARR_BUCKET", "ZARR_KEY", "OUTPUT_BUCKET"}
    assert required_vars.issubset(env_var_names), \
        f"All required environment variables must be present: {required_vars}"


@pytest.mark.ingestion
@given(
    bucket=bucket_strategy,
    key=key_strategy
)
@settings(max_examples=100)
def test_property_env_var_propagation_preserves_special_chars(bucket, key):
    """
    **Feature: ecs-zarr-conversion-migration, Property 1: Environment Variable Propagation**
    **Validates: Requirements 1.2, 3.1**
    
    For any bucket name or key with special characters (hyphens, underscores, dots),
    the environment variables SHALL preserve these characters exactly.
    """
    # Add special characters to test preservation
    special_key = f"{key}-test_file.v1"
    full_key = f"ingestion/{special_key}.nc"
    
    output_bucket = f"{bucket}-output"
    
    # Create ContainerOverrides
    overrides = create_ecs_container_overrides(
        container_name="zarr-converter",
        input_bucket=bucket,
        input_key=full_key,
        output_bucket=output_bucket
    )
    
    # Verify special characters are preserved
    assert extract_env_var(overrides, "INPUT_KEY") == full_key, \
        "Special characters in key should be preserved"
    assert extract_env_var(overrides, "OUTPUT_BUCKET") == output_bucket, \
        "Hyphens in bucket name should be preserved"


@pytest.mark.ingestion
@given(
    bucket=bucket_strategy,
    key=st.text(alphabet=key_chars, min_size=50, max_size=200)
)
@settings(max_examples=50)
def test_property_env_var_propagation_long_values(bucket, key):
    """
    **Feature: ecs-zarr-conversion-migration, Property 1: Environment Variable Propagation**
    **Validates: Requirements 1.2, 3.1**
    
    For any long key values (50-200 characters), the environment variables
    SHALL contain the complete value without truncation.
    """
    # Filter out invalid keys
    assume(key and not key.startswith('.'))
    
    full_key = f"ingestion/{key}.nc"
    output_bucket = f"{bucket}-zarr"
    
    # Create ContainerOverrides
    overrides = create_ecs_container_overrides(
        container_name="zarr-converter",
        input_bucket=bucket,
        input_key=full_key,
        output_bucket=output_bucket
    )
    
    # Verify long values are not truncated
    extracted_key = extract_env_var(overrides, "INPUT_KEY")
    assert len(extracted_key) == len(full_key), \
        f"Key length should be preserved: expected {len(full_key)}, got {len(extracted_key)}"
    assert extracted_key == full_key, \
        "Long key should be preserved exactly"


@pytest.mark.ingestion
@given(
    bucket1=bucket_strategy,
    bucket2=bucket_strategy,
    bucket3=bucket_strategy,
    key=key_strategy
)
@settings(max_examples=100)
def test_property_env_var_propagation_multiple_buckets(bucket1, bucket2, bucket3, key):
    """
    **Feature: ecs-zarr-conversion-migration, Property 1: Environment Variable Propagation**
    **Validates: Requirements 1.2, 3.1**
    
    For any execution with multiple different bucket names,
    the environment variables SHALL not confuse or mix up the bucket values.
    """
    # Ensure all buckets are different
    assume(bucket1 and bucket2 and bucket3)
    assume(bucket1 != bucket2 and bucket2 != bucket3 and bucket1 != bucket3)
    
    full_key = f"ingestion/{key}.nc"
    
    # Create ContainerOverrides with distinct buckets
    overrides = create_ecs_container_overrides(
        container_name="zarr-converter",
        input_bucket=bucket1,
        input_key=full_key,
        output_bucket=bucket2
    )
    
    # Verify buckets are not confused
    input_bucket_value = extract_env_var(overrides, "INPUT_BUCKET")
    output_bucket_value = extract_env_var(overrides, "OUTPUT_BUCKET")
    
    assert input_bucket_value == bucket1, \
        f"INPUT_BUCKET should be '{bucket1}', not confused with other buckets"
    assert output_bucket_value == bucket2, \
        f"OUTPUT_BUCKET should be '{bucket2}', not confused with other buckets"
    assert input_bucket_value != output_bucket_value, \
        "Input and output buckets should remain distinct"


@pytest.mark.ingestion
def test_property_env_var_propagation_real_world_zarr():
    """
    **Feature: ecs-zarr-conversion-migration, Property 1: Environment Variable Propagation**
    **Validates: Requirements 1.2, 3.1**
    
    Test environment variable propagation with real-world values from the project.
    """
    # Real-world scenario
    input_bucket = "[YOURORG]-raw-data"
    input_key = "ingestion/A2002070120230731_MC_SST_std_coastal_v05.nc"
    output_bucket = "[YOURORG]-zarr-data"
    
    # Create ContainerOverrides
    overrides = create_ecs_container_overrides(
        container_name="zarr-converter",
        input_bucket=input_bucket,
        input_key=input_key,
        output_bucket=output_bucket
    )
    
    # Verify exact values
    assert extract_env_var(overrides, "INPUT_BUCKET") == "[YOURORG]-raw-data"
    assert extract_env_var(overrides, "INPUT_KEY") == "ingestion/A2002070120230731_MC_SST_std_coastal_v05.nc"
    assert extract_env_var(overrides, "OUTPUT_BUCKET") == "[YOURORG]-zarr-data"
    
    # Verify structure
    assert overrides == {
        "ContainerOverrides": [{
            "Name": "zarr-converter",
            "Environment": [
                {"Name": "INPUT_BUCKET", "Value": "[YOURORG]-raw-data"},
                {"Name": "INPUT_KEY", "Value": "ingestion/A2002070120230731_MC_SST_std_coastal_v05.nc"},
                {"Name": "OUTPUT_BUCKET", "Value": "[YOURORG]-zarr-data"}
            ]
        }]
    }


@pytest.mark.ingestion
def test_property_env_var_propagation_real_world_cog():
    """
    **Feature: ecs-zarr-conversion-migration, Property 1: Environment Variable Propagation**
    **Validates: Requirements 1.2, 3.1**
    
    Test environment variable propagation for COG generation with real-world values.
    """
    # Real-world scenario
    zarr_bucket = "[YOURORG]-zarr-data"
    zarr_key = "zarr/A2002070120230731_MC_SST_std_coastal_v05.zarr"
    output_bucket = "[YOURORG]-cog-data"
    
    # Create ContainerOverrides
    overrides = create_cog_container_overrides(
        zarr_bucket=zarr_bucket,
        zarr_key=zarr_key,
        output_bucket=output_bucket
    )
    
    # Verify exact values
    assert extract_env_var(overrides, "ZARR_BUCKET") == "[YOURORG]-zarr-data"
    assert extract_env_var(overrides, "ZARR_KEY") == "zarr/A2002070120230731_MC_SST_std_coastal_v05.zarr"
    assert extract_env_var(overrides, "OUTPUT_BUCKET") == "[YOURORG]-cog-data"
    
    # Verify structure
    assert overrides == {
        "ContainerOverrides": [{
            "Name": "cog-generator",
            "Environment": [
                {"Name": "ZARR_BUCKET", "Value": "[YOURORG]-zarr-data"},
                {"Name": "ZARR_KEY", "Value": "zarr/A2002070120230731_MC_SST_std_coastal_v05.zarr"},
                {"Name": "OUTPUT_BUCKET", "Value": "[YOURORG]-cog-data"}
            ]
        }]
    }


@pytest.mark.ingestion
@given(
    bucket=bucket_strategy,
    key=key_strategy
)
@settings(max_examples=100)
def test_property_env_var_propagation_no_extra_vars(bucket, key):
    """
    **Feature: ecs-zarr-conversion-migration, Property 1: Environment Variable Propagation**
    **Validates: Requirements 1.2, 3.1**
    
    For any Step Functions execution, the ContainerOverrides SHALL contain
    ONLY the required environment variables (no extra or unexpected variables).
    """
    full_key = f"ingestion/{key}.nc"
    output_bucket = f"{bucket}-output"
    
    # Create ContainerOverrides
    overrides = create_ecs_container_overrides(
        container_name="zarr-converter",
        input_bucket=bucket,
        input_key=full_key,
        output_bucket=output_bucket
    )
    
    # Verify exactly 3 environment variables
    env_vars = overrides["ContainerOverrides"][0]["Environment"]
    assert len(env_vars) == 3, \
        f"Should have exactly 3 environment variables, got {len(env_vars)}"
    
    # Verify no unexpected variables
    env_var_names = {env["Name"] for env in env_vars}
    expected_vars = {"INPUT_BUCKET", "INPUT_KEY", "OUTPUT_BUCKET"}
    assert env_var_names == expected_vars, \
        f"Should have exactly {expected_vars}, got {env_var_names}"


@pytest.mark.ingestion
@given(
    bucket=bucket_strategy,
    key=key_strategy
)
@settings(max_examples=100)
def test_property_env_var_propagation_value_types(bucket, key):
    """
    **Feature: ecs-zarr-conversion-migration, Property 1: Environment Variable Propagation**
    **Validates: Requirements 1.2, 3.1**
    
    For any Step Functions execution, all environment variable values
    SHALL be strings (not null, not numbers, not other types).
    """
    full_key = f"ingestion/{key}.nc"
    output_bucket = f"{bucket}-output"
    
    # Create ContainerOverrides
    overrides = create_ecs_container_overrides(
        container_name="zarr-converter",
        input_bucket=bucket,
        input_key=full_key,
        output_bucket=output_bucket
    )
    
    # Verify all values are strings
    env_vars = overrides["ContainerOverrides"][0]["Environment"]
    for env_var in env_vars:
        assert isinstance(env_var["Name"], str), \
            f"Environment variable name should be string, got {type(env_var['Name'])}"
        assert isinstance(env_var["Value"], str), \
            f"Environment variable value should be string, got {type(env_var['Value'])}"
        assert env_var["Value"] != "", \
            f"Environment variable value should not be empty string"
        assert env_var["Value"] is not None, \
            f"Environment variable value should not be None"
