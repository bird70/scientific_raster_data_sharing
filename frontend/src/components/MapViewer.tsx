/**
 * Map viewer component using MapLibre GL JS
 */

import { useEffect, useRef, useState } from 'react';
import maplibregl, { type StyleSpecification } from 'maplibre-gl';
import 'maplibre-gl/dist/maplibre-gl.css';
import { MapLibreAdapter } from '../utils/map/MapLibreAdapter';
import { TimeStepIndicator } from './TimeStepIndicator';
import type { MapAdapter } from '../utils/map/MapAdapter';
import type { Dataset, LatLng } from '../types';
import { usePreferencesStore } from '../store/preferences';
import type { BaseMapStyle, ColorScheme } from '../store/preferences';

interface MapViewerProps {
  dataset: Dataset | null;
  onPointClick?: (point: LatLng) => void;
  selectedPoint?: LatLng | null;
  currentTimeStep?: number;
  timeSteps?: string[];
}

const baseStyles: Record<BaseMapStyle, StyleSpecification> = {
  osm: {
    version: 8,
    sources: {
      osm: {
        type: 'raster',
        tiles: [
          'https://a.tile.openstreetmap.org/{z}/{x}/{y}.png',
          'https://b.tile.openstreetmap.org/{z}/{x}/{y}.png',
          'https://c.tile.openstreetmap.org/{z}/{x}/{y}.png',
        ],
        tileSize: 256,
        attribution: '© OpenStreetMap contributors',
      },
    },
    layers: [
      {
        id: 'osm',
        type: 'raster',
        source: 'osm',
        minzoom: 0,
        maxzoom: 19,
      },
    ],
  },
  satellite: {
    version: 8,
    sources: {
      satellite: {
        type: 'raster',
        tiles: [
          'https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
        ],
        tileSize: 256,
        attribution: '© Esri, Maxar, Earthstar Geographics',
      },
    },
    layers: [
      {
        id: 'satellite',
        type: 'raster',
        source: 'satellite',
        minzoom: 0,
        maxzoom: 19,
      },
    ],
  },
};

const getBaseStyle = (baseMap: BaseMapStyle) => baseStyles[baseMap];

