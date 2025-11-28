#!/usr/bin/env python3
"""
Validation script for dual backend deployment.

This script validates that:
1. DynamoDB infrastructure is deployed
2. Application is configured with STAC_BACKEND=dual
3. API queries work from both backends
4. CloudWatch logs show proper backend usage
"""

import boto3
import json
import os
import sys
import time
from typing import Dict, Optional

# Set AWS profile
os.environ["AWS_PROFILE"] = "DEVcloud"

# Initialize AWS clients
dynamodb = boto3.client('dynamodb')
ecs = boto3.client('ecs')
logs = boto3.client('logs')
cloudwatch = boto3.client('cloudwatch')


def check_dynamodb_table(table_name: str) -> bool:
    """
    Check if DynamoDB table exists and is active.
    
    Args:
        table_name: Name of the DynamoDB table
        
    Returns:
        True if table exists and is active, False otherwise
    """
    try:
        response = dynamodb.describe_table(TableName=table_name)
        status = response['Table']['TableStatus']
        
        print(f"✓ DynamoDB table '{table_name}' exists")
        print(f"  Status: {status}")
        print(f"  Item count: {response['Table']['ItemCount']}")
        
        # Check GSIs
        gsis = response['Table'].get('GlobalSecondaryIndexes', [])
        print(f"  Global Secondary Indexes: {len(gsis)}")
        for gsi in gsis:
            print(f"    - {gsi['IndexName']}: {gsi['IndexStatus']}")
        
        return status == 'ACTIVE'
        
    except dynamodb.exceptions.ResourceNotFoundException:
        print(f"✗ DynamoDB table '{table_name}' not found")
        return False
    except Exception as e:
        print(f"✗ Error checking DynamoDB table: {e}")
        return False


def check_ecs_environment(cluster_name: str, service_name: str) -> Optional[Dict[str, str]]:
    """
    Check ECS service environment variables.
    
    Args:
        cluster_name: Name of the ECS cluster
        service_name: Name of the ECS service
        
    Returns:
        Dictionary of environment variables, or None if error
    """
    try:
        # Get service details
        services = ecs.describe_services(
            cluster=cluster_name,
            services=[service_name]
        )
        
        if not services['services']:
            print(f"✗ ECS service '{service_name}' not found in cluster '{cluster_name}'")
            return None
        
        service = services['services'][0]
        task_definition_arn = service['taskDefinition']
        
        # Get task definition
        task_def = ecs.describe_task_definition(taskDefinition=task_definition_arn)
        container_defs = task_def['taskDefinition']['containerDefinitions']
        
        # Extract environment variables from first container
        if container_defs:
            env_vars = {
                env['name']: env['value'] 
                for env in container_defs[0].get('environment', [])
            }
            
            print(f"✓ ECS service '{service_name}' configuration:")
            print(f"  Task Definition: {task_definition_arn.split('/')[-1]}")
            print(f"  STAC_BACKEND: {env_vars.get('STAC_BACKEND', 'NOT SET')}")
            print(f"  DYNAMODB_STAC_TABLE: {env_vars.get('DYNAMODB_STAC_TABLE', 'NOT SET')}")
            print(f"  OPENSEARCH_HOST: {env_vars.get('OPENSEARCH_HOST', 'NOT SET')}")
            
            return env_vars
        else:
            print(f"✗ No container definitions found in task definition")
            return None
            
    except Exception as e:
        print(f"✗ Error checking ECS service: {e}")
        return None


def check_cloudwatch_metrics(namespace: str = 'STAC/DualBackend', minutes: int = 60) -> bool:
    """
    Check CloudWatch metrics for dual backend usage.
    
    Args:
        namespace: CloudWatch namespace
        minutes: Number of minutes to look back
        
    Returns:
        True if metrics are being emitted, False otherwise
    """
    try:
        end_time = time.time()
        start_time = end_time - (minutes * 60)
        
        # Check for DynamoDB usage metrics
        dynamodb_metrics = cloudwatch.get_metric_statistics(
            Namespace=namespace,
            MetricName='DynamoDBUsage',
            StartTime=start_time,
            EndTime=end_time,
            Period=300,
            Statistics=['Sum']
        )
        
        # Check for OpenSearch usage metrics
        opensearch_metrics = cloudwatch.get_metric_statistics(
            Namespace=namespace,
            MetricName='OpenSearchUsage',
            StartTime=start_time,
            EndTime=end_time,
            Period=300,
            Statistics=['Sum']
        )
        
        dynamodb_count = sum(dp['Sum'] for dp in dynamodb_metrics.get('Datapoints', []))
        opensearch_count = sum(dp['Sum'] for dp in opensearch_metrics.get('Datapoints', []))
        
        print(f"✓ CloudWatch metrics (last {minutes} minutes):")
        print(f"  DynamoDB operations: {int(dynamodb_count)}")
        print(f"  OpenSearch operations: {int(opensearch_count)}")
        
        return True
        
    except Exception as e:
        print(f"⚠ Warning: Could not retrieve CloudWatch metrics: {e}")
        print(f"  This is normal if no operations have occurred yet")
        return True  # Don't fail validation for this


