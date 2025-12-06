from pydantic_settings import BaseSettings
from typing import Optional

class Settings(BaseSettings):
    # AWS Configuration
    AWS_REGION: str = "ap-southeast-2"
    
    # S3 Configuration - required for data access
    S3_ZARR_PREFIX: str = ""
    S3_COG_PREFIX: str = ""
    
    # STAC Backend Configuration
    # Supported values: "dynamodb", "opensearch", "dual"
    STAC_BACKEND: str = "dynamodb"
    
    # DynamoDB Configuration - required when STAC_BACKEND is "dynamodb" or "dual"
    DYNAMODB_STAC_TABLE: str = ""
    
    # OpenSearch Configuration - required when STAC_BACKEND is "opensearch" or "dual"
    OPENSEARCH_HOST: str = ""
    OPENSEARCH_INDEX: str = "stac"
    
    # Redis Configuration - required for caching
    REDIS_URL: str = "redis://localhost:6379"
    
    # Cognito Configuration - required for authentication
    COGNITO_JWKS_URL: str = ""
    COGNITO_USERPOOL_AUD: str = ""
    
    # Dask Configuration - optional for distributed processing
    DASK_SCHEDULER: Optional[str] = None
    
    # Logging Configuration
    LOG_LEVEL: str = "INFO"
    
    # Frontend Configuration - optional for CORS
    CLOUDFRONT_DOMAIN: Optional[str] = None
    CUSTOM_DOMAIN: Optional[str] = None

    model_config = {
        "env_file": ".env",
        "env_file_encoding": "utf-8"
    }

settings = Settings()