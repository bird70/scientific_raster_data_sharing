"""
STAC Indexer Lambda Function
Reads STAC item from S3 and indexes it in OpenSearch
"""
import json
import os
import boto3
from opensearchpy import OpenSearch, RequestsHttpConnection
from requests_aws4auth import AWS4Auth

s3_client = boto3.client('s3')
sns_client = boto3.client('sns')

def get_opensearch_client():
    """Create OpenSearch client with AWS authentication"""
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

def lambda_handler(event, context):
    """
    Index STAC item in OpenSearch
    
    Args:
        event: Contains stac_bucket and stac_key
        context: Lambda context
        
    Returns:
        dict: Response with indexing status
    """
    try:
        stac_bucket = event['stac_bucket']
        stac_key = event['stac_key']
        
        # Read STAC item from S3
        response = s3_client.get_object(Bucket=stac_bucket, Key=stac_key)
        stac_item = json.loads(response['Body'].read().decode('utf-8'))
        
        # Index in OpenSearch
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
        
        print(f"Indexed STAC item {stac_item['id']}: {response['result']}")
        
        return {
            'statusCode': 200,
            'result': response['result'],
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
                    'stac_key': event.get('stac_key')
                }, indent=2)
            )
        except Exception as sns_error:
            print(f"Failed to send SNS notification: {str(sns_error)}")
        
        raise
