"""
Property-based tests for Step Functions filename transformations

Feature: ecs-zarr-conversion-migration
"""
import pytest
from hypothesis import given, strategies as st, assume, settings


def transform_netcdf_to_zarr(input_key: str) -> str:
    """
    Transform NetCDF input key to Zarr output key.
    
    This mimics the Step Functions JSONPath transformation:
    States.Format('zarr/{}', States.StringReplace(
        States.ArrayGetItem(States.StringSplit(input_key, '/'), 1), 
        '.nc', '.zarr'))
    
    Args:
        input_key: S3 key in format 'ingestion/*.nc'
        
    Returns:
        S3 key in format 'zarr/*.zarr'
    """
    # Split by '/'
    parts = input_key.split('/')
    
    # Get second element (index 1) - the filename
    if len(parts) < 2:
        raise ValueError(f"Input key must have at least 2 parts separated by '/': {input_key}")
    
    filename = parts[1]
    
    # Replace '.nc' with '.zarr'
    zarr_filename = filename.replace('.nc', '.zarr')
    
    # Prepend 'zarr/'
    return f'zarr/{zarr_filename}'


# Strategy for generating valid filenames
# Alphanumeric, hyphens, underscores, dots (but not starting with dot)
filename_chars = st.characters(
    whitelist_categories=('Lu', 'Ll', 'Nd'),  # Letters and digits
    whitelist_characters='-_.'
)

filename_strategy = st.text(
    alphabet=filename_chars,
    min_size=1,
    max_size=100
).filter(lambda s: not s.startswith('.') and s != '.' and s != '..')


@pytest.mark.ingestion
@given(filename=filename_strategy)
@settings(max_examples=100)
def test_property_filename_transformation_basic(filename):
    """
    **Feature: ecs-zarr-conversion-migration, Property 2: Filename Transformation Consistency**
    **Validates: Requirements 2.1, 2.2**
    
    For any input NetCDF filename matching the pattern `ingestion/*.nc`, 
    the transformation SHALL produce `zarr/*.zarr` by replacing the prefix and extension.
    """
    # Construct input key
    input_key = f'ingestion/{filename}.nc'
    
    # Transform
    output_key = transform_netcdf_to_zarr(input_key)
    
    # Verify properties
    assert output_key.startswith('zarr/'), f"Output should start with 'zarr/', got: {output_key}"
    assert output_key.endswith('.zarr'), f"Output should end with '.zarr', got: {output_key}"
    
    # Extract the filename part
    output_filename = output_key[5:]  # Remove 'zarr/' prefix
    expected_filename = f'{filename}.zarr'
    
    assert output_filename == expected_filename, \
        f"Expected '{expected_filename}', got '{output_filename}'"


@pytest.mark.ingestion
@given(
    filename=filename_strategy,
    subdirs=st.lists(
        st.text(alphabet=filename_chars, min_size=1, max_size=20),
        min_size=0,
        max_size=3
    )
)
@settings(max_examples=100)
def test_property_filename_transformation_with_subdirectories(filename, subdirs):
    """
    **Feature: ecs-zarr-conversion-migration, Property 2: Filename Transformation Consistency**
    **Validates: Requirements 2.1, 2.2**
    
    For any input with subdirectories like `ingestion/subdir/file.nc`,
    the transformation SHALL extract the element at index 1 after splitting by '/'.
    
    Note: This test verifies the ACTUAL behavior of the Step Functions JSONPath:
    - 'ingestion/file.nc' -> 'zarr/file.zarr' (index 1 is 'file.nc')
    - 'ingestion/subdir/file.nc' -> 'zarr/subdir.zarr' (index 1 is 'subdir')
    """
    # Filter out invalid subdirectory names
    subdirs = [s for s in subdirs if s and s not in ('.', '..') and not s.startswith('.')]
    
    if not subdirs:
        # No subdirectories, use simple path
        input_key = f'ingestion/{filename}.nc'
    else:
        # Build path with subdirectories
        subdir_path = '/'.join(subdirs)
        input_key = f'ingestion/{subdir_path}/{filename}.nc'
    
    # Transform
    output_key = transform_netcdf_to_zarr(input_key)
    
    # Verify properties
    assert output_key.startswith('zarr/'), f"Output should start with 'zarr/', got: {output_key}"
    
    # The transformation extracts element at index 1 after split
    # For 'ingestion/file.nc', split gives ['ingestion', 'file.nc']
    # ArrayGetItem(..., 1) gives 'file.nc', then .nc is replaced with .zarr -> 'file.zarr'
    # For 'ingestion/subdir/file.nc', split gives ['ingestion', 'subdir', 'file.nc']
    # ArrayGetItem(..., 1) gives 'subdir', then .nc is replaced (no match) -> 'subdir.zarr'
    parts = input_key.split('/')
    expected_middle_part = parts[1] if len(parts) > 1 else filename
    
    # Replace .nc with .zarr in the middle part
    expected_middle_part_transformed = expected_middle_part.replace('.nc', '.zarr')
    expected_output = f'zarr/{expected_middle_part_transformed}'
    
    assert output_key == expected_output, \
        f"For input '{input_key}', expected '{expected_output}', got '{output_key}'"


