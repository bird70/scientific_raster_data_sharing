/**
 * MapLibre GL JS implementation of MapAdapter
 */

import maplibregl from 'maplibre-gl';
import type { MapAdapter, RasterLayerOptions, MarkerOptions, PolygonOptions } from './MapAdapter';

export class MapLibreAdapter implements MapAdapter {
  private map: maplibregl.Map;
  private markers: Map<string, maplibregl.Marker> = new Map();

  constructor(map: maplibregl.Map) {
    this.map = map;
  }

  // Core map operations
  setCenter(lat: number, lng: number, zoom: number): void {
    this.map.setCenter([lng, lat]);
    this.map.setZoom(zoom);
  }

  getCenter(): { lat: number; lng: number; zoom: number } {
    const center = this.map.getCenter();
    return {
      lat: center.lat,
      lng: center.lng,
      zoom: this.map.getZoom(),
    };
  }

  fitBounds(bounds: [[number, number], [number, number]]): void {
    // Convert [[lat, lng], [lat, lng]] to [[lng, lat], [lng, lat]] for MapLibre
    this.map.fitBounds([
      [bounds[0][1], bounds[0][0]],
      [bounds[1][1], bounds[1][0]],
    ], {
      padding: 50,
    });
  }

  // Layer management
  addRasterLayer(id: string, url: string, options: RasterLayerOptions = {}): void {
    // Remove existing layer if present
    if (this.map.getLayer(id)) {
      this.map.removeLayer(id);
    }
    if (this.map.getSource(id)) {
      this.map.removeSource(id);
    }

    // Add raster source
    this.map.addSource(id, {
      type: 'raster',
      tiles: [url],
      tileSize: 256,
      minzoom: options.minzoom || 0,
      maxzoom: options.maxzoom || 22,
    });

    // Add raster layer
    this.map.addLayer({
      id: id,
      type: 'raster',
      source: id,
      paint: {
        'raster-opacity': options.opacity !== undefined ? options.opacity : 1.0,
      },
    });
  }

  updateLayerOpacity(id: string, opacity: number): void {
    if (this.map.getLayer(id)) {
      this.map.setPaintProperty(id, 'raster-opacity', opacity);
    }
  }

  removeLayer(id: string): void {
    if (this.map.getLayer(id)) {
      this.map.removeLayer(id);
    }
    if (this.map.getSource(id)) {
      this.map.removeSource(id);
    }
  }

  // Markers and shapes
  addMarker(id: string, lat: number, lng: number, options: MarkerOptions = {}): void {
    // Remove existing marker if present
    this.removeMarker(id);

    const marker = new maplibregl.Marker({
      color: options.color || '#3b82f6',
      draggable: options.draggable || false,
    })
      .setLngLat([lng, lat])
      .addTo(this.map);

    this.markers.set(id, marker);
  }

  removeMarker(id: string): void {
    const marker = this.markers.get(id);
    if (marker) {
      marker.remove();
      this.markers.delete(id);
    }
  }

  addPolygon(id: string, coordinates: number[][][], options: PolygonOptions = {}): void {
    // Remove existing polygon if present
    this.removePolygon(id);

    // Add polygon source
    this.map.addSource(id, {
      type: 'geojson',
      data: {
        type: 'Feature',
        properties: {},
        geometry: {
          type: 'Polygon',
          coordinates: coordinates,
        },
      },
    });

    // Add fill layer
    this.map.addLayer({
      id: `${id}-fill`,
      type: 'fill',
      source: id,
      paint: {
        'fill-color': options.fillColor || '#3b82f6',
        'fill-opacity': options.fillOpacity !== undefined ? options.fillOpacity : 0.3,
      },
    });

    // Add outline layer
    this.map.addLayer({
      id: `${id}-outline`,
      type: 'line',
      source: id,
      paint: {
        'line-color': options.strokeColor || '#1e40af',
        'line-width': options.strokeWidth || 2,
      },
    });
  }

  removePolygon(id: string): void {
    if (this.map.getLayer(`${id}-fill`)) {
      this.map.removeLayer(`${id}-fill`);
    }
    if (this.map.getLayer(`${id}-outline`)) {
      this.map.removeLayer(`${id}-outline`);
    }
    if (this.map.getSource(id)) {
      this.map.removeSource(id);
    }
  }

  // Event handlers
  onMapClick(callback: (lat: number, lng: number) => void): () => void {
    const handler = (e: maplibregl.MapMouseEvent) => {
      callback(e.lngLat.lat, e.lngLat.lng);
    };
    this.map.on('click', handler);
    
    // Return cleanup function
    return () => {
      this.map.off('click', handler);
    };
  }

  onMapMove(callback: () => void): () => void {
    this.map.on('move', callback);
    
    // Return cleanup function
    return () => {
      this.map.off('move', callback);
    };
  }

  // Drawing tools (placeholder - would integrate with @mapbox/mapbox-gl-draw)
  enableDrawing(mode: 'polygon' | 'point'): void {
    console.log(`Drawing mode ${mode} enabled (to be implemented with mapbox-gl-draw)`);
  }

  disableDrawing(): void {
    console.log('Drawing disabled');
  }

  onDrawComplete(callback: (geometry: unknown) => void): () => void {
    console.log('Draw complete handler registered');
    // Placeholder to demonstrate callback usage until drawing is wired
    void callback;
    return () => {
      console.log('Draw complete handler removed');
    };
  }

  // Utility
  resize(): void {
    this.map.resize();
  }

  remove(): void {
    // Clean up all markers
    this.markers.forEach((marker) => marker.remove());
    this.markers.clear();
    
    // Remove map
    this.map.remove();
  }
}
