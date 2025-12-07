import { Link, useLocation } from 'react-router-dom'

interface MobileNavProps {
  isOpen: boolean
  onClose: () => void
  links: Array<{ label: string; to: string }>
}

export function MobileNav({ isOpen, onClose, links }: MobileNavProps) {
  const location = useLocation()

  return (
    <>
      <div
        className="mobile-nav-backdrop"
        data-state={isOpen ? 'open' : 'closed'}
        onClick={onClose}
        data-testid="mobile-nav-backdrop"
      />
      <aside
        className="mobile-nav-panel"
        data-state={isOpen ? 'open' : 'closed'}
        data-testid="mobile-nav-panel"
        aria-label="Mobile navigation"
      >
        <div className="flex items-center justify-between mb-6">
          <div>
            <p className="text-xs uppercase tracking-[0.2em] text-white/70">Navigate</p>
            <p className="text-lg font-extrabold text-white">Web Data Explorer</p>
          </div>
          <button
            type="button"
            className="text-white border border-white/30 rounded-lg px-3 py-2 text-sm font-semibold hover:bg-white/10"
            onClick={onClose}
            aria-label="Close navigation"
          >
            Close
          </button>
        </div>
        <nav className="space-y-2">
          {links.map((link) => {
            const isActive = location.pathname === link.to
            return (
              <Link
                key={link.to}
                to={link.to}
                className="mobile-nav-link"
                aria-current={isActive ? 'page' : undefined}
                onClick={onClose}
              >
                {link.label}
              </Link>
            )
          })}
        </nav>
      </aside>
    </>
  )
}
