import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, it, expect, vi } from 'vitest'
import { MemoryRouter } from 'react-router-dom'
import { ResponsiveLayout } from '@/components/map/ResponsiveLayout'
import { MobileNav } from '@/components/layout/MobileNav'

vi.mock('react-plotly.js', () => ({
  default: () => <div />,
}))

describe('ResponsiveLayout', () => {
  it('opens and closes the controls drawer', async () => {
    render(
      <ResponsiveLayout
        mapSlot={<div data-testid="map-slot">map</div>}
        sidebar={<div>sidebar content</div>}
      />
    )

    const sidebar = screen.getByTestId('map-sidebar')
    expect(sidebar).toHaveAttribute('data-state', 'closed')

    await userEvent.click(screen.getByTestId('open-controls'))
    expect(sidebar).toHaveAttribute('data-state', 'open')

    await userEvent.click(screen.getByTestId('close-controls'))
    expect(sidebar).toHaveAttribute('data-state', 'closed')
  })
})

describe('MobileNav', () => {
  it('renders links and closes on backdrop click', async () => {
    const handleClose = vi.fn()
    render(
      <MemoryRouter initialEntries={['/']}>
        <MobileNav
          isOpen
          onClose={handleClose}
          links={[
            { label: 'Explorer', to: '/' },
            { label: 'Browse', to: '/browse' },
          ]}
        />
      </MemoryRouter>
    )

    expect(screen.getByText('Explorer')).toBeInTheDocument()
    expect(screen.getByTestId('mobile-nav-panel')).toHaveAttribute('data-state', 'open')

    await userEvent.click(screen.getByTestId('mobile-nav-backdrop'))
    expect(handleClose).toHaveBeenCalled()
  })
})
