# Redis Optimization Guide

## Current Configuration

The platform uses ElastiCache Redis for caching tile data and API responses. Current settings in `terraform.tfvars`:

```hcl
redis_node_type = "cache.t4g.micro" # Graviton ARM, ~$12/month
```

## Cost Optimization Strategies

### 1. Instance Type Selection

**Recommended: cache.t4g.micro (Graviton2)**
- Cost: ~$12/month
- Memory: 555 MB
- Network: Up to 5 Gbps
- Best price/performance ratio for development

**Alternative Options:**
- `cache.t3.micro`: ~$15/month (x86)
- `cache.t4g.small`: ~$24/month (1.37 GB memory)

### 2. Memory Management

**Cache Eviction Policy:**
```python
# In app/cache.py
REDIS_MAXMEMORY_POLICY = "allkeys-lru"  # Evict least recently used keys
```

**TTL Settings:**
```python
# Tile cache: 1 hour
TILE_CACHE_TTL = 3600

# STAC metadata: 24 hours  
STAC_CACHE_TTL = 86400

# Timeseries data: 30 minutes
TIMESERIES_CACHE_TTL = 1800
```

### 3. Monitoring and Alerts

**Key Metrics to Monitor:**
- Memory utilization (target: <80%)
- Cache hit ratio (target: >70%)
- Evictions per second
- Connection count

**CloudWatch Alarms:**
```hcl
# In terraform/modules/data/redis.tf
resource "aws_cloudwatch_metric_alarm" "redis_memory" {
  alarm_name          = "${var.project_name}-redis-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseMemoryUsagePercentage"
  namespace           = "AWS/ElastiCache"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "Redis memory usage is high"
}
```

### 4. Cache Strategy Implementation

**Hierarchical Caching:**
```python
# Priority order for cache allocation
1. Frequently accessed tiles (zoom levels 8-12)
2. STAC catalog responses
3. Timeseries aggregations
4. Authentication tokens
```

**Cache Warming:**
```python
# Pre-populate cache with common tile requests
async def warm_cache():
    common_tiles = get_popular_tile_coordinates()
    for tile in common_tiles:
        await cache_tile_data(tile)
```

## Performance Tuning

### Connection Pooling
```python
# app/cache.py
REDIS_CONNECTION_POOL_SIZE = 10
REDIS_CONNECTION_TIMEOUT = 5
```

### Compression
```python
# Enable compression for large objects
import gzip
import json

def cache_compressed(key, data, ttl=3600):
    compressed = gzip.compress(json.dumps(data).encode())
    redis_client.setex(key, ttl, compressed)
```

## Scaling Considerations

### When to Scale Up
- Memory utilization consistently >80%
- Cache hit ratio drops below 60%
- Frequent evictions impacting performance

### Scaling Options
1. **Vertical scaling**: Upgrade to `cache.t4g.small` (+$12/month)
2. **Horizontal scaling**: Add read replicas (not recommended for dev)
3. **Cluster mode**: For production workloads only

## Cost Monitoring

### Monthly Cost Breakdown
```
cache.t4g.micro: $12.41/month
Data transfer: ~$1-2/month
Total: ~$14/month
```

### Cost Alerts
```hcl
resource "aws_budgets_budget" "redis_budget" {
  name         = "${var.project_name}-redis-budget"
  budget_type  = "COST"
  limit_amount = "20"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
}
```

## Troubleshooting

### High Memory Usage
1. Check eviction policy: `CONFIG GET maxmemory-policy`
2. Analyze key patterns: `MEMORY USAGE <key>`
3. Review TTL settings: `TTL <key>`

### Low Cache Hit Ratio
1. Increase memory allocation
2. Optimize cache keys structure
3. Review eviction patterns

### Connection Issues
1. Check security group rules
2. Verify subnet configuration
3. Monitor connection pool metrics

## Best Practices

1. **Use appropriate TTL values** based on data freshness requirements
2. **Monitor cache hit ratios** and adjust strategy accordingly
3. **Implement circuit breakers** for cache failures
4. **Use compression** for large cached objects
5. **Set up proper monitoring** and alerting
6. **Regular cache analysis** to optimize key patterns

## Implementation Checklist

- [ ] Configure eviction policy
- [ ] Set up CloudWatch monitoring
- [ ] Implement cache warming for critical data
- [ ] Add compression for large objects
- [ ] Configure connection pooling
- [ ] Set up cost alerts
- [ ] Test failover scenarios
- [ ] Document cache key patterns