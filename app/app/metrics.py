from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST
from fastapi import Response, APIRouter

router = APIRouter()
REQUEST_COUNT = Counter("raster_http_requests_total", "Total HTTP requests", ["method", "endpoint", "status"])
REQUEST_LATENCY = Histogram("raster_request_latency_seconds", "Request latency", ["endpoint"])
UPTIME = Gauge("raster_uptime_seconds", "Service uptime seconds")

@router.get("/metrics")
def metrics():
    data = generate_latest()
    return Response(content=data, media_type=CONTENT_TYPE_LATEST)