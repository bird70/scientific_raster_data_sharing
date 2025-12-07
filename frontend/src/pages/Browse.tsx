import { CatalogBrowser } from '@/components/browse/CatalogBrowser'

export function Browse() {
  return (
    <div className="p-6 space-y-4">
      <div>
        <h2 className="text-2xl font-bold text-gray-900">Catalog Browser</h2>
        <p className="text-sm text-muted">Navigate collections and view item metadata.</p>
      </div>
      <CatalogBrowser />
    </div>
  )
}
