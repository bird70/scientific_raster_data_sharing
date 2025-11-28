#!/usr/bin/env python3
"""
STAC Migration Script: OpenSearch to DynamoDB

This script migrates STAC items from OpenSearch to DynamoDB with the following features:
- Scrolls through all items in OpenSearch
- Transforms items to DynamoDB format with GSI attributes
- Batch writes to DynamoDB (25 items per batch)
- Progress logging and error tracking
- Resume capability to skip already migrated items
- Dry-run mode for validation
- Comprehensive migration report

Requirements: 4.1, 4.2, 4.3, 4.4, 4.5
"""

import argparse
import boto3
import json
import logging
import os
import sys
from datetime import datetime
from typing import Dict, Iterator, List, Optional, Set
from opensearchpy import OpenSearch, RequestsHttpConnection
from requests_aws4auth import AWS4Auth

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler(f'migration_{datetime.now().strftime("%Y%m%d_%H%M%S")}.log')
    ]
)
logger = logging.getLogger(__name__)


class MigrationStats:
    """Track migration statistics"""
    
    def __init__(self):
        self.total_read = 0
        self.total_written = 0
        self.total_skipped = 0
        self.total_errors = 0
        self.errors: List[Dict] = []
        self.start_time = datetime.now()
    
    def add_read(self, count: int = 1):
        self.total_read += count
    
    def add_written(self, count: int = 1):
        self.total_written += count
    
    def add_skipped(self, count: int = 1):
        self.total_skipped += count
    
    def add_error(self, item_id: str, error: str):
        self.total_errors += 1
        self.errors.append({
            'item_id': item_id,
            'error': error,
            'timestamp': datetime.now().isoformat()
        })
    
    def get_report(self) -> Dict:
        """Generate migration report"""
        duration = (datetime.now() - self.start_time).total_seconds()
        
        return {
            'summary': {
                'total_read': self.total_read,
                'total_written': self.total_written,
                'total_skipped': self.total_skipped,
                'total_errors': self.total_errors,
                'duration_seconds': duration,
                'items_per_second': self.total_written / duration if duration > 0 else 0
            },
            'errors': self.errors
        }


def get_opensearch_client(host: str, region: str, use_auth: bool = True) -> OpenSearch:
    """
    Create OpenSearch client with optional AWS authentication.
    
    Args:
        host: OpenSearch endpoint (without https://)
        region: AWS region
        use_auth: Whether to use AWS authentication
    
    Returns:
        OpenSearch client instance
    """
    if use_auth:
        credentials = boto3.Session().get_credentials()
        awsauth = AWS4Auth(
            credentials.access_key,
            credentials.secret_key,
            region,
            'es',
            session_token=credentials.token
        )
        http_auth = awsauth
    else:
        http_auth = None
    
    client = OpenSearch(
        hosts=[{'host': host, 'port': 443}],
        http_auth=http_auth,
        use_ssl=True,
        verify_certs=True,
        connection_class=RequestsHttpConnection
    )
    
    logger.info(f"Connected to OpenSearch: {host}")
    return client


def scroll_opensearch_items(
    os_client: OpenSearch,
    index: str,
    scroll_size: int = 100
) -> Iterator[Dict]:
    """
    Scroll through all items in OpenSearch index.
    
    Args:
        os_client: OpenSearch client
        index: Index name
        scroll_size: Number of items per scroll request
    
    Yields:
        STAC items from OpenSearch
    """
    query = {"query": {"match_all": {}}}
    
    try:
        response = os_client.search(
            index=index,
            body=query,
            scroll='5m',
            size=scroll_size
        )
        
        scroll_id = response['_scroll_id']
        hits = response['hits']['hits']
        
        logger.info(f"Starting scroll through {response['hits']['total']['value']} items")
        
        while hits:
            for hit in hits:
                yield hit['_source']
            
            # Get next batch
            response = os_client.scroll(scroll_id=scroll_id, scroll='5m')
            scroll_id = response['_scroll_id']
            hits = response['hits']['hits']
        
        # Clear scroll context
        os_client.clear_scroll(scroll_id=scroll_id)
        
    except Exception as e:
        logger.error(f"Error scrolling OpenSearch: {e}")
        raise


def transform_item(item: Dict) -> Dict:
    """
    Transform OpenSearch item to DynamoDB format.
    
    Extracts collection and datetime for GSI attributes and ensures
    all required STAC fields are present.
    
    Args:
        item: STAC item from OpenSearch
    
    Returns:
        Transformed item for DynamoDB
    """
    # Extract GSI attributes
    collection = item.get("collection", "unknown")
    datetime_str = item.get("properties", {}).get("datetime", "")
    
    # Build DynamoDB item with all required fields
    dynamodb_item = {
        "id": item["id"],
        "type": item.get("type", "Feature"),
        "geometry": item.get("geometry", {}),
        "bbox": item.get("bbox", []),
        "properties": item.get("properties", {}),
        "assets": item.get("assets", {}),
        "collection": collection,
        "datetime": datetime_str,
        "stac_version": item.get("stac_version", "1.0.0"),
        "stac_extensions": item.get("stac_extensions", [])
    }
    
    return dynamodb_item


