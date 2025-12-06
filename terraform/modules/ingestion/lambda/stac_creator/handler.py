"""
STAC Creator Lambda Function
Reads Zarr metadata and generates STAC item JSON with bounding box

Requirements: 4.1, 4.2, 4.3, 4.5, 4.6, 4.7, 8.1, 8.2, 8.3, 8.4
"""
import json
import os
import re
import boto3
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict

s3_client = boto3.client('s3')


def read_metadata_from_s3(bucket, key, client=None):
    """
    Read metadata file from S3
    
    Args:
        bucket: S3 bucket name
        key: S3 key for metadata file
        client: Optional S3 client (for testing)
        
    Returns:
        dict: Metadata containing bbox and other information
        
    Raises:
        ValueError: If metadata file cannot be read
    """
    if client is None:
        client = s3_client
    
    try:
        response = client.get_object(Bucket=bucket, Key=key)
        metadata = json.loads(response['Body'].read().decode('utf-8'))
        return metadata
    except Exception as e:
        raise ValueError(f"Failed to read metadata from s3://{bucket}/{key}: {e}")


def create_geometry_from_bbox(bbox):
    """
    Create GeoJSON polygon geometry from bounding box
    
    Args:
        bbox: List of [west, south, east, north]
        
    Returns:
        dict: GeoJSON Polygon geometry
    """
    west, south, east, north = bbox
    
    return {
        "type": "Polygon",
        "coordinates": [[
            [west, south],   # SW corner
            [east, south],   # SE corner
            [east, north],   # NE corner
            [west, north],   # NW corner
            [west, south]    # Close the polygon
        ]]
    }


def derive_stac_key(zarr_key):
    """
    Derive STAC key from zarr key
    
    Args:
        zarr_key: Zarr file S3 key (e.g., "zarr/file.zarr")
        
    Returns:
        str: STAC key in format "stac/{basename}.json"
    """
    basename = Path(zarr_key).stem
    return f"stac/{basename}.json"


def escape_special_characters(value: Any) -> Any:
    """
    Escape special characters in metadata values for safe storage and search.
    
    Handles strings, lists, and nested dictionaries recursively.
    Special characters that could cause issues in JSON or search queries
    are properly escaped.
    
    Args:
        value: Value to escape (string, list, dict, or other)
        
    Returns:
        Escaped value of the same type
        
    Requirements: 8.5
    """
    if isinstance(value, str):
        # Escape backslashes first to avoid double-escaping
        value = value.replace('\\', '\\\\')
        # Escape quotes
        value = value.replace('"', '\\"')
        value = value.replace("'", "\\'")
        # Escape newlines and tabs
        value = value.replace('\n', '\\n')
        value = value.replace('\t', '\\t')
        return value
    elif isinstance(value, list):
        return [escape_special_characters(item) for item in value]
    elif isinstance(value, dict):
        return {k: escape_special_characters(v) for k, v in value.items()}
    else:
        # Numbers, booleans, None, etc. don't need escaping
        return value


