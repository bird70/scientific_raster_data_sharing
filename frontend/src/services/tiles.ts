import { tileCache } from '../utils/tileCache';

const API_BASE = ((import.meta as ImportMeta & { env: { VITE_API_BASE_URL?: string } }).env.VITE_API_BASE_URL || 'http://localhost:8000').replace(/\/$/, '')

export function buildTileUrl(collection: string, asset?: string) {
  const cacheKey = `${collection}:${asset || 'default'}`;
  
  // Check cache first
  const cached = tileCache.get(cacheKey);
  if (cached) {
    return cached;
  }

  const assetQuery = asset ? `?asset=${encodeURIComponent(asset)}` : ''
  const url = `${API_BASE}/tiles/${collection}/{z}/{x}/{y}.png${assetQuery}`;
  
  // Cache the URL
  tileCache.set(cacheKey, url);
  
  return url;
}

export interface RasterLayerOptions {
  opacity?: number
  minzoom?: number
  maxzoom?: number
}

export function attachRasterLayer(
  map: {
    addSource: (id: string, source: unknown) => void
    addLayer: (layer: unknown) => void
    setPaintProperty: (layerId: string, prop: string, value: unknown) => void
    getSource: (id: string) => unknown
    getLayer: (id: string) => unknown
  },
  id: string,
  collection: string,
  asset?: string,
  options: RasterLayerOptions = {},
) {
  const sourceId = `source-${id}`
  const layerId = `layer-${id}`
  const tileUrl = buildTileUrl(collection, asset)

  if (!map.getSource(sourceId)) {
    map.addSource(sourceId, {
      type: 'raster',
      tiles: [tileUrl],
      tileSize: 256,
      minzoom: options.minzoom ?? 0,
      maxzoom: options.maxzoom ?? 22,
    })
  }

  if (!map.getLayer(layerId)) {
    map.addLayer({
      id: layerId,
      type: 'raster',
      source: sourceId,
      paint: {
        'raster-opacity': options.opacity ?? 1,
      },
    })
  } else if (options.opacity != null) {
    map.setPaintProperty(layerId, 'raster-opacity', options.opacity)
  }
}
