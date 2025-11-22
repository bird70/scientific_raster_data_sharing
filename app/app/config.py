from pydantic import BaseSettings, AnyHttpUrl

class Settings(BaseSettings):
    AWS_REGION: str = "ap-southeast-2"
    S3_ZARR_PREFIX: str
    S3_COG_PREFIX: str
    OPENSEARCH_HOST: str
    OPENSEARCH_INDEX: str = "stac"
    REDIS_URL: str
    COGNITO_JWKS_URL: str
    COGNITO_USERPOOL_AUD: str
    DASK_SCHEDULER: str | None = None
    LOG_LEVEL: str = "INFO"

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"

settings = Settings()