def get_existing_item_ids(
    dynamodb_table,
    limit: Optional[int] = None
) -> Set[str]:
    """
    Get set of existing item IDs in DynamoDB for resume capability.
    
    Args:
        dynamodb_table: DynamoDB table resource
        limit: Optional limit on number of items to check
    
    Returns:
        Set of item IDs already in DynamoDB
    """
    logger.info("Scanning DynamoDB for existing items (for resume capability)...")
    
    existing_ids = set()
    scan_kwargs = {
        'ProjectionExpression': 'id'
    }
    
    if limit:
        scan_kwargs['Limit'] = limit
    
    try:
        response = dynamodb_table.scan(**scan_kwargs)
        
        for item in response.get('Items', []):
            existing_ids.add(item['id'])
        
        # Handle pagination
        while 'LastEvaluatedKey' in response and (limit is None or len(existing_ids) < limit):
            scan_kwargs['ExclusiveStartKey'] = response['LastEvaluatedKey']
            response = dynamodb_table.scan(**scan_kwargs)
            
            for item in response.get('Items', []):
                existing_ids.add(item['id'])
        
        logger.info(f"Found {len(existing_ids)} existing items in DynamoDB")
        return existing_ids
        
    except Exception as e:
        logger.warning(f"Error scanning DynamoDB for existing items: {e}")
        logger.warning("Continuing without resume capability")
        return set()


def batch_write_items(
    dynamodb_table,
    items: List[Dict],
    dry_run: bool = False
) -> int:
    """
    Write items to DynamoDB in batches.
    
    Uses batch_writer for efficient batch operations (25 items per batch).
    
    Args:
        dynamodb_table: DynamoDB table resource
        items: List of items to write
        dry_run: If True, don't actually write to DynamoDB
    
    Returns:
        Number of items written
    """
    if dry_run:
        logger.info(f"[DRY RUN] Would write {len(items)} items to DynamoDB")
        return len(items)
    
    try:
        with dynamodb_table.batch_writer() as batch:
            for item in items:
                batch.put_item(Item=item)
        
        return len(items)
        
    except Exception as e:
        logger.error(f"Error batch writing items: {e}")
        raise


def migrate_stac_items(
    opensearch_host: str,
    opensearch_index: str,
    dynamodb_table_name: str,
    region: str,
    dry_run: bool = False,
    resume: bool = False,
    batch_size: int = 25,
    use_opensearch_auth: bool = True
) -> Dict:
    """
    Main migration function.
    
    Migrates all STAC items from OpenSearch to DynamoDB with progress
    logging, error tracking, and resume capability.
    
    Args:
        opensearch_host: OpenSearch endpoint
        opensearch_index: OpenSearch index name
        dynamodb_table_name: DynamoDB table name
        region: AWS region
        dry_run: If True, don't write to DynamoDB
        resume: If True, skip items already in DynamoDB
        batch_size: Number of items per batch write
        use_opensearch_auth: Whether to use AWS auth for OpenSearch
    
    Returns:
        Migration report dictionary
    """
    logger.info("=" * 80)
    logger.info("STAC Migration: OpenSearch → DynamoDB")
    logger.info("=" * 80)
    logger.info(f"OpenSearch: {opensearch_host}/{opensearch_index}")
    logger.info(f"DynamoDB: {dynamodb_table_name}")
    logger.info(f"Region: {region}")
    logger.info(f"Dry Run: {dry_run}")
    logger.info(f"Resume: {resume}")
    logger.info(f"Batch Size: {batch_size}")
    logger.info("=" * 80)
    
    # Initialize clients
    os_client = get_opensearch_client(opensearch_host, region, use_opensearch_auth)
    
    # Create boto3 session with profile
    session = boto3.Session(profile_name=os.environ.get('AWS_PROFILE', 'DEVcloud'))
    dynamodb = session.resource('dynamodb', region_name=region)
    table = dynamodb.Table(dynamodb_table_name)
    
    # Initialize statistics
    stats = MigrationStats()
    
    # Get existing items for resume capability
    existing_ids = set()
    if resume:
        existing_ids = get_existing_item_ids(table)
    
    # Migrate items
    batch = []
    
    try:
        for item in scroll_opensearch_items(os_client, opensearch_index):
            stats.add_read()
            
            try:
                item_id = item.get('id')
                
                # Skip if already migrated (resume mode)
                if resume and item_id in existing_ids:
                    stats.add_skipped()
                    if stats.total_skipped % 100 == 0:
                        logger.info(f"Skipped {stats.total_skipped} already-migrated items")
                    continue
                
                # Transform item
                transformed = transform_item(item)
                batch.append(transformed)
                
                # Write batch when full
                if len(batch) >= batch_size:
                    written = batch_write_items(table, batch, dry_run)
                    stats.add_written(written)
                    
                    logger.info(
                        f"Progress: Read={stats.total_read}, "
                        f"Written={stats.total_written}, "
                        f"Skipped={stats.total_skipped}, "
                        f"Errors={stats.total_errors}"
                    )
                    
                    batch = []
                
            except Exception as e:
                error_msg = str(e)
                logger.error(f"Failed to migrate item {item.get('id')}: {error_msg}")
                stats.add_error(item.get('id', 'unknown'), error_msg)
                # Continue processing remaining items
        
        # Write remaining items
        if batch:
            written = batch_write_items(table, batch, dry_run)
            stats.add_written(written)
            logger.info(f"Wrote final batch of {written} items")
        
        # Generate report
        report = stats.get_report()
        
        logger.info("=" * 80)
        logger.info("MIGRATION COMPLETE")
        logger.info("=" * 80)
        logger.info(f"Total items read: {report['summary']['total_read']}")
        logger.info(f"Total items written: {report['summary']['total_written']}")
        logger.info(f"Total items skipped: {report['summary']['total_skipped']}")
        logger.info(f"Total errors: {report['summary']['total_errors']}")
        logger.info(f"Duration: {report['summary']['duration_seconds']:.2f} seconds")
        logger.info(f"Rate: {report['summary']['items_per_second']:.2f} items/second")
        logger.info("=" * 80)
        
        if report['errors']:
            logger.warning(f"Encountered {len(report['errors'])} errors during migration")
            logger.warning("See migration log file for error details")
        
        # Save report to file
        report_filename = f"migration_report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        with open(report_filename, 'w') as f:
            json.dump(report, f, indent=2)
        logger.info(f"Migration report saved to: {report_filename}")
        
        return report
        
    except Exception as e:
        logger.error(f"Migration failed: {e}")
        raise


