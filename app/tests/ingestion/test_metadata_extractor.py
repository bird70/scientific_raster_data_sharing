import pytest
import numpy as np
import xarray as xr

from app.ingestion.metadata_extractor import MetadataExtractor, STACMetadataBuilder


@pytest.mark.ingestion
def test_extract_variables():
    """
    Test variable extraction with CF attributes
    Requirements: 6.1, 6.2
    """
    # Create a test dataset with multiple variables
    data1 = np.random.rand(10, 10)
    data2 = np.random.rand(10, 10)
    
    ds = xr.Dataset(
        {
            'SST': (
                ['y', 'x'], 
                data1,
                {
                    'long_name': 'Sea Surface Temperature',
                    'standard_name': 'sea_surface_temperature',
                    'units': 'degC',
                    'description': 'Temperature at ocean surface'
                }
            ),
            'CHL': (
                ['y', 'x'],
                data2,
                {
                    'long_name': 'Chlorophyll Concentration',
                    'standard_name': 'mass_concentration_of_chlorophyll_in_sea_water',
                    'units': 'mg m-3'
                }
            )
        }
    )
    
    # Extract variables
    extractor = MetadataExtractor()
    variables = extractor.extract_variables(ds)
    
    # Verify
    assert len(variables) == 2
    
    # Check SST variable
    sst_var = next(v for v in variables if v['name'] == 'SST')
    assert sst_var['long_name'] == 'Sea Surface Temperature'
    assert sst_var['standard_name'] == 'sea_surface_temperature'
    assert sst_var['units'] == 'degC'
    assert sst_var['description'] == 'Temperature at ocean surface'
    assert sst_var['dimensions'] == ['y', 'x']
    assert sst_var['shape'] == [10, 10]
    
    # Check CHL variable
    chl_var = next(v for v in variables if v['name'] == 'CHL')
    assert chl_var['long_name'] == 'Chlorophyll Concentration'
    assert chl_var['standard_name'] == 'mass_concentration_of_chlorophyll_in_sea_water'
    assert chl_var['units'] == 'mg m-3'


@pytest.mark.ingestion
def test_extract_global_attributes():
    """
    Test global attribute extraction
    Requirements: 6.3
    """
    # Create a test dataset with global attributes
    ds = xr.Dataset(
        {
            'temperature': (['y', 'x'], np.random.rand(10, 10))
        },
        attrs={
            'title': 'Test Dataset',
            'institution': '[YOURORG]',
            'source': 'Satellite observations',
            'Conventions': 'CF-1.6',
            'creator_name': 'Test Creator',
            'project': 'Marine Coastal',
            'custom_attr': 'This should not be extracted'
        }
    )
    
    # Extract global attributes
    extractor = MetadataExtractor()
    attrs = extractor.extract_global_attributes(ds)
    
    # Verify standard CF attributes are extracted
    assert attrs['title'] == 'Test Dataset'
    assert attrs['institution'] == '[YOURORG]'
    assert attrs['source'] == 'Satellite observations'
    assert attrs['Conventions'] == 'CF-1.6'
    assert attrs['creator_name'] == 'Test Creator'
    assert attrs['project'] == 'Marine Coastal'
    
    # Verify non-standard attributes are not extracted
    assert 'custom_attr' not in attrs


@pytest.mark.ingestion
def test_derive_collections_from_standard_name():
    """
    Test collection derivation from standard_name
    Requirements: 7.1
    """
    # Create dataset with standard_name
    ds = xr.Dataset(
        {
            'SST': (
                ['y', 'x'],
                np.random.rand(10, 10),
                {
                    'standard_name': 'sea_surface_temperature',
                    'long_name': 'Sea Surface Temperature',
                    'units': 'degC'
                }
            )
        }
    )
    
    # Derive collections
    extractor = MetadataExtractor()
    collections = extractor.derive_collections(ds)
    
    # Verify
    assert len(collections) == 1
    assert collections[0]['name'] == 'sea-surface-temperature'
    assert collections[0]['variable'] == 'SST'
    assert collections[0]['description'] == 'Sea Surface Temperature'
    assert collections[0]['units'] == 'degC'


@pytest.mark.ingestion
def test_derive_collections_from_long_name():
    """
    Test collection derivation from long_name when standard_name is missing
    Requirements: 7.2
    """
    # Create dataset without standard_name
    ds = xr.Dataset(
        {
            'temp': (
                ['y', 'x'],
                np.random.rand(10, 10),
                {
                    'long_name': 'Water Temperature',
                    'units': 'degC'
                }
            )
        }
    )
    
    # Derive collections
    extractor = MetadataExtractor()
    collections = extractor.derive_collections(ds)
    
    # Verify
    assert len(collections) == 1
    assert collections[0]['name'] == 'water-temperature'
    assert collections[0]['variable'] == 'temp'


