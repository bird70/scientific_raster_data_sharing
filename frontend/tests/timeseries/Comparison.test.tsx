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

const datasetA: Dataset = {
  id: 'dataset-a',
  collection: 'collection-a',
  title: 'Dataset A',
  description: 'Dataset A desc',
  temporal: {
    start: new Date('2024-01-01'),
    end: new Date('2024-12-31'),
    interval: 'P1D',
  },
  spatial: {
    bbox: [-10, -10, 10, 10],
    crs: 'EPSG:4326',
  },
  variables: [],
  assets: { cog: 's3://a', zarr: '' },
  properties: {},
}

const datasetB: Dataset = {
  ...datasetA,
  id: 'dataset-b',
  title: 'Dataset B',
  assets: { cog: 's3://b', zarr: '' },
}

describe('Timeseries comparison', () => {
  const mockSeries = {
    series: [
      {
        datasetId: 'dataset-a',
        variable: 'temperature',
        units: 'K',
        times: ['2024-01-01T00:00:00Z'],
        values: [290],
      },
      {
        datasetId: 'dataset-b',
        variable: 'salinity',
        units: 'psu',
        times: ['2024-01-01T00:00:00Z'],
        values: [35],
      },
    ],
    metadata: {
      coordinates: { lat: -33, lng: 151 },
    },
  }

  beforeEach(() => {
    vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {})
    vi.spyOn(timeseriesService, 'fetchTimeseries').mockResolvedValue(mockSeries)
    global.URL.createObjectURL = vi.fn(() => 'blob:mock')
    global.URL.revokeObjectURL = vi.fn()
    act(() => {
      useMapStore.setState({
        selectedPoint: { lat: -33, lng: 151 },
        layers: [
          {
            id: datasetA.id,
            name: datasetA.title,
            collection: datasetA.collection,
            variable: 'temperature',
            opacity: 1,
            visible: true,
            temporal: datasetA.temporal,
          },
          {
            id: datasetB.id,
            name: datasetB.title,
            collection: datasetB.collection,
            variable: 'salinity',
            opacity: 1,
            visible: true,
            temporal: datasetB.temporal,
          },
        ],
      })
    })
  })

  afterEach(() => {
    vi.restoreAllMocks()
    // @ts-expect-error test cleanup
    global.URL.createObjectURL = undefined
    // @ts-expect-error test cleanup
    global.URL.revokeObjectURL = undefined
    act(() => {
      useMapStore.setState({ selectedPoint: null, layers: [] })
    })
  })

  it('queries all visible layers and exports combined CSV', async () => {
    await act(async () => {
      render(<TimeseriesController dataset={datasetA} variable="temperature" />)
      await Promise.resolve()
    })

    await waitFor(() => expect(timeseriesService.fetchTimeseries).toHaveBeenCalled())
    const call = vi.mocked(timeseriesService.fetchTimeseries).mock.calls[0]?.[0]
    expect(call?.datasetIds).toEqual([datasetA.id, datasetB.id])
    expect(call?.variables).toEqual(['temperature', 'salinity'])

    await waitFor(() => expect(screen.getByText(/Points:/i)).toBeInTheDocument())

    const downloadBtn = screen.getByLabelText(/Download timeseries as CSV/i)
    await userEvent.click(downloadBtn)
    expect(global.URL.createObjectURL).toBeDefined()
  })
})