def main():
    """Main entry point with argument parsing"""
    parser = argparse.ArgumentParser(
        description='Migrate STAC items from OpenSearch to DynamoDB',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Dry run to validate migration
  python migrate_stac_to_dynamodb.py --dry-run
  
  # Full migration with custom settings
  python migrate_stac_to_dynamodb.py \\
    --opensearch-host search-domain.region.es.amazonaws.com \\
    --dynamodb-table my-stac-items
  
  # Resume interrupted migration
  python migrate_stac_to_dynamodb.py --resume
  
  # Use environment variables
  export OPENSEARCH_HOST=search-domain.region.es.amazonaws.com
  export DYNAMODB_STAC_TABLE=my-stac-items
  python migrate_stac_to_dynamodb.py
        """
    )
    
    # OpenSearch configuration
    parser.add_argument(
        '--opensearch-host',
        type=str,
        default=os.environ.get('OPENSEARCH_HOST', ''),
        help='OpenSearch endpoint (without https://). Can also use OPENSEARCH_HOST env var.'
    )
    parser.add_argument(
        '--opensearch-index',
        type=str,
        default=os.environ.get('OPENSEARCH_INDEX', 'stac'),
        help='OpenSearch index name. Default: stac'
    )
    parser.add_argument(
        '--no-opensearch-auth',
        action='store_true',
        help='Disable AWS authentication for OpenSearch (for testing with local OpenSearch)'
    )
    
    # DynamoDB configuration
    parser.add_argument(
        '--dynamodb-table',
        type=str,
        default=os.environ.get('DYNAMODB_STAC_TABLE', ''),
        help='DynamoDB table name. Can also use DYNAMODB_STAC_TABLE env var.'
    )
    
    # AWS configuration
    parser.add_argument(
        '--region',
        type=str,
        default=os.environ.get('AWS_REGION', 'ap-southeast-2'),
        help='AWS region. Default: ap-southeast-2'
    )
    parser.add_argument(
        '--profile',
        type=str,
        default=os.environ.get('AWS_PROFILE', 'DEVcloud'),
        help='AWS profile to use. Default: DEVcloud'
    )
    
    # Migration options
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Validate migration without writing to DynamoDB'
    )
    parser.add_argument(
        '--resume',
        action='store_true',
        help='Skip items already in DynamoDB (for resuming interrupted migrations)'
    )
    parser.add_argument(
        '--batch-size',
        type=int,
        default=25,
        help='Number of items per batch write. Default: 25 (DynamoDB limit)'
    )
    
    args = parser.parse_args()
    
    # Validate required arguments
    if not args.opensearch_host:
        parser.error("--opensearch-host is required (or set OPENSEARCH_HOST env var)")
    if not args.dynamodb_table:
        parser.error("--dynamodb-table is required (or set DYNAMODB_STAC_TABLE env var)")
    
    # Run migration
    try:
        report = migrate_stac_items(
            opensearch_host=args.opensearch_host,
            opensearch_index=args.opensearch_index,
            dynamodb_table_name=args.dynamodb_table,
            region=args.region,
            dry_run=args.dry_run,
            resume=args.resume,
            batch_size=args.batch_size,
            use_opensearch_auth=not args.no_opensearch_auth
        )
        
        # Exit with error code if there were errors
        if report['summary']['total_errors'] > 0:
            logger.warning(f"Migration completed with {report['summary']['total_errors']} errors")
            sys.exit(1)
        else:
            logger.info("Migration completed successfully!")
            sys.exit(0)
            
    except Exception as e:
        logger.error(f"Migration failed: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()
