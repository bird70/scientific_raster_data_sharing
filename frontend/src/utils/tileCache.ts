/**
 * Tile caching utility for MapLibre GL JS
 * Implements in-memory caching with LRU eviction
 */

interface CacheEntry<T> {
  value: T;
  timestamp: number;
  accessCount: number;
}

export class TileCache<T = unknown> {
  private cache = new Map<string, CacheEntry<T>>();
  private maxSize: number;
  private ttl: number; // Time to live in milliseconds

  constructor(maxSize = 100, ttl = 5 * 60 * 1000) {
    // Default: 100 entries, 5 minutes TTL
    this.maxSize = maxSize;
    this.ttl = ttl;
  }

  get(key: string): T | undefined {
    const entry = this.cache.get(key);
    if (!entry) return undefined;

    // Check if expired
    if (Date.now() - entry.timestamp > this.ttl) {
      this.cache.delete(key);
      return undefined;
    }

    // Update access count for LRU
    entry.accessCount++;
    return entry.value;
  }

  set(key: string, value: T): void {
    // Evict if at capacity
    if (this.cache.size >= this.maxSize && !this.cache.has(key)) {
      this.evictLRU();
    }

    this.cache.set(key, {
      value,
      timestamp: Date.now(),
      accessCount: 1,
    });
  }

  has(key: string): boolean {
    const entry = this.cache.get(key);
    if (!entry) return false;

    // Check expiration
    if (Date.now() - entry.timestamp > this.ttl) {
      this.cache.delete(key);
      return false;
    }

    return true;
  }

  clear(): void {
    this.cache.clear();
  }

  size(): number {
    return this.cache.size;
  }

  private evictLRU(): void {
    let lruKey: string | undefined;
    let minAccessCount = Infinity;
    let oldestTimestamp = Infinity;

    // Find least recently used entry
    for (const [key, entry] of this.cache.entries()) {
      if (
        entry.accessCount < minAccessCount ||
        (entry.accessCount === minAccessCount && entry.timestamp < oldestTimestamp)
      ) {
        lruKey = key;
        minAccessCount = entry.accessCount;
        oldestTimestamp = entry.timestamp;
      }
    }

    if (lruKey) {
      this.cache.delete(lruKey);
    }
  }

  /**
   * Remove expired entries
   */
  prune(): void {
    const now = Date.now();
    for (const [key, entry] of this.cache.entries()) {
      if (now - entry.timestamp > this.ttl) {
        this.cache.delete(key);
      }
    }
  }
}

// Singleton instance for tile URL caching
export const tileCache = new TileCache<string>(200, 10 * 60 * 1000); // 200 tiles, 10 minutes

/**
 * Batch tile requests to reduce network overhead
 * Groups multiple tile requests into a single batch with configurable delay
 */
export class TileBatcher {
  private queue: Array<{ key: string; resolve: (url: string) => void }> = [];
  private batchDelay: number;
  private batchTimer: ReturnType<typeof setTimeout> | null = null;
  private fetchFn: (keys: string[]) => Promise<Map<string, string>>;

  constructor(fetchFn: (keys: string[]) => Promise<Map<string, string>>, batchDelay = 50) {
    this.fetchFn = fetchFn;
    this.batchDelay = batchDelay;
  }

  request(key: string): Promise<string> {
    return new Promise((resolve) => {
      // Check cache first
      if (tileCache.has(key)) {
        const cached = tileCache.get(key);
        if (cached) {
          resolve(cached);
          return;
        }
      }

      // Add to batch queue
      this.queue.push({ key, resolve });

      // Schedule batch processing
      if (!this.batchTimer) {
        this.batchTimer = setTimeout(() => this.processBatch(), this.batchDelay);
      }
    });
  }

  private async processBatch(): Promise<void> {
    if (this.queue.length === 0) return;

    const batch = [...this.queue];
    this.queue = [];
    this.batchTimer = null;

    const keys = batch.map((item) => item.key);

    try {
      const results = await this.fetchFn(keys);

      // Cache and resolve
      for (const { key, resolve } of batch) {
        const url = results.get(key);
        if (url) {
          tileCache.set(key, url);
          resolve(url);
        } else {
          // Fallback to individual key if batch didn't return it
          resolve(key);
        }
      }
    } catch (error) {
      console.error('[TileBatcher] Batch fetch failed:', error);
      // Resolve with original keys as fallback
      for (const { key, resolve } of batch) {
        resolve(key);
      }
    }
  }

  clear(): void {
    this.queue = [];
    if (this.batchTimer) {
      clearTimeout(this.batchTimer);
      this.batchTimer = null;
    }
  }
}