@pytest.mark.ingestion
@given(filename=filename_strategy)
@settings(max_examples=100)
def test_property_filename_transformation_preserves_special_chars(filename):
    """
    **Feature: ecs-zarr-conversion-migration, Property 2: Filename Transformation Consistency**
    **Validates: Requirements 2.1, 2.2**
    
    For any filename with special characters (hyphens, underscores, dots),
    the transformation SHALL preserve these characters correctly.
    """
    # Add some special characters to the filename
    special_filename = f'{filename}-test_file.v1'
    input_key = f'ingestion/{special_filename}.nc'
    
    # Transform
    output_key = transform_netcdf_to_zarr(input_key)
    
    # Verify the special characters are preserved
    expected_output = f'zarr/{special_filename}.zarr'
    assert output_key == expected_output, \
        f"Special characters should be preserved. Expected '{expected_output}', got '{output_key}'"


@pytest.mark.ingestion
@given(
    filename=st.text(alphabet=filename_chars, min_size=50, max_size=200)
)
@settings(max_examples=50)
def test_property_filename_transformation_long_names(filename):
    """
    **Feature: ecs-zarr-conversion-migration, Property 2: Filename Transformation Consistency**
    **Validates: Requirements 2.1, 2.2**
    
    For any long filename (50-200 characters), the transformation SHALL work correctly.
    """
    # Filter out invalid names
    assume(filename and not filename.startswith('.'))
    
    input_key = f'ingestion/{filename}.nc'
    
    # Transform
    output_key = transform_netcdf_to_zarr(input_key)
    
    # Verify properties
    assert output_key.startswith('zarr/'), f"Output should start with 'zarr/'"
    assert output_key.endswith('.zarr'), f"Output should end with '.zarr'"
    
    # Verify the transformation is correct
    expected_output = f'zarr/{filename}.zarr'
    assert output_key == expected_output, \
        f"Expected '{expected_output}', got '{output_key}'"
    
    # Length relationship: 'zarr' is 4 chars, 'ingestion' is 9 chars (5 char difference)
    # '.zarr' is 5 chars, '.nc' is 3 chars (2 char difference)
    # Net: output should be 3 chars shorter than input (5 - 2 = 3)
    assert len(output_key) == len(input_key) - 3, \
        f"Output length should be input length - 3, got {len(output_key)} vs {len(input_key)}"


@pytest.mark.ingestion
def test_property_filename_transformation_real_world_examples():
    """
    **Feature: ecs-zarr-conversion-migration, Property 2: Filename Transformation Consistency**
    **Validates: Requirements 2.1, 2.2**
    
    Test with real-world NetCDF filenames from the project.
    """
    test_cases = [
        ('ingestion/A2002070120230731_MC_SST_std_coastal_v05.nc', 
         'zarr/A2002070120230731_MC_SST_std_coastal_v05.zarr'),
        ('ingestion/A20021822023212_MC_CHL12_coastal_v05_mean_MC_CHL_exp_coastal_v05.nc',
         'zarr/A20021822023212_MC_CHL12_coastal_v05_mean_MC_CHL_exp_coastal_v05.zarr'),
        ('ingestion/A20021822023212_MC_HVIS_coastal_v05_mean_MC_HVIS_exp_coastal_v05.nc',
         'zarr/A20021822023212_MC_HVIS_coastal_v05_mean_MC_HVIS_exp_coastal_v05.zarr'),
        ('ingestion/your-data.nc',
         'zarr/your-data.zarr'),
    ]
    
    for input_key, expected_output in test_cases:
        output_key = transform_netcdf_to_zarr(input_key)
        assert output_key == expected_output, \
            f"For input '{input_key}', expected '{expected_output}', got '{output_key}'"


