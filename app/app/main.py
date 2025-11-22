from fastapi import FastAPI
from .tiles import router as tiles_router
from .timeseries import router as ts_router
from .metrics import router as metrics_router
from .auth import require_auth
import structlog
import logging

def configure_logging():
    logging.basicConfig(level=logging.INFO)
    structlog.configure(logger_factory=structlog.stdlib.LoggerFactory())

configure_logging()
app = FastAPI(title="Raster TimeSeries API", version="1.0.0")

app.include_router(tiles_router)
app.include_router(ts_router)
app.include_router(metrics_router)

@app.get("/health")
def health():
    return {"status": "ok"}