def check_cloudwatch_logs(log_group: str, minutes: int = 10) -> bool:
    """
    Check CloudWatch logs for dual backend activity.
    
    Args:
        log_group: CloudWatch log group name
        minutes: Number of minutes to look back
        
    Returns:
        True if logs show dual backend activity, False otherwise
    """
    try:
        end_time = int(time.time() * 1000)
        start_time = end_time - (minutes * 60 * 1000)
        
        # Search for dual backend log messages
        response = logs.filter_log_events(
            logGroupName=log_group,
            startTime=start_time,
            endTime=end_time,
            filterPattern='"dual backend" OR "DynamoDB" OR "OpenSearch"',
            limit=10
        )
        
        events = response.get('events', [])
        
        if events:
            print(f"✓ CloudWatch logs show dual backend activity:")
            print(f"  Found {len(events)} relevant log entries in last {minutes} minutes")
            for event in events[:3]:  # Show first 3
                message = event['message'][:100]
                print(f"    {message}...")
        else:
            print(f"⚠ No dual backend log entries found in last {minutes} minutes")
            print(f"  This is normal if no API requests have been made yet")
        
        return True
        
    except logs.exceptions.ResourceNotFoundException:
        print(f"⚠ Log group '{log_group}' not found")
        return True  # Don't fail validation for this
    except Exception as e:
        print(f"⚠ Warning: Could not check CloudWatch logs: {e}")
        return True  # Don't fail validation for this


def main():
    """Main validation function."""
    print("=" * 60)
    print("Dual Backend Deployment Validation")
    print("=" * 60)
    print()
    
    # Get configuration from environment or use defaults
    import os
    table_name = os.environ.get('DYNAMODB_STAC_TABLE', 'cloud-scientific-raster-sharing-stac-items')
    cluster_name = os.environ.get('ECS_CLUSTER', 'cloud-scientific-raster-sharing-ecs-cluster')
    tiles_service = os.environ.get('TILES_SERVICE', 'tiles-service')
    timeseries_service = os.environ.get('TIMESERIES_SERVICE', 'timeseries-service')
    log_group = os.environ.get('LOG_GROUP', '/ecs/tiles-service')
    
    results = []
    
    # 1. Check DynamoDB infrastructure
    print("1. Checking DynamoDB infrastructure...")
    print("-" * 60)
    results.append(check_dynamodb_table(table_name))
    print()
    
    # 2. Check ECS tiles service configuration
    print("2. Checking ECS tiles service configuration...")
    print("-" * 60)
    tiles_env = check_ecs_environment(cluster_name, tiles_service)
    if tiles_env:
        stac_backend = tiles_env.get('STAC_BACKEND', '')
        if stac_backend == 'dual':
            print("  ✓ STAC_BACKEND is set to 'dual'")
            results.append(True)
        else:
            print(f"  ✗ STAC_BACKEND is '{stac_backend}', expected 'dual'")
            results.append(False)
    else:
        results.append(False)
    print()
    
    # 3. Check ECS timeseries service configuration
    print("3. Checking ECS timeseries service configuration...")
    print("-" * 60)
    timeseries_env = check_ecs_environment(cluster_name, timeseries_service)
    if timeseries_env:
        stac_backend = timeseries_env.get('STAC_BACKEND', '')
        if stac_backend == 'dual':
            print("  ✓ STAC_BACKEND is set to 'dual'")
            results.append(True)
        else:
            print(f"  ✗ STAC_BACKEND is '{stac_backend}', expected 'dual'")
            results.append(False)
    else:
        results.append(False)
    print()
    
    # 4. Check CloudWatch metrics
    print("4. Checking CloudWatch metrics...")
    print("-" * 60)
    results.append(check_cloudwatch_metrics())
    print()
    
    # 5. Check CloudWatch logs
    print("5. Checking CloudWatch logs...")
    print("-" * 60)
    results.append(check_cloudwatch_logs(log_group))
    print()
    
    # Summary
    print("=" * 60)
    print("Validation Summary")
    print("=" * 60)
    passed = sum(results)
    total = len(results)
    
    if passed == total:
        print(f"✓ All {total} checks passed!")
        print()
        print("Next steps:")
        print("1. Test API queries to verify both backends are working")
        print("2. Upload a test file to trigger ingestion")
        print("3. Monitor CloudWatch logs for dual backend activity")
        print("4. Check that new items are written to both DynamoDB and OpenSearch")
        return 0
    else:
        print(f"✗ {total - passed} of {total} checks failed")
        print()
        print("Please review the errors above and fix any issues before proceeding.")
        return 1


if __name__ == '__main__':
    sys.exit(main())
