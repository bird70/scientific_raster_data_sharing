import redis.asyncio as aioredis
import json
from .config import settings

_redis = None

async def get_redis():
    global _redis
    if _redis is None:
        _redis = aioredis.from_url(settings.REDIS_URL, encoding="utf-8", decode_responses=True)
    return _redis

async def get_cached(key: str):
    r = await get_redis()
    v = await r.get(key)
    return json.loads(v) if v else None

async def set_cached(key: str, value, ttl: int = 300):
    r = await get_redis()
    await r.set(key, json.dumps(value), ex=ttl)