# ============================================================================
# COG Key Derivation Tests (Property 4)
# ============================================================================

def transform_zarr_to_cog(zarr_key: str) -> str:
    """
    Transform Zarr key to COG output key.
    
    This mimics the Step Functions JSONPath transformation:
    States.Format('cog/{}.tif', States.ArrayGetItem(
        States.StringSplit(zarr_key, '/'), 1))
    
    Args:
        zarr_key: S3 key in format 'zarr/*.zarr'
        
    Returns:
        S3 key in format 'cog/*.tif'
    """
    # Split by '/'
    parts = zarr_key.split('/')
    
    # Get second element (index 1) - the filename
    if len(parts) < 2:
        raise ValueError(f"Zarr key must have at least 2 parts separated by '/': {zarr_key}")
    
    filename = parts[1]
    
    # Format as 'cog/{filename}.tif'
    return f'cog/{filename}.tif'


@pytest.mark.ingestion
@given(filename=filename_strategy)
@settings(max_examples=100)
def test_property_cog_key_derivation_basic(filename):
    """
    **Feature: ecs-zarr-conversion-migration, Property 4: COG Key Derivation**
    **Validates: Requirements 3.3, 3.5**
    
    For any Zarr key matching the pattern `zarr/*.zarr`, the transformation
    SHALL produce `cog/*.tif` by extracting the filename and changing the prefix.
    """
    # Construct Zarr key
    zarr_key = f'zarr/{filename}.zarr'
    
    # Transform
    cog_key = transform_zarr_to_cog(zarr_key)
    
    # Verify properties
    assert cog_key.startswith('cog/'), f"Output should start with 'cog/', got: {cog_key}"
    assert cog_key.endswith('.tif'), f"Output should end with '.tif', got: {cog_key}"
    
    # Extract the filename part
    cog_filename = cog_key[4:]  # Remove 'cog/' prefix
    expected_filename = f'{filename}.zarr.tif'
    
    assert cog_filename == expected_filename, \
        f"Expected '{expected_filename}', got '{cog_filename}'"


@pytest.mark.ingestion
@given(filename=filename_strategy)
@settings(max_examples=100)
def test_property_cog_key_derivation_preserves_zarr_extension(filename):
    """
    **Feature: ecs-zarr-conversion-migration, Property 4: COG Key Derivation**
    **Validates: Requirements 3.3, 3.5**
    
    For any Zarr key, the transformation SHALL preserve the .zarr extension
    and append .tif (resulting in .zarr.tif).
    
    Note: This is the behavior of the Step Functions JSONPath transformation.
    The actual Python code in cog_generator.py replaces .zarr with .tif.
    """
    zarr_key = f'zarr/{filename}.zarr'
    
    # Transform
    cog_key = transform_zarr_to_cog(zarr_key)
    
    # The JSONPath transformation keeps .zarr and adds .tif
    expected_cog_key = f'cog/{filename}.zarr.tif'
    
    assert cog_key == expected_cog_key, \
        f"Expected '{expected_cog_key}', got '{cog_key}'"


@pytest.mark.ingestion
@given(
    filename=filename_strategy,
    subdirs=st.lists(
        st.text(alphabet=filename_chars, min_size=1, max_size=20),
        min_size=0,
        max_size=3
    )
)
@settings(max_examples=100)
def test_property_cog_key_derivation_with_subdirectories(filename, subdirs):
    """
    **Feature: ecs-zarr-conversion-migration, Property 4: COG Key Derivation**
    **Validates: Requirements 3.3, 3.5**
    
    For any Zarr key with subdirectories like `zarr/subdir/file.zarr`,
    the transformation SHALL extract the element at index 1 after splitting by '/'.
    
    Note: Similar to NetCDF transformation, this extracts the second path component.
    - 'zarr/file.zarr' -> 'cog/file.zarr.tif' (index 1 is 'file.zarr')
    - 'zarr/subdir/file.zarr' -> 'cog/subdir.tif' (index 1 is 'subdir')
    """
    # Filter out invalid subdirectory names
    subdirs = [s for s in subdirs if s and s not in ('.', '..') and not s.startswith('.')]
    
    if not subdirs:
        # No subdirectories, use simple path
        zarr_key = f'zarr/{filename}.zarr'
    else:
        # Build path with subdirectories
        subdir_path = '/'.join(subdirs)
        zarr_key = f'zarr/{subdir_path}/{filename}.zarr'
    
    # Transform
    cog_key = transform_zarr_to_cog(zarr_key)
    
    # Verify properties
    assert cog_key.startswith('cog/'), f"Output should start with 'cog/', got: {cog_key}"
    assert cog_key.endswith('.tif'), f"Output should end with '.tif', got: {cog_key}"
    
    # The transformation extracts element at index 1 after split
    parts = zarr_key.split('/')
    expected_middle_part = parts[1] if len(parts) > 1 else filename
    expected_output = f'cog/{expected_middle_part}.tif'
    
    assert cog_key == expected_output, \
        f"For input '{zarr_key}', expected '{expected_output}', got '{cog_key}'"