export function MapViewer({
  dataset,
  onPointClick,
  selectedPoint,
  currentTimeStep = 0,
  timeSteps = [],
}: MapViewerProps) {
  const mapContainer = useRef<HTMLDivElement>(null);
  const map = useRef<maplibregl.Map | null>(null);
  const adapter = useRef<MapAdapter | null>(null);
  const [isLoaded, setIsLoaded] = useState(false);
  const { baseMap, setBaseMap, colorScheme, setColorScheme } = usePreferencesStore();
  const initialStyle = useRef<StyleSpecification>(getBaseStyle(baseMap));

  // Initialize map
  useEffect(() => {
    if (!mapContainer.current || map.current) return;

    // Create map instance
    map.current = new maplibregl.Map({
      container: mapContainer.current,
      style: initialStyle.current,
      center: [174, -41], // New Zealand
      zoom: 5,
    });

    // Add navigation controls
    map.current.addControl(new maplibregl.NavigationControl(), 'top-right');

    // Add scale control
    map.current.addControl(new maplibregl.ScaleControl(), 'bottom-left');

    // Create adapter
    adapter.current = new MapLibreAdapter(map.current);

    // Set loaded state
    map.current.on('load', () => {
      setIsLoaded(true);
    });

    // Cleanup
    return () => {
      if (adapter.current) {
        adapter.current.remove();
        adapter.current = null;
      }
      map.current = null;
    };
  }, []);

  // Handle base map preference changes
  useEffect(() => {
    if (!map.current) return;
    map.current.setStyle(getBaseStyle(baseMap));
    map.current.once('styledata', () => {
      setIsLoaded(true);
    });
  }, [baseMap]);

  // Handle map clicks
  useEffect(() => {
    if (!adapter.current || !onPointClick) return;

    const cleanup = adapter.current.onMapClick((lat: number, lng: number) => {
      onPointClick({ lat, lng });
    });

    return cleanup;
  }, [onPointClick]);

  // Handle selected point marker
  useEffect(() => {
    if (!adapter.current || !isLoaded) return;

    if (selectedPoint) {
      adapter.current.addMarker('selected-point', selectedPoint.lat, selectedPoint.lng, {
        color: '#ef4444',
      });
    } else {
      adapter.current.removeMarker('selected-point');
    }
  }, [selectedPoint, isLoaded]);

  // Handle dataset visualization
  useEffect(() => {
    if (!adapter.current || !isLoaded || !dataset) return;

    // Fit map to dataset bounds
    if (dataset.spatial && dataset.spatial.bbox) {
      const bbox = dataset.spatial.bbox;
      // bbox format: [minx, miny, maxx, maxy]
      // Convert to [[lat, lng], [lat, lng]]
      adapter.current.fitBounds([
        [bbox[1], bbox[0]], // [miny, minx]
        [bbox[3], bbox[2]], // [maxy, maxx]
      ]);
    }

    // Add raster tile layer if COG is available
    if (dataset.assets && dataset.assets.cog) {
      // Generate tile URL template
      // Format: /tiles/{collection}/{z}/{x}/{y}.png
      const baseUrl = ((import.meta as ImportMeta & { env: { VITE_API_BASE_URL?: string } }).env.VITE_API_BASE_URL || 'http://localhost:8000').replace(/\/$/, '');
      const tileUrl = `${baseUrl}/tiles/${dataset.collection}/{z}/{x}/{y}.png`;
      
      adapter.current.addRasterLayer('dataset-tiles', tileUrl, {
        opacity: 0.7,
        minzoom: 0,
        maxzoom: 18,
      });
    }

    // Cleanup when dataset changes
    return () => {
      if (adapter.current) {
        adapter.current.removeLayer('dataset-tiles');
      }
    };
  }, [dataset, isLoaded]);

  // Handle window resize
  useEffect(() => {
    if (!adapter.current) return;

    const handleResize = () => {
      adapter.current?.resize();
    };

    window.addEventListener('resize', handleResize);
    return () => window.removeEventListener('resize', handleResize);
  }, []);

  return (
    <div style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 }}>
      <div ref={mapContainer} style={{ width: '100%', height: '100%' }} />
      
      {/* Loading indicator */}
      {!isLoaded && (
        <div className="absolute inset-0 flex items-center justify-center bg-gray-100">
          <div className="text-center">
            <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600 mx-auto mb-4"></div>
            <p className="text-sm text-gray-600">Loading map...</p>
          </div>
        </div>
      )}

      {/* Dataset info overlay with better contrast */}
      {dataset && isLoaded && (
        <div className="absolute top-4 left-4 bg-white/95 backdrop-blur-sm rounded-lg shadow-xl border-2 border-blue-500 p-4 max-w-xs">
          <h3 className="text-base font-bold text-gray-900 mb-2">
            {dataset.title || dataset.id}
          </h3>
          <p className="text-sm text-gray-800 font-semibold bg-blue-50 px-2 py-1 rounded">{dataset.collection}</p>
          {dataset.variables && dataset.variables.length > 0 && (
            <div className="mt-2 flex flex-wrap gap-1">
              {dataset.variables.slice(0, 3).map((variable, index) => (
                <span
                  key={index}
                  className="inline-flex items-center px-2 py-1 rounded-md text-xs font-bold bg-gradient-to-r from-blue-500 to-indigo-500 text-white shadow-sm"
                >
                  {variable.name}
                </span>
              ))}
            </div>
          )}
        </div>
      )}

      {/* Preferences overlay */}
      <div className="absolute top-4 right-4 bg-white/95 backdrop-blur-sm rounded-lg shadow-lg border border-gray-200 p-3 w-56 space-y-2">
        <div className="space-y-1">
          <label className="text-xs font-semibold text-gray-700">Base map</label>
          <select
            value={baseMap}
            onChange={(e) => setBaseMap(e.target.value as BaseMapStyle)}
            className="w-full border border-gray-300 rounded-md px-2 py-1 text-sm"
          >
            <option value="osm">OpenStreetMap</option>
            <option value="satellite">Satellite imagery</option>
          </select>
        </div>
        <div className="space-y-1">
          <label className="text-xs font-semibold text-gray-700">Color scheme</label>
          <select
            value={colorScheme}
            onChange={(e) => setColorScheme(e.target.value as ColorScheme)}
            className="w-full border border-gray-300 rounded-md px-2 py-1 text-sm"
          >
            <option value="default">Default</option>
            <option value="high-contrast">High contrast</option>
          </select>
        </div>
      </div>

      {/* Time step indicator */}
      {isLoaded && timeSteps.length > 0 && (
        <TimeStepIndicator
          currentTime={timeSteps[currentTimeStep]}
          totalSteps={timeSteps.length}
          currentStep={currentTimeStep}
        />
      )}

      {/* Coordinates display on hover */}
      {isLoaded && (
        <div className="absolute bottom-4 right-4 bg-white/95 backdrop-blur-sm rounded-lg px-4 py-2 shadow-lg border-2 border-gray-300 text-sm font-bold text-gray-900">
          📍 Click on map to select point
        </div>
      )}
    </div>
  );
}
