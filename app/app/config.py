from pydantic import BaseSettings, AnyHttpUrl
from typing import Optional

class Settings(BaseSettings):
    # AWS Configuration
    AWS_REGION: str = "ap-southeast-2"
    
    # S3 Configuration - required for data access
    S3_ZARR_PREFIX: str = ""
    S3_COG_PREFIX: str = ""
    
    # OpenSearch Configuration - required for STAC catalog
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

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"

settings = Settings()