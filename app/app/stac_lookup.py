from opensearchpy import OpenSearch, RequestsHttpConnection
from .config import settings
from tenacity import retry, stop_after_attempt, wait_exponential
import logging

logger = logging.getLogger(__name__)

@retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=0.5))
def make_client():
    host = settings.OPENSEARCH_HOST
    return OpenSearch(
        hosts=[{"host": host, "port": 443}],
        use_ssl=True,
        verify_certs=True,
        connection_class=RequestsHttpConnection,
        http_auth=None
    )

client = make_client()

def stac_search_point(variable: str, lon: float, lat: float, start: str, end: str, size: int = 100):
    body = {
      "query": {
        "bool": {
          "must": [
            {"term": {"properties.variable.keyword": variable}},
            {"range": {"properties.start_datetime": {"lte": end}}},
            {"range": {"properties.end_datetime": {"gte": start}}},
            {"geo_distance": {"distance": "1km", "geometry": {"lat": lat, "lon": lon}}}
          ]
        }
      },
      "size": size
    }
    res = client.search(index=settings.OPENSEARCH_INDEX, body=body)
    return res.get("hits", {}).get("hits", [])