@pytest.mark.ingestion
@given(filename=filename_strategy)
@settings(max_examples=100)
def test_property_cog_key_derivation_preserves_special_chars(filename):
    """
    **Feature: ecs-zarr-conversion-migration, Property 4: COG Key Derivation**
    **Validates: Requirements 3.3, 3.5**
    
    For any filename with special characters (hyphens, underscores, dots),
    the transformation SHALL preserve these characters correctly.
    """
    # Add some special characters to the filename
    special_filename = f'{filename}-test_file.v1'
    zarr_key = f'zarr/{special_filename}.zarr'
    
    # Transform
    cog_key = transform_zarr_to_cog(zarr_key)
    
    # Verify the special characters are preserved
    expected_output = f'cog/{special_filename}.zarr.tif'
    assert cog_key == expected_output, \
        f"Special characters should be preserved. Expected '{expected_output}', got '{cog_key}'"


@pytest.mark.ingestion
@given(
    filename=st.text(alphabet=filename_chars, min_size=50, max_size=200)
)
@settings(max_examples=50)
def test_property_cog_key_derivation_long_names(filename):
    """
    **Feature: ecs-zarr-conversion-migration, Property 4: COG Key Derivation**
    **Validates: Requirements 3.3, 3.5**
    
    For any long filename (50-200 characters), the transformation SHALL work correctly.
    """
    # Filter out invalid names
    assume(filename and not filename.startswith('.'))
    
    zarr_key = f'zarr/{filename}.zarr'
    
    # Transform
    cog_key = transform_zarr_to_cog(zarr_key)
    
    # Verify properties
    assert cog_key.startswith('cog/'), f"Output should start with 'cog/'"
    assert cog_key.endswith('.tif'), f"Output should end with '.tif'"
    
    # Verify the transformation is correct
    expected_output = f'cog/{filename}.zarr.tif'
    assert cog_key == expected_output, \
        f"Expected '{expected_output}', got '{cog_key}'"


@pytest.mark.ingestion
def test_property_cog_key_derivation_real_world_examples():
    """
    **Feature: ecs-zarr-conversion-migration, Property 4: COG Key Derivation**
    **Validates: Requirements 3.3, 3.5**
    
    Test with real-world Zarr filenames derived from the project's NetCDF files.
    """
    test_cases = [
        ('zarr/A2002070120230731_MC_SST_std_coastal_v05.zarr', 
         'cog/A2002070120230731_MC_SST_std_coastal_v05.zarr.tif'),
        ('zarr/A20021822023212_MC_CHL12_coastal_v05_mean_MC_CHL_exp_coastal_v05.zarr',
         'cog/A20021822023212_MC_CHL12_coastal_v05_mean_MC_CHL_exp_coastal_v05.zarr.tif'),
        ('zarr/A20021822023212_MC_HVIS_coastal_v05_mean_MC_HVIS_exp_coastal_v05.zarr',
         'cog/A20021822023212_MC_HVIS_coastal_v05_mean_MC_HVIS_exp_coastal_v05.zarr.tif'),
        ('zarr/your-data.zarr',
         'cog/your-data.zarr.tif'),
    ]
    
    for zarr_key, expected_output in test_cases:
        cog_key = transform_zarr_to_cog(zarr_key)
        assert cog_key == expected_output, \
            f"For input '{zarr_key}', expected '{expected_output}', got '{cog_key}'"


# ============================================================================
# State Data Flow Preservation Tests (Property 3)
# ============================================================================