def validate_metadata_structure(metadata: Dict[str, Any]) -> Dict[str, Any]:
    """
    Validate and sanitize metadata structure.
    
    Ensures metadata has expected structure and handles missing/incomplete data.
    Removes None values and empty structures.
    
    Args:
        metadata: Raw metadata dictionary
        
    Returns:
        Validated and sanitized metadata dictionary
        
    Requirements: 7.5, 8.5
    """
    validated = {}
    
    # Ensure bbox exists and is valid
    if 'bbox' in metadata and metadata['bbox']:
        bbox = metadata['bbox']
        if isinstance(bbox, list) and len(bbox) == 4:
            # Validate bbox values are numbers
            try:
                validated['bbox'] = [float(x) for x in bbox]
            except (ValueError, TypeError):
                print(f"Warning: Invalid bbox values: {bbox}, using default")
                validated['bbox'] = [-180, -90, 180, 90]
        else:
            print(f"Warning: Invalid bbox structure: {bbox}, using default")
            validated['bbox'] = [-180, -90, 180, 90]
    else:
        validated['bbox'] = [-180, -90, 180, 90]
    
    # Copy other fields, removing None and empty values
    for key in ['zarr_key', 'zarr_bucket', 'is_default_bbox', 'collection_id', 'temporal']:
        if key in metadata and metadata[key] is not None:
            validated[key] = metadata[key]
    
    # Handle variables - ensure it's a list
    if 'variables' in metadata:
        variables = metadata['variables']
        if isinstance(variables, list):
            # Filter out None values and empty dicts
            validated['variables'] = [
                v for v in variables 
                if v is not None and (not isinstance(v, dict) or v)
            ]
        else:
            validated['variables'] = []
    else:
        validated['variables'] = []
    
    # Handle global_attributes - ensure it's a dict
    if 'global_attributes' in metadata:
        attrs = metadata['global_attributes']
        if isinstance(attrs, dict):
            # Remove None values
            validated['global_attributes'] = {
                k: v for k, v in attrs.items() 
                if v is not None and v != ''
            }
        else:
            validated['global_attributes'] = {}
    else:
        validated['global_attributes'] = {}
    
    # Handle collections - ensure it's a list
    if 'collections' in metadata:
        collections = metadata['collections']
        if isinstance(collections, list):
            validated['collections'] = [
                c for c in collections 
                if c is not None and (not isinstance(c, dict) or c)
            ]
        else:
            validated['collections'] = []
    else:
        validated['collections'] = []
    
    # Handle stac_properties - ensure it's a dict
    if 'stac_properties' in metadata:
        props = metadata['stac_properties']
        if isinstance(props, dict):
            validated['stac_properties'] = {
                k: v for k, v in props.items() 
                if v is not None and v != ''
            }
        else:
            validated['stac_properties'] = {}
    else:
        validated['stac_properties'] = {}
    
    return validated


def create_or_update_collection(
    s3_client,
    bucket: str,
    collection_id: str,
    collection_metadata: Dict[str, Any]
) -> None:
    """
    Create or update a STAC collection.
    
    Collections are stored in S3 at collections/{collection_id}.json.
    If a collection already exists, its metadata is updated with new information.
    
    Args:
        s3_client: Boto3 S3 client
        bucket: S3 bucket for collections
        collection_id: Collection identifier
        collection_metadata: Metadata for the collection
        
    Requirements: 6.5, 7.4, 7.5
    """
    collection_key = f"collections/{collection_id}.json"
    
    try:
        # Try to read existing collection
        response = s3_client.get_object(Bucket=bucket, Key=collection_key)
        existing_collection = json.loads(response['Body'].read().decode('utf-8'))
        print(f"Found existing collection: {collection_id}")
        
        # Update metadata if new info is more complete
        # Update description if new one is provided and better than existing
        if collection_metadata.get('description'):
            # Update if existing is empty or if new description is more detailed
            if (not existing_collection.get('description') or 
                existing_collection.get('description') == f"Collection for {collection_id}" or
                len(collection_metadata['description']) > len(existing_collection.get('description', ''))):
                existing_collection['description'] = collection_metadata['description']
                if 'title' in existing_collection:
                    existing_collection['title'] = collection_metadata['description']
        
        # Update units if new one is provided and better than existing
        if collection_metadata.get('units') and collection_metadata['units'] != 'unknown':
            if 'summaries' not in existing_collection:
                existing_collection['summaries'] = {}
            existing_collection['summaries']['units'] = [collection_metadata['units']]
        
        # Update timestamp
        existing_collection['updated'] = datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
        
        collection = existing_collection
        
    except s3_client.exceptions.NoSuchKey:
        # Collection doesn't exist, create new one
        print(f"Creating new collection: {collection_id}")
        
        collection = {
            "type": "Collection",
            "stac_version": "1.0.0",
            "id": collection_id,
            "title": collection_metadata.get('description', collection_id),
            "description": collection_metadata.get('description', f"Collection for {collection_id}"),
            "license": "proprietary",
            "extent": {
                "spatial": {
                    "bbox": [[-180, -90, 180, 90]]
                },
                "temporal": {
                    "interval": [[None, None]]
                }
            },
            "summaries": {
                "units": [collection_metadata.get('units', 'unknown')]
            },
            "created": datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z'),
            "updated": datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
        }
    
    # Write collection back to S3
    s3_client.put_object(
        Bucket=bucket,
        Key=collection_key,
        Body=json.dumps(collection, indent=2),
        ContentType='application/json'
    )
    
    print(f"Collection saved: s3://{bucket}/{collection_key}")


