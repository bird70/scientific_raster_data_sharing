import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import { SearchPanel } from '@/components/SearchPanel'
import { apiClient } from '@/api/client'
import { searchStac } from '@/services/stacSearch'
import { ApiError } from '@/utils/errors'
import type { Dataset } from '@/types'

vi.mock('@/api/client', () => ({
  apiClient: {
    getCollections: vi.fn(),
  },
}))

vi.mock('@/services/stacSearch', () => ({
  searchStac: vi.fn(),
}))

describe('SearchPanel', () => {
  const mockCollections = ['collection-a', 'collection-b']
  const baseResponse = { items: [] as Dataset[], page: 1, pageSize: 50, hasMore: false }
  const mockedGetCollections = vi.mocked(apiClient.getCollections)
  const mockedSearchStac = vi.mocked(searchStac)

  beforeEach(() => {
    mockedGetCollections.mockResolvedValue(mockCollections)
    mockedSearchStac.mockResolvedValue(baseResponse)
  })

  afterEach(() => {
    vi.clearAllMocks()
  })

  it('builds a STAC payload from form inputs and submits search', async () => {
    const user = userEvent.setup()
    render(<SearchPanel onDatasetSelect={vi.fn()} />)

    await waitFor(() => expect(mockedGetCollections).toHaveBeenCalled())

    fireEvent.change(screen.getByPlaceholderText(/e\.g\. temperature, precipitation/i), {
      target: { value: 'rain' },
    })
    fireEvent.change(screen.getByLabelText(/Start date/i), { target: { value: '2024-01-01' } })
    fireEvent.change(screen.getByLabelText(/End date/i), { target: { value: '2024-02-02' } })

    const bboxPlaceholders = ['minX', 'minY', 'maxX', 'maxY']
    const bboxValues = ['-10', '-20', '10', '20']
    for (let i = 0; i < bboxPlaceholders.length; i += 1) {
      fireEvent.change(screen.getByPlaceholderText(bboxPlaceholders[i]), {
        target: { value: bboxValues[i] },
      })
    }

    fireEvent.change(screen.getByPlaceholderText('temperature, precipitation'), {
      target: { value: 'temp, precip' },
    })
    await waitFor(() => expect(screen.getByLabelText('collection-a')).toBeInTheDocument())
    await user.click(screen.getByLabelText('collection-a'))

    await user.click(screen.getByRole('button', { name: /Search/i }))

    await waitFor(() => expect(mockedSearchStac).toHaveBeenCalled())
    const lastCall = mockedSearchStac.mock.calls[mockedSearchStac.mock.calls.length - 1]
    expect(lastCall?.[0]).toEqual({
      keywords: 'rain',
      collections: ['collection-a'],
      variables: ['temp', 'precip'],
      bbox: [-10, -20, 10, 20],
      datetime: '2024-01-01T00:00:00.000Z/2024-02-02T00:00:00.000Z',
      limit: 50,
      page: 1,
    })
  })

  it('surfaces API errors and retries when retryable', async () => {
    const user = userEvent.setup()
    mockedSearchStac
      .mockRejectedValueOnce(new ApiError({ message: 'Boom', correlationId: 'abc-123', retryable: true }))
      .mockResolvedValueOnce(baseResponse)

    render(<SearchPanel onDatasetSelect={vi.fn()} />)
    await waitFor(() => expect(mockedGetCollections).toHaveBeenCalled())

    fireEvent.change(screen.getByPlaceholderText(/e\.g\. temperature, precipitation/i), {
      target: { value: 'snow' },
    })
    await user.click(screen.getByRole('button', { name: /Search/i }))

    await waitFor(() => screen.getByText(/Search failed/i))
    expect(screen.getByText(/Boom/)).toBeInTheDocument()
    expect(screen.getByText('Ref: abc-123')).toBeInTheDocument()

    await user.click(screen.getByRole('button', { name: /Retry/i }))
    await waitFor(() => expect(mockedSearchStac).toHaveBeenCalledTimes(2))
  })
})