def simulate_state_transition(initial_state: dict, state_output: dict, result_path: str) -> dict:
    """
    Simulate Step Functions state transition with ResultPath.
    
    This mimics how Step Functions merges state output into the state data:
    - If ResultPath is None, the output replaces the entire state
    - If ResultPath is a JSONPath like "$.zarr_conversion", the output is merged at that path
    
    Args:
        initial_state: The state data before the transition
        state_output: The output from the current state
        result_path: The ResultPath value (e.g., "$.zarr_conversion")
        
    Returns:
        The merged state data after the transition
    """
    import copy
    
    # Deep copy to avoid mutating the input
    new_state = copy.deepcopy(initial_state)
    
    if result_path is None:
        # Output replaces entire state
        return state_output
    
    # Parse ResultPath (e.g., "$.zarr_conversion" -> "zarr_conversion")
    if result_path.startswith('$.'):
        path_key = result_path[2:]
    else:
        path_key = result_path
    
    # Merge output at the specified path
    new_state[path_key] = state_output
    
    return new_state


@pytest.mark.ingestion
@given(
    bucket=st.text(alphabet=st.characters(whitelist_categories=('Lu', 'Ll', 'Nd'), 
                                          whitelist_characters='-'), 
                   min_size=3, max_size=63),
    key=st.text(alphabet=filename_chars, min_size=1, max_size=100)
)
@settings(max_examples=100)
def test_property_state_data_flow_zarr_conversion(bucket, key):
    """
    **Feature: ecs-zarr-conversion-migration, Property 3: State Data Flow Preservation**
    **Validates: Requirements 2.3, 2.4, 3.4, 4.8**
    
    For any Step Functions state transition from initial input to ConvertToZarr output,
    the data SHALL be preserved exactly (no loss or corruption of bucket names and keys).
    """
    # Filter out invalid bucket names
    assume(bucket and not bucket.startswith('-') and not bucket.endswith('-'))
    assume(key and not key.startswith('.'))
    
    # Initial state (from trigger Lambda)
    initial_state = {
        "bucket": bucket,
        "key": f"ingestion/{key}.nc"
    }
    
    # Simulate ConvertToZarr state output
    zarr_bucket = f"{bucket}-zarr"
    zarr_key = transform_netcdf_to_zarr(initial_state["key"])
    
    zarr_output = {
        "zarr_key": zarr_key,
        "zarr_bucket": zarr_bucket,
        "status": "success"
    }
    
    # Simulate state transition with ResultPath = "$.zarr_conversion"
    new_state = simulate_state_transition(initial_state, zarr_output, "$.zarr_conversion")
    
    # Verify original data is preserved
    assert new_state["bucket"] == bucket, \
        f"Original bucket should be preserved, got {new_state.get('bucket')}"
    assert new_state["key"] == f"ingestion/{key}.nc", \
        f"Original key should be preserved, got {new_state.get('key')}"
    
    # Verify new data is added
    assert "zarr_conversion" in new_state, \
        "zarr_conversion should be added to state"
    assert new_state["zarr_conversion"]["zarr_key"] == zarr_key, \
        f"zarr_key should be {zarr_key}, got {new_state['zarr_conversion'].get('zarr_key')}"
    assert new_state["zarr_conversion"]["zarr_bucket"] == zarr_bucket, \
        f"zarr_bucket should be {zarr_bucket}, got {new_state['zarr_conversion'].get('zarr_bucket')}"
    assert new_state["zarr_conversion"]["status"] == "success", \
        "status should be 'success'"


