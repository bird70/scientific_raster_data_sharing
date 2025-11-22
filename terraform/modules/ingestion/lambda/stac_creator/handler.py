"""
STAC Creator Lambda Function
Reads Zarr metadata and generates STAC item JSON
"""
import json
import os
import boto3
from datetime import datetime
import uuid

s3_client = boto3.client('s3')

def lambda_handler(event, context):
    """
    Create STAC item from Zarr metadata
    
    Args:
        event: Contains zarr_bucket, zarr_key, cog_bucket, cog_key, metadata
        context: Lambda context
        
    Returns:
        dict: Response with STAC item S3 key
    """
    try:
        zarr_bucket = event['zarr_bucket']
        zarr_key = event['zarr_key']
        cog_bucket = event['cog_bucket']
        cog_key = event['cog_key']
        metadata = event.get('metadata', {})
        
        # In a real implementation, we would read Zarr metadata from S3
        # For now, create a minimal STAC item
        stac_item = {
            "stac_version": "1.0.0",
            "type": "Feature",
            "id": str(uuid.uuid4()),
            "geometry": {
                "type": "Polygon",
                "coordinates": [[
                    [140.0, -40.0],
                    [160.0, -40.0],
                    [160.0, -20.0],
                    [140.0, -20.0],
                    [140.0, -40.0]
                ]]
            },
            "bbox": [140.0, -40.0, 160.0, -20.0],
            "properties": {
                "datetime": metadata.get('event_time', datetime.utcnow().isoformat() + 'Z'),
                "created": datetime.utcnow().isoformat() + 'Z',
                "updated": datetime.utcnow().isoformat() + 'Z'
            },
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
        
        # Write STAC item to S3
        stac_bucket = os.environ['STAC_BUCKET']
        stac_key = f"items/{stac_item['id']}.json"
        
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
            'stac_id': stac_item['id']
        }
        
    except Exception as e:
        print(f"Error creating STAC item: {str(e)}")
        raise
