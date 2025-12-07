import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { CatalogBrowser } from '@/components/browse/CatalogBrowser'

describe('CatalogBrowser', () => {
  it('loads root collections and shows items on selection', async () => {
    render(<CatalogBrowser />)

    const rootBreadcrumb = await screen.findByTestId('breadcrumb')
    expect(rootBreadcrumb.textContent).toContain('Root')

    const collectionBtn = await screen.findByRole('button', { name: /Ocean Temps/i })
    await userEvent.click(collectionBtn)

    await waitFor(() => expect(screen.getByTestId('breadcrumb').textContent).toContain('Ocean Temps'))
    const itemBtn = await screen.findByRole('button', { name: /Sea Surface Temperature/i })
    await userEvent.click(itemBtn)

    expect(await screen.findByTestId('item-details')).toBeInTheDocument()
    expect(screen.getAllByText(/Sea Surface Temperature/).length).toBeGreaterThan(0)
  })
})