@pytest.mark.ingestion
@given(
    bucket=st.text(alphabet=st.characters(whitelist_categories=('Lu', 'Ll', 'Nd'), 
                                          whitelist_characters='-'), 
                   min_size=3, max_size=63),
    key=st.text(alphabet=filename_chars, min_size=1, max_size=100)
)
@settings(max_examples=100)
def test_property_state_data_flow_cog_generation(bucket, key):
    """
    **Feature: ecs-zarr-conversion-migration, Property 3: State Data Flow Preservation**
    **Validates: Requirements 2.3, 2.4, 3.4, 4.8**
    
    For any Step Functions state transition from ConvertToZarr to GenerateCOG,
    the data SHALL be preserved exactly (no loss or corruption).
    """
    # Filter out invalid bucket names
    assume(bucket and not bucket.startswith('-') and not bucket.endswith('-'))
    assume(key and not key.startswith('.'))
    
    # State after ConvertToZarr
    zarr_bucket = f"{bucket}-zarr"
    zarr_key = transform_netcdf_to_zarr(f"ingestion/{key}.nc")
    
    state_after_zarr = {
        "bucket": bucket,
        "key": f"ingestion/{key}.nc",
        "zarr_conversion": {
            "zarr_key": zarr_key,
            "zarr_bucket": zarr_bucket,
            "status": "success"
        }
    }
    
    # Simulate GenerateCOG state output
    cog_bucket = f"{bucket}-cog"
    cog_key = transform_zarr_to_cog(zarr_key)
    
    cog_output = {
        "cog_key": cog_key,
        "cog_bucket": cog_bucket,
        "status": "success"
    }
    
    # Simulate state transition with ResultPath = "$.cog_generation"
    new_state = simulate_state_transition(state_after_zarr, cog_output, "$.cog_generation")
    
    # Verify original data is preserved
    assert new_state["bucket"] == bucket, \
        f"Original bucket should be preserved"
    assert new_state["key"] == f"ingestion/{key}.nc", \
        f"Original key should be preserved"
    
    # Verify zarr_conversion data is preserved
    assert "zarr_conversion" in new_state, \
        "zarr_conversion should be preserved"
    assert new_state["zarr_conversion"]["zarr_key"] == zarr_key, \
        f"zarr_key should be preserved"
    assert new_state["zarr_conversion"]["zarr_bucket"] == zarr_bucket, \
        f"zarr_bucket should be preserved"
    
    # Verify new data is added
    assert "cog_generation" in new_state, \
        "cog_generation should be added to state"
    assert new_state["cog_generation"]["cog_key"] == cog_key, \
        f"cog_key should be {cog_key}"
    assert new_state["cog_generation"]["cog_bucket"] == cog_bucket, \
        f"cog_bucket should be {cog_bucket}"
    assert new_state["cog_generation"]["status"] == "success", \
        "status should be 'success'"


@pytest.mark.ingestion
@given(
    bucket=st.text(alphabet=st.characters(whitelist_categories=('Lu', 'Ll', 'Nd'), 
                                          whitelist_characters='-'), 
                   min_size=3, max_size=63),
    key=st.text(alphabet=filename_chars, min_size=1, max_size=100)
)
@settings(max_examples=100)
def test_property_state_data_flow_complete_pipeline(bucket, key):
    """
    **Feature: ecs-zarr-conversion-migration, Property 3: State Data Flow Preservation**
    **Validates: Requirements 2.3, 2.4, 3.4, 4.8**
    
    For any complete pipeline execution through ConvertToZarr and GenerateCOG,
    all data SHALL be preserved and accessible for the STAC creation step.
    """
    # Filter out invalid bucket names
    assume(bucket and not bucket.startswith('-') and not bucket.endswith('-'))
    assume(key and not key.startswith('.'))
    
    # Initial state
    initial_state = {
        "bucket": bucket,
        "key": f"ingestion/{key}.nc"
    }
    
    # After ConvertToZarr
    zarr_bucket = f"{bucket}-zarr"
    zarr_key = transform_netcdf_to_zarr(initial_state["key"])
    zarr_output = {
        "zarr_key": zarr_key,
        "zarr_bucket": zarr_bucket,
        "status": "success"
    }
    state_after_zarr = simulate_state_transition(initial_state, zarr_output, "$.zarr_conversion")
    
    # After GenerateCOG
    cog_bucket = f"{bucket}-cog"
    cog_key = transform_zarr_to_cog(zarr_key)
    cog_output = {
        "cog_key": cog_key,
        "cog_bucket": cog_bucket,
        "status": "success"
    }
    final_state = simulate_state_transition(state_after_zarr, cog_output, "$.cog_generation")
    
    # Verify all data needed for STAC creation is present
    assert "zarr_conversion" in final_state, \
        "zarr_conversion data must be available for STAC creation"
    assert "cog_generation" in final_state, \
        "cog_generation data must be available for STAC creation"
    
    # Verify STAC creator can access all required fields
    assert final_state["zarr_conversion"]["zarr_bucket"] == zarr_bucket
    assert final_state["zarr_conversion"]["zarr_key"] == zarr_key
    assert final_state["cog_generation"]["cog_bucket"] == cog_bucket
    assert final_state["cog_generation"]["cog_key"] == cog_key
    
    # Verify no data corruption occurred
    assert isinstance(final_state["zarr_conversion"]["zarr_bucket"], str)
    assert isinstance(final_state["zarr_conversion"]["zarr_key"], str)
    assert isinstance(final_state["cog_generation"]["cog_bucket"], str)
    assert isinstance(final_state["cog_generation"]["cog_key"], str)


