import { ReactNode, useState } from 'react'

interface ResponsiveLayoutProps {
  mapSlot: ReactNode
  sidebar: ReactNode
}

export function ResponsiveLayout({ mapSlot, sidebar }: ResponsiveLayoutProps) {
  const [sidebarOpen, setSidebarOpen] = useState(false)

  return (
    <div className="map-layout">
      <div className="map-canvas" data-testid="map-canvas">
        {mapSlot}
        <button
          type="button"
          className="map-toggle md:hidden"
          onClick={() => setSidebarOpen(true)}
          aria-label="Open layer controls"
          data-testid="open-controls"
        >
          Controls
          <span aria-hidden>⇧</span>
        </button>
      </div>

      <aside
        className="map-sidebar"
        data-state={sidebarOpen ? 'open' : 'closed'}
        data-testid="map-sidebar"
      >
        <div className="map-sidebar__header md:hidden">
          <p className="text-sm font-semibold text-gray-900">Layers & Legend</p>
          <button
            type="button"
            className="text-sm px-3 py-2 rounded-md border border-gray-300 hover:bg-gray-50"
            onClick={() => setSidebarOpen(false)}
            aria-label="Close controls"
            data-testid="close-controls"
          >
            Close
          </button>
        </div>
        {sidebar}
      </aside>

      <button
        type="button"
        className="sidebar-backdrop"
        data-state={sidebarOpen ? 'open' : 'closed'}
        onClick={() => setSidebarOpen(false)}
        aria-label="Close controls backdrop"
        data-testid="sidebar-backdrop"
      />
    </div>
  )
}
