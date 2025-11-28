"""
S3 Trigger Lambda Function
Triggered by S3 ObjectCreated events, validates the file and starts Step Functions execution
"""
import json
import os
import boto3
from urllib.parse import unquote_plus

sfn_client = boto3.client('stepfunctions')

def lambda_handler(event, context):
    """
    Handle S3 event notification and start Step Functions execution
    
    Args:
        event: S3 event notification
        context: Lambda context
        
    Returns:
        dict: Response with execution ARN
    """
    try:
        # Extract S3 event details
        for record in event['Records']:
            bucket = record['s3']['bucket']['name']
            key = unquote_plus(record['s3']['object']['key'])
            
            # Validate file extension
            if not key.endswith('.nc'):
                print(f"Skipping non-NetCDF file: {key}")
                continue
            
            # Prepare Step Functions input
            execution_input = {
                'bucket': bucket,
                'key': key,
                'metadata': {
                    'source': 'S3 upload',
                    'event_time': record['eventTime']
                }
            }
            
            # Start Step Functions execution
            state_machine_arn = os.environ['STATE_MACHINE_ARN']
            execution_name = key.replace('/', '-').replace('.nc', f'-{context.aws_request_id[:8]}')
            
            response = sfn_client.start_execution(
                stateMachineArn=state_machine_arn,
                name=execution_name,
                input=json.dumps(execution_input)
            )
            
            print(f"Started execution: {response['executionArn']}")
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Execution started',
                    'executionArn': response['executionArn']
                })
            }
            
    except Exception as e:
        print(f"Error processing S3 event: {str(e)}")
        raise
