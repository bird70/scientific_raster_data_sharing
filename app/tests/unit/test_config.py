import pytest
import os
from app.config import Settings


def test_config_defaults():
    """Test that configuration has sensible defaults"""
    # Create settings without environment variables
    settings = Settings(
        _env_file=None,
        S3_ZARR_PREFIX="s3://test-zarr/",
        S3_COG_PREFIX="s3://test-cog/",
        OPENSEARCH_HOST="test-opensearch.example.com",
        REDIS_URL="redis://test-redis:6379",
        COGNITO_JWKS_URL="https://cognito.example.com/.well-known/jwks.json",
        COGNITO_USERPOOL_AUD="test-client-id"
    )
    
    # Verify defaults
    assert settings.AWS_REGION == "ap-southeast-2"
    assert settings.OPENSEARCH_INDEX == "stac"
    assert settings.LOG_LEVEL == "INFO"
    assert settings.DASK_SCHEDULER is None


def test_config_optional_dask():
    """Test that DASK_SCHEDULER is optional"""
    settings = Settings(
        _env_file=None,
        S3_ZARR_PREFIX="s3://test-zarr/",
        S3_COG_PREFIX="s3://test-cog/",
        OPENSEARCH_HOST="test-opensearch.example.com",
        REDIS_URL="redis://test-redis:6379",
        COGNITO_JWKS_URL="https://cognito.example.com/.well-known/jwks.json",
        COGNITO_USERPOOL_AUD="test-client-id"
    )
    
    # DASK_SCHEDULER should be None by default
    assert settings.DASK_SCHEDULER is None


def test_config_with_dask():
    """Test that DASK_SCHEDULER can be configured"""
    settings = Settings(
        _env_file=None,
        S3_ZARR_PREFIX="s3://test-zarr/",
        S3_COG_PREFIX="s3://test-cog/",
        OPENSEARCH_HOST="test-opensearch.example.com",
        REDIS_URL="redis://test-redis:6379",
        COGNITO_JWKS_URL="https://cognito.example.com/.well-known/jwks.json",
        COGNITO_USERPOOL_AUD="test-client-id",
        DASK_SCHEDULER="tcp://dask-scheduler:8786"
    )
    
    assert settings.DASK_SCHEDULER == "tcp://dask-scheduler:8786"
