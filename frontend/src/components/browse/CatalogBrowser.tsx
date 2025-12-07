import { useEffect, useState } from 'react'
import type { CollectionNode, Dataset } from '@/types'
import { fetchCollection, fetchRootCollections } from '@/services/catalogBrowse'
import { ItemDetails } from './ItemDetails'

interface CatalogBrowserProps {
  onViewOnMap?: (dataset: Dataset) => void
  onViewTimeseries?: (dataset: Dataset) => void
}

export function CatalogBrowser({ onViewOnMap, onViewTimeseries }: CatalogBrowserProps) {
  const [collections, setCollections] = useState<CollectionNode[]>([])
  const [activeCollection, setActiveCollection] = useState<CollectionNode | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [breadcrumb, setBreadcrumb] = useState<string[]>(['Root'])
  const [selectedDataset, setSelectedDataset] = useState<Dataset | null>(null)

  useEffect(() => {
    const loadRoot = async () => {
      setLoading(true)
      setError(null)
      try {
        const data = await fetchRootCollections()
        setCollections(data)
        setActiveCollection(null)
        setBreadcrumb(['Root'])
      } catch (err) {
        const message = err instanceof Error ? err.message : 'Failed to load catalog'
        setError(message)
      } finally {
        setLoading(false)
      }
    }
    loadRoot()
  }, [])

  const handleCollectionClick = async (collectionId: string) => {
    setLoading(true)
    setError(null)
    try {
      const data = await fetchCollection(collectionId)
      setActiveCollection(data)
      setBreadcrumb(['Root', data.title])
      setSelectedDataset(null)
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to load collection'
      setError(message)
    } finally {
      setLoading(false)
    }
  }

  const datasets = activeCollection?.items ?? []
  const childCollections = activeCollection ? activeCollection.childCollections : collections.map((c) => c.id)

  return (
    <div className="grid grid-cols-3 gap-4" data-testid="catalog-browser">
      <div className="col-span-1 card-surface p-4">
        <div className="flex items-center justify-between mb-3">
          <div>
            <p className="text-xs text-muted">Breadcrumb</p>
            <p className="text-sm font-semibold" data-testid="breadcrumb">{breadcrumb.join(' / ')}</p>
          </div>
          {loading && <span className="text-xs text-muted">Loading...</span>}
        </div>
        {error && <p className="text-sm text-red-600" role="alert">{error}</p>}
        <div className="space-y-2" data-testid="collections-list">
          {childCollections.map((id) => {
            const title = collections.find((c) => c.id === id)?.title || id
            return (
              <button
                key={id}
                className="w-full text-left px-3 py-2 rounded-md border border-gray-200 hover:border-blue-500 hover:bg-blue-50 transition"
                onClick={() => handleCollectionClick(id)}
              >
                <p className="text-sm font-semibold text-gray-900">{title}</p>
                <p className="text-xs text-muted">{id}</p>
              </button>
            )
          })}
          {!loading && childCollections.length === 0 && (
            <p className="text-sm text-muted">No collections found.</p>
          )}
        </div>
      </div>

      <div className="col-span-1 card-surface p-4" data-testid="items-list">
        <p className="text-sm font-semibold mb-2">Items</p>
        {datasets.length === 0 && <p className="text-sm text-muted">Select a collection to view items.</p>}
        <div className="space-y-2">
          {datasets.map((item) => (
            <button
              key={item.id}
              className="w-full text-left px-3 py-2 rounded-md border border-gray-200 hover:border-blue-500 hover:bg-blue-50 transition"
              onClick={() => setSelectedDataset(item)}
            >
              <p className="text-sm font-semibold text-gray-900">{item.title}</p>
              <p className="text-xs text-muted">{item.id}</p>
            </button>
          ))}
        </div>
      </div>

      <div className="col-span-1">
        {selectedDataset ? (
          <ItemDetails dataset={selectedDataset} onViewOnMap={onViewOnMap} onViewTimeseries={onViewTimeseries} />
        ) : (
          <div className="card-surface p-4 h-full flex items-center justify-center">
            <p className="text-sm text-muted">Select an item to see details.</p>
          </div>
        )}
      </div>
    </div>
  )
}
