import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import { SearchResults } from '@/components/search/SearchResults'
import type { Dataset } from '@/types'

describe('SearchResults', () => {
  const baseDataset: Dataset = {
    id: 'ds-1',
    collection: 'collection-a',
    title: 'Dataset One',
    description: 'Example dataset',
    temporal: {
      start: new Date('2024-01-01T00:00:00.000Z'),
      end: new Date('2024-02-01T00:00:00.000Z'),
      interval: 'P1M',
    },
    spatial: {
      bbox: [-10, -20, 10, 20],
      crs: 'EPSG:4326',
    },
    variables: [],
    assets: { cog: '', zarr: '' },
    properties: {},
  }

  it('shows empty state when no results and not loading', () => {
    render(
      <SearchResults
        results={[]}
        isLoading={false}
        error={null}
        onSelect={vi.fn()}
      />,
    )

    expect(screen.getByText(/No datasets found/i)).toBeInTheDocument()
  })

  it('renders dataset cards and handles selection', async () => {
    const onSelect = vi.fn()
    const user = userEvent.setup()

    render(
      <SearchResults
        results={[baseDataset]}
        isLoading={false}
        error={null}
        onSelect={onSelect}
      />,
    )

    expect(screen.getByText(/Dataset One/)).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: /Dataset One/i }))
    expect(onSelect).toHaveBeenCalledWith(baseDataset)
  })
})
