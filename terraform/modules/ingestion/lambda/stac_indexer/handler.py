"""
STAC Indexer Lambda Function
Reads STAC item from S3 and indexes it in DynamoDB (with optional OpenSearch support)
"""
import json
import os
import boto3
from decimal import Decimal
from typing import Dict, Optional, Any

s3_client = boto3.client('s3')
sns_client = boto3.client('sns')
dynamodb = boto3.resource('dynamodb')

def get_opensearch_client():
    """Create OpenSearch client with AWS authentication (for dual backend mode)"""
    from opensearchpy import OpenSearch, RequestsHttpConnection
    from requests_aws4auth import AWS4Auth
    
    region = os.environ['AWS_REGION']
    service = 'es'
    credentials = boto3.Session().get_credentials()
    awsauth = AWS4Auth(
        credentials.access_key,
        credentials.secret_key,
        region,
        service,
        session_token=credentials.token
    )
    
    host = os.environ['OPENSEARCH_ENDPOINT']
    
    client = OpenSearch(
        hosts=[{'host': host, 'port': 443}],
        http_auth=awsauth,
        use_ssl=True,
        verify_certs=True,
        connection_class=RequestsHttpConnection
    )
    
    return client

def convert_floats_to_decimal(obj: Any) -> Any:
    """
    Recursively convert float values to Decimal for DynamoDB compatibility.
    
    DynamoDB doesn't support float types - it requires Decimal for numeric values.
    This function walks through nested structures and converts all floats.
    
    Args:
        obj: Object to convert (can be dict, list, float, or other)
        
    Returns:
        Object with floats converted to Decimal
    """
    if isinstance(obj, list):
        return [convert_floats_to_decimal(item) for item in obj]
    elif isinstance(obj, dict):
        return {key: convert_floats_to_decimal(value) for key, value in obj.items()}
    elif isinstance(obj, float):
        return Decimal(str(obj))
    else:
        return obj

def validate_stac_item(item: Dict) -> None:
    """
    Validate STAC item has required fields
    
    Args:
        item: STAC item dictionary
        
    Raises:
        ValueError: If required field is missing
    """
    required = ["id", "type", "geometry", "properties", "assets"]
    for field in required:
        if field not in item:
            raise ValueError(f"Missing required field: {field}")

def index_to_dynamodb(stac_item: Dict) -> Dict:
    """
    Index STAC item in DynamoDB
    
    Args:
        stac_item: STAC item dictionary
        
    Returns:
        dict: Response with indexing status
    """
    table_name = os.environ.get('DYNAMODB_STAC_TABLE')
    if not table_name:
        raise ValueError("DYNAMODB_STAC_TABLE environment variable not set")
    
    table = dynamodb.Table(table_name)
    
    # Validate STAC item
    validate_stac_item(stac_item)
    
    # Extract GSI attributes
    collection = stac_item.get("collection", "unknown")
    datetime_str = stac_item.get("properties", {}).get("datetime", "")
    
    # Prepare DynamoDB item
    item = {
        "id": stac_item["id"],
        "type": stac_item["type"],
        "geometry": stac_item["geometry"],
        "bbox": stac_item.get("bbox", []),
        "properties": stac_item["properties"],
        "assets": stac_item["assets"],
        "collection": collection,
        "datetime": datetime_str,
        "stac_version": stac_item.get("stac_version", "1.0.0"),
        "stac_extensions": stac_item.get("stac_extensions", [])
    }
    
    # Convert all floats to Decimal for DynamoDB compatibility
    item = convert_floats_to_decimal(item)
    
    # Write to DynamoDB
    table.put_item(Item=item)
    
    print(f"Indexed STAC item in DynamoDB: {stac_item['id']}")
    
    return {
        'statusCode': 200,
        'result': 'created',
        'stac_id': stac_item['id'],
        'backend': 'dynamodb'
    }

def index_to_opensearch(stac_item: Dict) -> Dict:
    """
    Index STAC item in OpenSearch
    
    Args:
        stac_item: STAC item dictionary
        
    Returns:
        dict: Response with indexing status
    """
    os_client = get_opensearch_client()
    index_name = os.environ['OPENSEARCH_INDEX']
    
    # Create index if it doesn't exist
    if not os_client.indices.exists(index=index_name):
        os_client.indices.create(
            index=index_name,
            body={
                "mappings": {
                    "properties": {
                        "geometry": {"type": "geo_shape"},
                        "bbox": {"type": "geo_shape"},
                        "properties": {"type": "object"}
                    }
                }
            }
        )
    
    # Index the STAC item
    response = os_client.index(
        index=index_name,
        id=stac_item['id'],
        body=stac_item,
        refresh=True
    )
    
    print(f"Indexed STAC item in OpenSearch: {stac_item['id']}: {response['result']}")
    
    return {
        'statusCode': 200,
        'result': response['result'],
        'stac_id': stac_item['id'],
        'backend': 'opensearch'
    }

def lambda_handler(event, context):
    """
    Index STAC item in DynamoDB and/or OpenSearch based on STAC_BACKEND configuration
    
    Args:
        event: Contains stac_bucket and stac_key
        context: Lambda context
        
    Returns:
        dict: Response with indexing status
    """
    stac_backend = os.environ.get('STAC_BACKEND', 'dynamodb')
    
    try:
        stac_bucket = event['stac_bucket']
        stac_key = event['stac_key']
        
        # Read STAC item from S3
        response = s3_client.get_object(Bucket=stac_bucket, Key=stac_key)
        stac_item = json.loads(response['Body'].read().decode('utf-8'))
        
        results = []
        errors = []
        
        # Index based on backend configuration
        if stac_backend in ['dynamodb', 'dual']:
            try:
                result = index_to_dynamodb(stac_item)
                results.append(result)
                print(f"Successfully indexed to DynamoDB")
            except Exception as e:
                error_msg = f"DynamoDB indexing failed: {str(e)}"
                print(error_msg)
                errors.append({'backend': 'dynamodb', 'error': error_msg})
                if stac_backend == 'dynamodb':
                    raise
        
        if stac_backend in ['opensearch', 'dual']:
            try:
                result = index_to_opensearch(stac_item)
                results.append(result)
                print(f"Successfully indexed to OpenSearch")
            except Exception as e:
                error_msg = f"OpenSearch indexing failed: {str(e)}"
                print(error_msg)
                errors.append({'backend': 'opensearch', 'error': error_msg})
                if stac_backend == 'opensearch':
                    raise
        
        # Log which backends were written to
        backends_written = [r['backend'] for r in results]
        print(f"STAC item {stac_item['id']} indexed to backends: {', '.join(backends_written)}")
        
        # In dual mode, if one backend fails, log but don't fail the entire operation
        if stac_backend == 'dual' and errors:
            print(f"Partial write failures in dual mode: {errors}")
        
        return {
            'statusCode': 200,
            'results': results,
            'errors': errors if errors else None,
            'stac_id': stac_item['id']
        }
        
    except Exception as e:
        error_message = f"Error indexing STAC item: {str(e)}"
        print(error_message)
        
        # Send SNS notification on failure
        try:
            sns_topic_arn = os.environ['SNS_TOPIC_ARN']
            sns_client.publish(
                TopicArn=sns_topic_arn,
                Subject='STAC Indexing Failure',
                Message=json.dumps({
                    'error': error_message,
                    'stac_bucket': event.get('stac_bucket'),
                    'stac_key': event.get('stac_key'),
                    'backend': stac_backend
                }, indent=2)
            )
        except Exception as sns_error:
            print(f"Failed to send SNS notification: {str(sns_error)}")
        
        raise