def handle_multiple_variables(
    s3_client,
    bucket: str,
    metadata: Dict[str, Any],
    base_stac_item: Dict[str, Any]
) -> list:
    """
    Handle files with multiple variables by creating separate STAC items.
    
    For files with multiple data variables, creates one STAC item per variable,
    each in its appropriate collection.
    
    Args:
        s3_client: Boto3 S3 client
        bucket: S3 bucket for STAC items
        metadata: Validated metadata dictionary
        base_stac_item: Base STAC item to clone for each variable
        
    Returns:
        List of created STAC item keys
        
    Requirements: 6.5, 7.4
    """
    created_items = []
    
    variables = metadata.get('variables', [])
    collections = metadata.get('collections', [])
    
    if not variables or len(variables) <= 1:
        # Single variable or no variables, return empty list
        # Caller will handle single item creation
        return created_items
    
    print(f"Handling {len(variables)} variables in file")
    
    # Create one STAC item per variable
    for i, variable in enumerate(variables):
        var_name = variable.get('name', f'var_{i}')
        
        # Find corresponding collection
        collection_info = collections[i] if i < len(collections) else None
        collection_id = collection_info.get('name', 'unknown') if collection_info else 'unknown'
        
        # Clone base item
        var_item = json.loads(json.dumps(base_stac_item))  # Deep copy
        
        # Update for this variable
        var_item['id'] = f"{base_stac_item['id']}_{var_name}"
        var_item['collection'] = collection_id
        
        # Update properties to focus on this variable
        var_item['properties']['variable'] = var_name
        var_item['properties']['variable_metadata'] = [variable]
        
        if variable.get('units'):
            var_item['properties']['units'] = [variable['units']]
        
        # Create/update collection for this variable
        if collection_info:
            create_or_update_collection(s3_client, bucket, collection_id, collection_info)
        
        # Write STAC item
        var_stac_key = f"stac/{var_item['id']}.json"
        s3_client.put_object(
            Bucket=bucket,
            Key=var_stac_key,
            Body=json.dumps(var_item, indent=2),
            ContentType='application/json'
        )
        
        print(f"Created STAC item for variable {var_name}: s3://{bucket}/{var_stac_key}")
        created_items.append(var_stac_key)
    
    return created_items


def build_stac_properties(metadata: Dict[str, Any]) -> Dict[str, Any]:
    """
    Build comprehensive STAC properties from metadata.
    
    Combines variable metadata, global attributes, and collection information
    into searchable STAC properties. All metadata fields are made searchable.
    
    Args:
        metadata: Validated metadata dictionary
        
    Returns:
        STAC properties dictionary with all searchable metadata
        
    Requirements: 8.1, 8.2, 8.3, 8.4
    """
    now = datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
    
    # Use temporal metadata if available, otherwise use current time
    temporal = metadata.get('temporal')
    if temporal and temporal.get('start'):
        # Use start time as primary datetime
        datetime_value = temporal['start']
        # Add temporal extent properties
        properties = {
            "datetime": datetime_value,
            "start_datetime": temporal['start'],
            "end_datetime": temporal.get('end', temporal['start']),
            "created": now,
            "updated": now
        }
        print(f"Using temporal extent from metadata: {datetime_value}")
    else:
        # Fallback to current time
        properties = {
            "datetime": now,
            "created": now,
            "updated": now
        }
        print(f"No temporal metadata found, using current time: {now}")
    
    # Add variable names for easy searching
    if 'variables' in metadata and metadata['variables']:
        # Extract just the variable names
        var_names = [v.get('name', '') for v in metadata['variables'] if v.get('name')]
        if var_names:
            properties['variables'] = var_names
        
        # Add full variable metadata for detailed queries
        properties['variable_metadata'] = metadata['variables']
        
        # Add units for searching by units (Requirement 8.3)
        units = [v.get('units', '') for v in metadata['variables'] if v.get('units')]
        if units:
            properties['units'] = list(set(units))  # Unique units
    
    # Add global attributes for searching (Requirement 8.4)
    if 'global_attributes' in metadata and metadata['global_attributes']:
        # Merge global attributes into properties (will be escaped at the end)
        for key, value in metadata['global_attributes'].items():
            properties[key] = value
    
    # Add collection information
    if 'collections' in metadata and metadata['collections']:
        properties['collections'] = metadata['collections']
    
    # Add any additional properties from stac_properties
    if 'stac_properties' in metadata and metadata['stac_properties']:
        for key, value in metadata['stac_properties'].items():
            if key not in properties:  # Don't overwrite existing
                properties[key] = value
    
    # Escape all string values in properties
    properties = escape_special_characters(properties)
    
    return properties


