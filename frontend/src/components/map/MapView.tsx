import { useEffect, useRef } from 'react'
import maplibregl from 'maplibre-gl'
import 'maplibre-gl/dist/maplibre-gl.css'
import { LayerControls } from './LayerControls'
import { LegendAndTooltip } from './LegendAndTooltip'
import { buildTileUrl } from '@/services/tiles'
import { useMapStore } from '@/state/mapStore'
import { ResponsiveLayout } from './ResponsiveLayout'

interface MapViewProps {
  legend?: {
    min?: number
    max?: number
    units?: string
    paletteName?: string
  }
}

export function MapView({ legend }: MapViewProps) {
  const mapContainer = useRef<HTMLDivElement | null>(null)
  const mapRef = useRef<maplibregl.Map | null>(null)
  const {
    layers,
    removeLayer,
    setOpacity,
    toggleVisibility,
    setVariable,
    hoverValue,
    setHoverValue,
    setSelectedPoint,
  } = useMapStore()

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
      setHoverValue({ lat: event.lngLat.lat, lng: event.lngLat.lng, value: undefined })
    })

    mapRef.current.on('click', (event) => {
      setSelectedPoint({ lat: event.lngLat.lat, lng: event.lngLat.lng })
    })

    return () => {
      mapRef.current?.remove()
      mapRef.current = null
    }
  }, [setHoverValue, setSelectedPoint])

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
    setOpacity(id, value)
  }

  const handleToggle = (id: string) => {
    toggleVisibility(id)
  }

  const handleRemove = (id: string) => {
    removeLayer(id)
    const map = mapRef.current
    if (map) {
      const layerId = `layer-${id}`
      const sourceId = `source-${id}`
      if (map.getLayer(layerId)) map.removeLayer(layerId)
      if (map.getSource(sourceId)) map.removeSource(sourceId)
    }
  }

  const handleVariableChange = (id: string, variable: string) => {
    setVariable(id, variable)
  }

  return (
    <ResponsiveLayout
      mapSlot={(
        <div className="h-full w-full relative">
          <div ref={mapContainer} className="map-frame" />
          <div className="absolute top-4 left-4 bg-white/90 backdrop-blur-sm border border-gray-200 rounded-md p-3 shadow-sm">
            <p className="text-sm font-semibold text-gray-900">Active layers: {layers.filter((l) => l.visible).length}</p>
          </div>
        </div>
      )}
      sidebar={(
        <div className="space-y-4">
          <LayerControls
            layers={layers}
            onOpacityChange={handleOpacityChange}
            onToggleVisibility={handleToggle}
            onRemove={handleRemove}
            onVariableChange={handleVariableChange}
          />
          <LegendAndTooltip legend={legend} hover={hoverValue} />
        </div>
      )}
    />
  )
}
