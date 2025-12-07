import { render, screen, fireEvent, act } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest'
import { MapView } from '@/components/map/MapView'
import { useMapStore } from '@/state/mapStore'
import type { MapLayer } from '@/types'

const addSource = vi.fn()
const addLayer = vi.fn((layer: { id: string }) => {
  existingLayers.add(layer.id)
})
const setPaintProperty = vi.fn()
const removeLayer = vi.fn((id: string) => {
  existingLayers.delete(id)
})
const removeSource = vi.fn()
const setLayoutProperty = vi.fn()
const getSource = vi.fn()
const existingLayers = new Set<string>()
const getLayer = vi.fn((id: string) => (existingLayers.has(id) ? {} : undefined))
const on = vi.fn()
const remove = vi.fn()
const getStyle = vi.fn(() => ({ layers: [{ id: 'osm' }, ...Array.from(existingLayers).map((id) => ({ id }))] }))

vi.mock('maplibre-gl', () => {
  return {
    default: {
      Map: vi.fn().mockImplementation(() => ({
        addSource,
        addLayer,
        setPaintProperty,
        setLayoutProperty,
        removeLayer,
        removeSource,
        getSource,
        getLayer,
        on,
        remove,
        getStyle,
      })),
    },
  }
})

describe('MapView', () => {
  const initialLayers: MapLayer[] = [
    { id: 'layer1', name: 'Layer 1', collection: 'c1', opacity: 0.7, visible: true },
    { id: 'layer2', name: 'Layer 2', collection: 'c2', opacity: 0.5, visible: true },
  ]

  beforeEach(() => {
    addSource.mockClear()
    addLayer.mockClear()
    setPaintProperty.mockClear()
    setLayoutProperty.mockClear()
    removeLayer.mockClear()
    removeSource.mockClear()
    existingLayers.clear()
    getSource.mockReturnValue(undefined)
    act(() => {
      useMapStore.setState({ layers: initialLayers, hoverValue: undefined, selectedPoint: null })
    })
  })

  afterEach(() => {
    act(() => {
      useMapStore.getState().clearLayers()
    })
    vi.clearAllMocks()
  })

  it('renders map view and legend', () => {
    render(<MapView legend={{ min: 1, max: 10, units: 'K' }} />)
    expect(screen.getByTestId('map-canvas')).toBeInTheDocument()
    expect(screen.getByTestId('legend-tooltip')).toBeInTheDocument()
    expect(screen.getByText(/Min/)).toBeInTheDocument()
    expect(screen.getByText(/10/)).toBeInTheDocument()
  })

  it('adds raster layers for visible layers', async () => {
    render(<MapView />)
    await vi.waitFor(() => {
      expect(addSource).toHaveBeenCalled()
      expect(addLayer).toHaveBeenCalled()
    })
  })

  it('updates opacity via controls', async () => {
    render(<MapView />)

    const sliders = await screen.findAllByLabelText(/Opacity/)
    await userEvent.click(sliders[0])
    const sliderEl = sliders[0] as HTMLInputElement
    fireEvent.change(sliderEl, { target: { value: '0.4' } })

    await vi.waitFor(() => expect(setPaintProperty).toHaveBeenCalled())
  })

  it('removes layer via control action', async () => {
    const user = userEvent.setup()
    render(<MapView />)

    const removeButton = await screen.findByLabelText(/Remove Layer 1/i)
    await user.click(removeButton)
    expect(removeLayer).toHaveBeenCalled()
  })

  it('toggles visibility', async () => {
    const user = userEvent.setup()
    render(<MapView />)

    const toggle = await screen.findByLabelText(/Toggle Layer 1/i)
    await user.click(toggle)
    expect(setLayoutProperty).toHaveBeenCalled()
  })
})