@pytest.mark.ingestion
def test_derive_collections_from_variable_name():
    """
    Test collection derivation from variable name as fallback
    Requirements: 7.2
    """
    # Create dataset without standard_name or long_name
    ds = xr.Dataset(
        {
            'MyVariable': (
                ['y', 'x'],
                np.random.rand(10, 10),
                {'units': 'unknown'}
            )
        }
    )
    
    # Derive collections
    extractor = MetadataExtractor()
    collections = extractor.derive_collections(ds)
    
    # Verify
    assert len(collections) == 1
    assert collections[0]['name'] == 'myvariable'
    assert collections[0]['variable'] == 'MyVariable'


@pytest.mark.ingestion
def test_extract_all_metadata():
    """
    Test comprehensive metadata extraction
    Requirements: 6.1, 6.2, 6.3
    """
    # Create a complete test dataset
    ds = xr.Dataset(
        {
            'SST': (
                ['y', 'x'],
                np.random.rand(10, 10),
                {
                    'long_name': 'Sea Surface Temperature',
                    'standard_name': 'sea_surface_temperature',
                    'units': 'degC'
                }
            ),
            'CHL': (
                ['y', 'x'],
                np.random.rand(10, 10),
                {
                    'long_name': 'Chlorophyll',
                    'units': 'mg m-3'
                }
            )
        },
        attrs={
            'title': 'Marine Data',
            'institution': '[YOURORG]'
        }
    )
    
    # Extract all metadata
    extractor = MetadataExtractor()
    metadata = extractor.extract_all_metadata(ds)
    
    # Verify structure
    assert 'variables' in metadata
    assert 'global_attributes' in metadata
    assert 'collections' in metadata
    
    # Verify content
    assert len(metadata['variables']) == 2
    assert len(metadata['collections']) == 2
    assert metadata['global_attributes']['title'] == 'Marine Data'
    assert metadata['global_attributes']['institution'] == '[YOURORG]'


@pytest.mark.ingestion
def test_build_stac_properties():
    """
    Test STAC properties building
    Requirements: 6.4, 7.3
    """
    # Create metadata
    metadata = {
        'variables': [
            {
                'name': 'SST',
                'long_name': 'Sea Surface Temperature',
                'units': 'degC'
            }
        ],
        'global_attributes': {
            'title': 'Test Dataset',
            'institution': '[YOURORG]'
        },
        'collections': [
            {
                'name': 'sea-surface-temperature',
                'variable': 'SST'
            }
        ]
    }
    
    # Build STAC properties
    builder = STACMetadataBuilder()
    properties = builder.build_stac_properties(metadata)
    
    # Verify
    assert 'variables' in properties
    assert properties['variables'] == ['SST']
    assert 'variable_metadata' in properties
    assert properties['title'] == 'Test Dataset'
    assert properties['institution'] == '[YOURORG]'
    assert 'collections' in properties


@pytest.mark.ingestion
def test_determine_collection_id_from_metadata():
    """
    Test collection ID determination from metadata
    Requirements: 7.3
    """
    # Create metadata with collections
    metadata = {
        'collections': [
            {
                'name': 'sea-surface-temperature',
                'variable': 'SST'
            }
        ]
    }
    
    # Determine collection ID
    builder = STACMetadataBuilder()
    collection_id = builder.determine_collection_id(metadata, 'test.nc')
    
    # Verify
    assert collection_id == 'sea-surface-temperature'


@pytest.mark.ingestion
def test_determine_collection_id_from_filename():
    """
    Test collection ID determination from filename pattern
    Requirements: 7.3
    """
    # Create metadata without collections
    metadata = {'collections': []}
    
    # Determine collection ID from filename
    builder = STACMetadataBuilder()
    collection_id = builder.determine_collection_id(
        metadata, 
        'A2002070120230731_MC_SST_std_coastal_v05.nc'
    )
    
    # Verify
    assert collection_id == 'sst'


@pytest.mark.ingestion
def test_determine_collection_id_fallback():
    """
    Test collection ID fallback to 'unknown'
    Requirements: 7.3
    """
    # Create metadata without collections
    metadata = {'collections': []}
    
    # Determine collection ID with unrecognizable filename
    builder = STACMetadataBuilder()
    collection_id = builder.determine_collection_id(metadata, 'random_file.nc')
    
    # Verify
    assert collection_id == 'unknown'
