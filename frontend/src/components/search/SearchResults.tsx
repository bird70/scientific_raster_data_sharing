import type { Dataset } from '../../types'
import { ErrorNotice } from '../ErrorNotice'
import { ResultFootprintPreview } from './ResultFootprintPreview'

interface SearchResultsProps {
  results: Dataset[]
  isLoading: boolean
  error?: string | null
  correlationId?: string
  onRetry?: () => void
  onSelect: (dataset: Dataset) => void
}

export function SearchResults({ results, isLoading, error, correlationId, onRetry, onSelect }: SearchResultsProps) {
  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between mb-2">
        <h3 className="text-base font-bold text-gray-900">Results ({results.length})</h3>
        {isLoading && (
          <div className="flex items-center space-x-2 text-xs text-gray-600">
            <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-blue-600" />
            <span>Searching...</span>
          </div>
        )}
      </div>

      {error && (
        <ErrorNotice
          title="Search failed"
          message={error}
          correlationId={correlationId}
          onRetry={onRetry}
        />
      )}

      <div className="space-y-2 max-h-80 overflow-y-auto">
        {!isLoading && !error && results.length === 0 && (
          <p className="text-sm text-gray-500 text-center py-4">No datasets found. Try adjusting your filters.</p>
        )}

        {results.map((dataset) => (
          <button
            key={dataset.id}
            onClick={() => onSelect(dataset)}
            className="w-full text-left p-3 border-2 border-gray-200 rounded-lg hover:border-blue-500 hover:bg-blue-50 transition-all bg-white shadow-sm"
          >
            <div className="flex items-start justify-between gap-3">
              <div className="flex-1 min-w-0">
                <h4 className="text-sm font-bold text-gray-900 mb-1 truncate">{dataset.title || dataset.id}</h4>
                <p className="text-xs text-gray-700 line-clamp-2">{dataset.description || 'No description available'}</p>
                <div className="flex items-center gap-2 mt-2 text-xs text-gray-600">
                  <span className="px-2 py-1 bg-blue-50 text-blue-700 font-semibold rounded">{dataset.collection}</span>
                  {dataset.temporal?.start && (
                    <span>
                      {new Date(dataset.temporal.start).toISOString().split('T')[0]} —{' '}
                      {new Date(dataset.temporal.end).toISOString().split('T')[0]}
                    </span>
                  )}
                </div>
              </div>
              <ResultFootprintPreview bbox={dataset.spatial?.bbox} />
            </div>
          </button>
        ))}
      </div>
    </div>
  )
}
