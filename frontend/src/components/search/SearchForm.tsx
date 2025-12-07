import { ChangeEvent } from 'react'
import type { SearchFilters } from '../../types'

interface SearchFormProps {
  filters: SearchFilters
  collections: string[]
  isLoading: boolean
  onFiltersChange: (next: SearchFilters) => void
  onSubmit: () => void
}

export function SearchForm({ filters, collections, isLoading, onFiltersChange, onSubmit }: SearchFormProps) {
  const updateField = <K extends keyof SearchFilters>(key: K, value: SearchFilters[K]) => {
    onFiltersChange({ ...filters, [key]: value })
  }

  const handleBboxChange = (index: number, value: string) => {
    const nextBbox = [...(filters.bbox || [0, 0, 0, 0])] as [number, number, number, number]
    nextBbox[index] = Number(value)
    updateField('bbox', nextBbox)
  }

  const handleDateChange = (index: 0 | 1, value: string) => {
    if (!value) {
      updateField('dateRange', null)
      return
    }
    const current = filters.dateRange ?? [new Date(), new Date()] as [Date, Date]
    const next = [...current] as [Date, Date]
    next[index] = new Date(value)
    updateField('dateRange', next)
  }

  const handleVariableChange = (evt: ChangeEvent<HTMLInputElement>) => {
    const val = evt.target.value
    const variables = val.split(',').map((v) => v.trim()).filter(Boolean)
    updateField('variables', variables)
  }

  return (
    <form
      className="space-y-4"
      onSubmit={(e) => {
        e.preventDefault()
        onSubmit()
      }}
    >
      <div>
        <label className="block text-sm font-semibold text-gray-800 mb-2">Keywords</label>
        <input
          type="text"
          value={filters.searchText}
          onChange={(e) => updateField('searchText', e.target.value)}
          placeholder="e.g. temperature, precipitation"
          className="w-full px-3 py-2 border-2 border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500 bg-white shadow-sm"
        />
      </div>

      <div>
        <label className="block text-sm font-semibold text-gray-800 mb-2">Collections</label>
        <div className="space-y-2 max-h-40 overflow-y-auto border-2 border-gray-200 rounded-lg p-3 bg-gray-50 shadow-inner">
          {collections.length === 0 ? (
            <p className="text-sm text-gray-500">Loading collections...</p>
          ) : (
            collections.map((collection) => (
              <label key={collection} className="flex items-center space-x-2 cursor-pointer">
                <input
                  type="checkbox"
                  checked={filters.collections.includes(collection)}
                  onChange={() => {
                    const exists = filters.collections.includes(collection)
                    const next = exists
                      ? filters.collections.filter((c) => c !== collection)
                      : [...filters.collections, collection]
                    updateField('collections', next)
                  }}
                  className="rounded border-gray-400 text-blue-600 focus:ring-blue-500 w-4 h-4"
                />
                <span className="text-sm text-gray-900">{collection}</span>
              </label>
            ))
          )}
        </div>
      </div>

      <div className="grid grid-cols-2 gap-3">
        <div>
          <label className="block text-sm font-semibold text-gray-800 mb-2">Start date</label>
          <input
            type="date"
            value={filters.dateRange?.[0]?.toISOString().split('T')[0] || ''}
            onChange={(e) => handleDateChange(0, e.target.value)}
            className="w-full px-3 py-2 border-2 border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 text-sm bg-white shadow-sm"
          />
        </div>
        <div>
          <label className="block text-sm font-semibold text-gray-800 mb-2">End date</label>
          <input
            type="date"
            value={filters.dateRange?.[1]?.toISOString().split('T')[0] || ''}
            onChange={(e) => handleDateChange(1, e.target.value)}
            className="w-full px-3 py-2 border-2 border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 text-sm bg-white shadow-sm"
          />
        </div>
      </div>

      <div>
        <label className="block text-sm font-semibold text-gray-800 mb-2">Variables (comma-separated)</label>
        <input
          type="text"
          value={filters.variables.join(', ')}
          onChange={handleVariableChange}
          placeholder="temperature, precipitation"
          className="w-full px-3 py-2 border-2 border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500 bg-white shadow-sm"
        />
      </div>

      <div>
        <label className="block text-sm font-semibold text-gray-800 mb-2">Bounding box (minX, minY, maxX, maxY)</label>
        <div className="grid grid-cols-4 gap-2">
          {['minX', 'minY', 'maxX', 'maxY'].map((label, idx) => (
            <input
              key={label}
              type="number"
              value={filters.bbox ? filters.bbox[idx] : ''}
              onChange={(e) => handleBboxChange(idx, e.target.value)}
              placeholder={label}
              className="w-full px-2 py-2 border-2 border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500 text-sm bg-white shadow-sm"
            />
          ))}
        </div>
      </div>

      <div className="flex items-center justify-between gap-2">
        <button
          type="button"
          onClick={() =>
            onFiltersChange({
              dateRange: null,
              bbox: null,
              variables: [],
              collections: [],
              searchText: '',
            })
          }
          className="px-4 py-2 text-sm font-semibold text-gray-700 bg-gray-100 border border-gray-300 rounded-lg hover:bg-gray-200"
        >
          Clear
        </button>
        <button
          type="submit"
          disabled={isLoading}
          className="px-4 py-2 text-sm font-semibold text-white bg-blue-600 rounded-lg hover:bg-blue-700 disabled:opacity-60"
        >
          {isLoading ? 'Searching...' : 'Search'}
        </button>
      </div>
    </form>
  )
}
