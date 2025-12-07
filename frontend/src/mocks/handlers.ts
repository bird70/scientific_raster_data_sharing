import { http, HttpResponse } from 'msw'

const stubDataset = {
  id: 'dataset-123',
  title: 'Sea Surface Temperature',
  description: 'Daily SST composites',
  bbox: [-180, -90, 180, 90] as [number, number, number, number],
  temporalExtent: { start: '2024-01-01', end: '2024-12-31' },
  variables: [{ name: 'temperature', units: 'K', assetKey: 'sst' }],
  assets: { sst: 's3://example/sst.tif' },
  thumbnailUrl: 'https://example.com/thumb.png',
  collectionId: 'collection-1',
}

const catalogCollections = [
  {
    id: 'collection-1',
    title: 'Ocean Temps',
    description: 'Global sea surface temperature composites',
    childCollections: [],
    items: [stubDataset],
  },
]

const blankPng = Uint8Array.from([
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1,
  8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 12, 73, 68, 65, 84, 8, 153, 99, 0, 1, 0, 0, 5,
  0, 1, 13, 10, 42, 180, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
])

export const handlers = [
  http.post('/api/v1/stac/search', async () => {
    return HttpResponse.json({
      items: [stubDataset],
      page: 1,
      pageSize: 20,
      hasMore: false,
    })
  }),

  http.get('/tiles/:collection/:z/:x/:y.png', async () => {
    return new HttpResponse(blankPng, {
      status: 200,
      headers: {
        'Content-Type': 'image/png',
        'Cache-Control': 'public, max-age=60',
      },
    })
  }),

  http.post('/api/v1/timeseries', async () => {
    return HttpResponse.json({
      series: [
        {
          datasetId: 'dataset-123',
          variable: 'temperature',
          units: 'K',
          times: ['2024-01-01T00:00:00Z', '2024-01-02T00:00:00Z'],
          values: [290.1, 289.5],
        },
      ],
    })
  }),

  http.get('/api/v1/collections', async () => {
    return HttpResponse.json({ collections: catalogCollections })
  }),

  http.get('/api/v1/collections/:id', async ({ params }) => {
    const match = catalogCollections.find((c) => c.id === params.id)
    if (!match) return HttpResponse.json({ error: { code: 'NOT_FOUND', message: 'not found' } }, { status: 404 })
    return HttpResponse.json(match)
  }),
]
