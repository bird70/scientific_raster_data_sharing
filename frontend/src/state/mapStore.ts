import { create } from 'zustand'
import type { LatLng, MapLayer } from '@/types'

interface MapState {
  layers: MapLayer[]
  hoverValue?: { value?: number | null; lat?: number; lng?: number }
  selectedPoint: LatLng | null
  addLayer: (layer: MapLayer) => void
  removeLayer: (id: string) => void
  setOpacity: (id: string, opacity: number) => void
  toggleVisibility: (id: string) => void
  setVariable: (id: string, variable?: string) => void
  setHoverValue: (info?: { value?: number | null; lat?: number; lng?: number }) => void
  setSelectedPoint: (point: LatLng | null) => void
  clearLayers: () => void
}

export const useMapStore = create<MapState>((set) => ({
  layers: [],
  hoverValue: undefined,
  selectedPoint: null,
  addLayer: (layer) => set((state) => ({ layers: [...state.layers.filter((l) => l.id !== layer.id), layer] })),
  removeLayer: (id) => set((state) => ({ layers: state.layers.filter((l) => l.id !== id) })),
  setOpacity: (id, opacity) => set((state) => ({
    layers: state.layers.map((l) => (l.id === id ? { ...l, opacity } : l)),
  })),
  toggleVisibility: (id) => set((state) => ({
    layers: state.layers.map((l) => (l.id === id ? { ...l, visible: !l.visible } : l)),
  })),
  setVariable: (id, variable) => set((state) => ({
    layers: state.layers.map((l) => (l.id === id ? { ...l, variable } : l)),
  })),
  setHoverValue: (info) => set({ hoverValue: info }),
  setSelectedPoint: (point) => set({ selectedPoint: point }),
  clearLayers: () => set({ layers: [] }),
}))
