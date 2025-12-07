import { render, screen, waitFor, act } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { vi, describe, it, beforeEach, afterEach, expect } from 'vitest'
import { TimeseriesController } from '@/components/timeseries/TimeseriesController'
import { useMapStore } from '@/state/mapStore'
import type { Dataset } from '@/types'
import * as timeseriesService from '@/services/timeseries'

vi.mock('react-plotly.js', () => ({
  default: () => <div data-testid="plotly-mock" />,
}))

const mockDataset: Dataset = {
  id: 'dataset-123',
  collection: 'collection-1',
  title: 'Sea Surface Temperature',
  description: 'Daily SST composites',
  temporal: {
    start: new Date('2024-01-01'),
    end: new Date('2024-12-31'),
    interval: 'P1D',
  },
  spatial: {
    bbox: [-180, -90, 180, 90],
    crs: 'EPSG:4326',
  },
  variables: [],
  assets: {
    cog: 's3://example/sst.tif',
    zarr: '',
  },
  properties: {},
}

describe('TimeseriesController', () => {
  const mockData = {
    times: ['2024-01-01T00:00:00Z', '2024-01-02T00:00:00Z'],
    values: [290.1, 289.5],
    metadata: {
      variable: 'temperature',
      units: 'K',
      long_name: 'Sea Surface Temperature',
      coordinates: { lat: -33, lng: 151 },
      temporal_extent: {
        start: '2024-01-01T00:00:00Z',
        end: '2024-12-31T23:59:59Z',
      },
    },
  }

  const originalCreate = global.URL.createObjectURL
  const originalRevoke = global.URL.revokeObjectURL

  beforeEach(() => {
    vi.spyOn(timeseriesService, 'fetchTimeseries').mockResolvedValue(mockData)
    global.URL.createObjectURL = vi.fn(() => 'blob:mock')
    global.URL.revokeObjectURL = vi.fn()
    act(() => {
      useMapStore.setState({ selectedPoint: { lat: -33.0, lng: 151.0 } })
    })
  })

  afterEach(() => {
    vi.restoreAllMocks()
    global.URL.createObjectURL = originalCreate
    global.URL.revokeObjectURL = originalRevoke
    act(() => {
      useMapStore.setState({ selectedPoint: null, layers: [] })
    })
  })

  it('fetches timeseries for map click and allows CSV export', async () => {
    render(<TimeseriesController dataset={mockDataset} variable="temperature" />)

    await waitFor(() => expect(timeseriesService.fetchTimeseries).toHaveBeenCalled())
    expect(timeseriesService.fetchTimeseries).toHaveBeenCalledWith({
      lon: 151.0,
      lat: -33.0,
      start: mockDataset.temporal.start.toISOString(),
      end: mockDataset.temporal.end.toISOString(),
      variables: ['temperature'],
      datasetIds: [mockDataset.id],
    })

    await waitFor(() => expect(screen.getByText(/Points:/i)).toBeInTheDocument())

    const csvButton = screen.getByLabelText(/Download timeseries as CSV/i)
    await userEvent.click(csvButton)
    expect(global.URL.createObjectURL).toHaveBeenCalled()
  })
})