@pytest.mark.ingestion
@given(
    bucket1=st.text(alphabet=st.characters(whitelist_categories=('Lu', 'Ll', 'Nd'), 
                                           whitelist_characters='-'), 
                    min_size=3, max_size=30),
    bucket2=st.text(alphabet=st.characters(whitelist_categories=('Lu', 'Ll', 'Nd'), 
                                           whitelist_characters='-'), 
                    min_size=3, max_size=30),
    key=st.text(alphabet=filename_chars, min_size=1, max_size=50)
)
@settings(max_examples=100)
def test_property_state_data_flow_different_buckets(bucket1, bucket2, key):
    """
    **Feature: ecs-zarr-conversion-migration, Property 3: State Data Flow Preservation**
    **Validates: Requirements 2.3, 2.4, 3.4, 4.8**
    
    For any state transition with different bucket names,
    the bucket names SHALL not be confused or overwritten.
    """
    # Filter out invalid bucket names
    assume(bucket1 and not bucket1.startswith('-') and not bucket1.endswith('-'))
    assume(bucket2 and not bucket2.startswith('-') and not bucket2.endswith('-'))
    assume(bucket1 != bucket2)  # Ensure buckets are different
    assume(key and not key.startswith('.'))
    
    # Initial state with bucket1
    initial_state = {
        "bucket": bucket1,
        "key": f"ingestion/{key}.nc"
    }
    
    # ConvertToZarr uses bucket2 for output
    zarr_output = {
        "zarr_key": transform_netcdf_to_zarr(initial_state["key"]),
        "zarr_bucket": bucket2,
        "status": "success"
    }
    
    new_state = simulate_state_transition(initial_state, zarr_output, "$.zarr_conversion")
    
    # Verify buckets are not confused
    assert new_state["bucket"] == bucket1, \
        f"Original bucket should remain {bucket1}"
    assert new_state["zarr_conversion"]["zarr_bucket"] == bucket2, \
        f"Zarr bucket should be {bucket2}"
    assert new_state["bucket"] != new_state["zarr_conversion"]["zarr_bucket"], \
        "Buckets should be different and not confused"


@pytest.mark.ingestion
def test_property_state_data_flow_real_world_scenario():
    """
    **Feature: ecs-zarr-conversion-migration, Property 3: State Data Flow Preservation**
    **Validates: Requirements 2.3, 2.4, 3.4, 4.8**
    
    Test state data flow with a real-world scenario from the project.
    """
    # Initial state from trigger Lambda
    initial_state = {
        "bucket": "[YOURORG]-raw-data",
        "key": "ingestion/A2002070120230731_MC_SST_std_coastal_v05.nc"
    }
    
    # After ConvertToZarr
    zarr_output = {
        "zarr_key": "zarr/A2002070120230731_MC_SST_std_coastal_v05.zarr",
        "zarr_bucket": "[YOURORG]-zarr-data",
        "status": "success"
    }
    state_after_zarr = simulate_state_transition(initial_state, zarr_output, "$.zarr_conversion")
    
    # After GenerateCOG
    cog_output = {
        "cog_key": "cog/A2002070120230731_MC_SST_std_coastal_v05.zarr.tif",
        "cog_bucket": "[YOURORG]-cog-data",
        "status": "success"
    }
    final_state = simulate_state_transition(state_after_zarr, cog_output, "$.cog_generation")
    
    # Verify complete state structure
    assert final_state == {
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
    
    # Verify STAC creator would receive correct parameters
    stac_params = {
        "zarr_bucket": final_state["zarr_conversion"]["zarr_bucket"],
        "zarr_key": final_state["zarr_conversion"]["zarr_key"],
        "cog_bucket": final_state["cog_generation"]["cog_bucket"],
        "cog_key": final_state["cog_generation"]["cog_key"]
    }
    
    assert stac_params == {
        "zarr_bucket": "[YOURORG]-zarr-data",
        "zarr_key": "zarr/A2002070120230731_MC_SST_std_coastal_v05.zarr",
        "cog_bucket": "[YOURORG]-cog-data",
        "cog_key": "cog/A2002070120230731_MC_SST_std_coastal_v05.zarr.tif"
    }
