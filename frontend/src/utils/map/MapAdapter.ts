/**
 * MapAdapter interface for abstracting map library implementation
 * 
 * This pattern allows us to swap map libraries without rewriting components.
 * Currently implemented with MapLibre GL JS, but could be swapped for other libraries.
 */

export interface RasterLayerOptions {
  opacity?: number;
  minzoom?: number;
  maxzoom?: number;
}

export interface MarkerOptions {
  color?: string;
  draggable?: boolean;
}

export interface PolygonOptions {
  fillColor?: string;
  fillOpacity?: number;
  strokeColor?: string;
  strokeWidth?: number;
}

export interface MapAdapter {
  // Core map operations
  setCenter(lat: number, lng: number, zoom: number): void;
  getCenter(): { lat: number; lng: number; zoom: number };
  fitBounds(bounds: [[number, number], [number, number]]): void;
  
  // Layer management
  addRasterLayer(id: string, url: string, options?: RasterLayerOptions): void;
  updateLayerOpacity(id: string, opacity: number): void;
  removeLayer(id: string): void;
  
  // Markers and shapes
  addMarker(id: string, lat: number, lng: number, options?: MarkerOptions): void;
  removeMarker(id: string): void;
  addPolygon(id: string, coordinates: number[][][], options?: PolygonOptions): void;
  removePolygon(id: string): void;
  
  // Event handlers - return cleanup function
  onMapClick(callback: (lat: number, lng: number) => void): () => void;
  onMapMove(callback: () => void): () => void;
  
  // Drawing tools
  enableDrawing(mode: 'polygon' | 'point'): void;
  disableDrawing(): void;
  onDrawComplete(callback: (geometry: any) => void): () => void;
  
  // Utility
  resize(): void;
  remove(): void;
}
