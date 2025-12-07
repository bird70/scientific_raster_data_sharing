import { useEffect, useMemo, useRef, useState } from 'react'
import maplibregl from 'maplibre-gl'
import 'maplibre-gl/dist/maplibre-gl.css'
import type { MapLayer } from '@/types'
import { LayerControls } from './LayerControls'
import { LegendAndTooltip } from './LegendAndTooltip'
import { buildTileUrl } from '@/services/tiles'

interface MapViewProps {
  initialLayers?: MapLayer[]
  legend?: {
    min?: number
    max?: number
    units?: string
    paletteName?: string
  }
}

export function MapView({ initialLayers = [], legend }: MapViewProps) {
  const mapContainer = useRef<HTMLDivElement | null>(null)
  const mapRef = useRef<maplibregl.Map | null>(null)
  const [layers, setLayers] = useState<MapLayer[]>(initialLayers)
  const [hoverInfo, setHoverInfo] = useState<{ value?: number; lat?: number; lng?: number }>({})

  // Initialize map
  useEffect(() => {
    if (!mapContainer.current || mapRef.current) return

    mapRef.current = new maplibregl.Map({
      container: mapContainer.current,
      style: {
        version: 8,
        sources: {
          osm: {
            type: 'raster',
            tiles: ['https://a.tile.openstreetmap.org/{z}/{x}/{y}.png'],
            tileSize: 256,
          },
        },
        layers: [
          {
            id: 'osm',
            type: 'raster',
            source: 'osm',
          },
        ],
      },
      center: [0, 0],
      zoom: 1,
    })

    mapRef.current.on('mousemove', (event) => {
      setHoverInfo({ lat: event.lngLat.lat, lng: event.lngLat.lng, value: undefined })
    })

    return () => {
      mapRef.current?.remove()
      mapRef.current = null
    }
  }, [])

  // Sync layers to maplibre
  useEffect(() => {
    if (!mapRef.current) return

    const map = mapRef.current
    const desiredLayerIds = new Set(layers.map((l) => `layer-${l.id}`))

    layers.forEach((layer) => {
      const sourceId = `source-${layer.id}`
      const layerId = `layer-${layer.id}`
      const tileUrl = buildTileUrl(layer.collection, layer.asset)

      if (!map.getSource(sourceId)) {
        map.addSource(sourceId, {
          type: 'raster',
          tiles: [tileUrl],
          tileSize: 256,
        })
      }

      if (!map.getLayer(layerId)) {
        map.addLayer({
          id: layerId,
          type: 'raster',
          source: sourceId,
          paint: { 'raster-opacity': layer.opacity },
          layout: { visibility: layer.visible ? 'visible' : 'none' },
        })
      } else {
        map.setPaintProperty(layerId, 'raster-opacity', layer.opacity)
        map.setLayoutProperty(layerId, 'visibility', layer.visible ? 'visible' : 'none')
      }
    })

    // Remove layers that are no longer present
    const existingLayerIds = map.getStyle()?.layers?.map((l) => l.id) || []
    existingLayerIds
      .filter((id) => id.startsWith('layer-') && !desiredLayerIds.has(id))
      .forEach((id) => {
        map.removeLayer(id)
        const sourceId = `source-${id.replace('layer-', '')}`
        if (map.getSource(sourceId)) {
          map.removeSource(sourceId)
        }
      })
  }, [layers])

  const handleOpacityChange = (id: string, value: number) => {
    setLayers((prev) => prev.map((l) => (l.id === id ? { ...l, opacity: value } : l)))
  }

  const handleToggle = (id: string) => {
    setLayers((prev) => prev.map((l) => (l.id === id ? { ...l, visible: !l.visible } : l)))
  }

  const handleRemove = (id: string) => {
    setLayers((prev) => prev.filter((l) => l.id !== id))
    const map = mapRef.current
    if (map) {
      const layerId = `layer-${id}`
      const sourceId = `source-${id}`
      if (map.getLayer(layerId)) map.removeLayer(layerId)
      if (map.getSource(sourceId)) map.removeSource(sourceId)
    }
  }

  const handleVariableChange = (id: string, variable: string) => {
    setLayers((prev) => prev.map((l) => (l.id === id ? { ...l, variable } : l)))
  }

  return (
    <div className="grid grid-cols-3 gap-4 h-full" data-testid="map-view">
      <div className="col-span-2 relative border border-gray-200 rounded-lg overflow-hidden shadow-sm">
        <div ref={mapContainer} className="w-full h-[600px]" />
        <div className="absolute top-4 left-4 bg-white/90 backdrop-blur-sm border border-gray-200 rounded-md p-3">
          <p className="text-sm font-semibold text-gray-900">Active layers: {layers.filter((l) => l.visible).length}</p>
        </div>
      </div>

      <div className="col-span-1 space-y-4">
        <LayerControls
          layers={layers}
          onOpacityChange={handleOpacityChange}
          onToggleVisibility={handleToggle}
          onRemove={handleRemove}
          onVariableChange={handleVariableChange}
        />
        <LegendAndTooltip legend={legend} hover={hoverInfo} />
      </div>
    </div>
  )
}