def lambda_handler(event, context):
    """
    Create STAC item from Zarr metadata
    
    Args:
        event: Contains input_key, zarr_bucket, cog_bucket, stac_bucket
        context: Lambda context
        
    Returns:
        dict: Response with STAC item S3 key
    """
    try:
        # Extract inputs from Step Functions
        input_key = event['input_key']
        zarr_bucket = event['zarr_bucket']
        cog_bucket = event['cog_bucket']
        stac_bucket = event.get('stac_bucket', zarr_bucket)
        
        # Compute zarr_key and cog_key from input_key
        # Transform ingestion/file.nc -> zarr/file.zarr
        filename = input_key.split('/')[-1]  # Get last part
        zarr_filename = filename.replace('.nc', '.zarr')
        zarr_key = f'zarr/{zarr_filename}'
        
        # Transform ingestion/file.nc -> cog/file.tif
        cog_filename = filename.replace('.nc', '.tif')
        cog_key = f'cog/{cog_filename}'
        
        print(f"Input: {input_key}")
        print(f"Creating STAC item for zarr: s3://{zarr_bucket}/{zarr_key}")
        print(f"COG location: s3://{cog_bucket}/{cog_key}")
        
        # Read metadata file from S3
        # Metadata file is created by zarr_converter and contains bbox
        metadata_key = zarr_key.replace('.zarr', '_metadata.json')
        print(f"Reading metadata from: s3://{zarr_bucket}/{metadata_key}")
        
        # Read and validate metadata
        raw_metadata = read_metadata_from_s3(zarr_bucket, metadata_key)
        metadata = validate_metadata_structure(raw_metadata)
        
        bbox = metadata['bbox']
        print(f"Extracted bounding box: {bbox}")
        
        # Build comprehensive STAC properties with all metadata
        properties = build_stac_properties(metadata)
        print(f"Built STAC properties with {len(properties)} fields")
        
        # Extract basename for STAC ID
        basename = Path(zarr_key).stem
        
        # Determine collection ID
        collection_id = metadata.get('collection_id', 'unknown')
        print(f"Collection ID: {collection_id}")
        
        # Create STAC item with enhanced metadata
        stac_item = {
            "type": "Feature",
            "stac_version": "1.0.0",
            "id": basename,
            "collection": collection_id,
            "bbox": bbox,
            "geometry": create_geometry_from_bbox(bbox),
            "properties": properties,
            "assets": {
                "zarr": {
                    "href": f"s3://{zarr_bucket}/{zarr_key}",
                    "type": "application/vnd+zarr",
                    "roles": ["data"]
                },
                "cog": {
                    "href": f"s3://{cog_bucket}/{cog_key}",
                    "type": "image/tiff; application=geotiff; profile=cloud-optimized",
                    "roles": ["visual"]
                }
            },
            "links": []
        }
        
        # Create or update collection
        stac_bucket = os.environ.get('STAC_BUCKET', zarr_bucket)
        
        if metadata.get('collections'):
            # Get primary collection info (first variable's collection)
            primary_collection = metadata['collections'][0]
            create_or_update_collection(
                s3_client,
                stac_bucket,
                collection_id,
                primary_collection
            )
        
        # Handle multiple variables if present
        created_items = handle_multiple_variables(
            s3_client,
            stac_bucket,
            metadata,
            stac_item
        )
        
        if created_items:
            # Multiple variables - items already created
            print(f"Created {len(created_items)} STAC items for multiple variables")
            return {
                'statusCode': 200,
                'stac_keys': created_items,
                'stac_ids': [Path(key).stem for key in created_items],
                'stac_bucket': stac_bucket,
                'collection_id': collection_id,
                'variable_count': len(created_items)
            }
        else:
            # Single variable - write main STAC item
            stac_key = derive_stac_key(zarr_key)
            
            s3_client.put_object(
                Bucket=stac_bucket,
                Key=stac_key,
                Body=json.dumps(stac_item, indent=2),
                ContentType='application/json'
            )
            
            print(f"Created STAC item: s3://{stac_bucket}/{stac_key}")
            
            return {
                'statusCode': 200,
                'stac_key': stac_key,
                'stac_id': stac_item['id'],
                'stac_bucket': stac_bucket,
                'collection_id': collection_id
            }
        
    except Exception as e:
        print(f"Error creating STAC item: {str(e)}")
        import traceback
        traceback.print_exc()
        raise
