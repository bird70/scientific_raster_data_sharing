import pytest
import xarray as xr
from pathlib import Path

from app.ingestion.metadata_extractor import MetadataExtractor, STACMetadataBuilder


@pytest.mark.ingestion
def test_metadata_extraction_with_real_file():
    """
    Test metadata extraction with a real NetCDF file
    Requirements: 6.1, 6.2, 6.3, 7.1, 7.2
    """
    # Use one of the test files
    test_file = Path("data/A2002070120230731_MC_SST_std_coastal_v05.nc")
    
    if not test_file.exists():
        pytest.skip(f"Test file not found: {test_file}")
    
    # Open the dataset
    ds = xr.open_dataset(test_file, engine="netcdf4")
    
    # Extract metadata
    extractor = MetadataExtractor()
    metadata = extractor.extract_all_metadata(ds)
    
    # Verify structure
    assert 'variables' in metadata
    assert 'global_attributes' in metadata
    assert 'collections' in metadata
    
    # Verify we extracted variables
    assert len(metadata['variables']) > 0
    
    # Check that each variable has required fields
    for var in metadata['variables']:
        assert 'name' in var
        assert 'long_name' in var
        assert 'dimensions' in var
        assert 'shape' in var
        assert 'dtype' in var
    
    # Verify collections were derived
    assert len(metadata['collections']) > 0
    
    # Check that each collection has required fields
    for collection in metadata['collections']:
        assert 'name' in collection
        assert 'variable' in collection
        assert 'description' in collection
        assert 'units' in collection
    
    # Build STAC metadata
    builder = STACMetadataBuilder()
    stac_properties = builder.build_stac_properties(metadata)
    
    # Verify STAC properties
    assert 'variables' in stac_properties
    assert 'variable_metadata' in stac_properties
    
    # Determine collection ID
    collection_id = builder.determine_collection_id(metadata, test_file.name)
    
    # Verify collection ID is not 'unknown'
    assert collection_id != 'unknown'
    
    print(f"\nExtracted metadata:")
    print(f"  Variables: {[v['name'] for v in metadata['variables']]}")
    print(f"  Collections: {[c['name'] for c in metadata['collections']]}")
    print(f"  Collection ID: {collection_id}")
    print(f"  Global attributes: {list(metadata['global_attributes'].keys())}")


@pytest.mark.ingestion
def test_metadata_extraction_with_owda_file():
    """
    Test metadata extraction with OWDA file (different structure)
    Requirements: 6.1, 6.2, 6.3
    """
    # Use the OWDA test file
    test_file = Path("data/other/owda.nc")
    
    if not test_file.exists():
        pytest.skip(f"Test file not found: {test_file}")
    
    # Open the dataset
    ds = xr.open_dataset(test_file, engine="netcdf4")
    
    # Extract metadata
    extractor = MetadataExtractor()
    metadata = extractor.extract_all_metadata(ds)
    
    # Verify structure
    assert 'variables' in metadata
    assert 'global_attributes' in metadata
    assert 'collections' in metadata
    
    # Verify we extracted variables
    assert len(metadata['variables']) > 0
    
    print(f"\nOWDA file metadata:")
    print(f"  Variables: {[v['name'] for v in metadata['variables']]}")
    print(f"  Collections: {[c['name'] for c in metadata['collections']]}")
