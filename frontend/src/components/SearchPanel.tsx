/**
 * Search panel component with filters for dataset discovery
 */

import { useState, useEffect, useCallback, ChangeEvent, useRef } from 'react';
import { apiClient } from '../api/client';
import type { Dataset, SearchFilters } from '../types';
import { ApiError, formatErrorMessage, normalizeApiError } from '../utils/errors';
import { ErrorNotice } from './ErrorNotice';

type SearchParams = {
  start_date?: string;
  end_date?: string;
  bbox?: string;
  variables?: string[];
  collections?: string[];
  limit: number;
  offset: number;
};

interface SearchPanelProps {
  onDatasetSelect: (dataset: Dataset) => void;
}

export function SearchPanel({ onDatasetSelect }: SearchPanelProps) {
  const [filters, setFilters] = useState<SearchFilters>({
    dateRange: null,
    bbox: null,
    variables: [],
    collections: [],
    searchText: '',
  });

  const [results, setResults] = useState<Dataset[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [lastError, setLastError] = useState<ApiError | null>(null);
  const [collections, setCollections] = useState<string[]>([]);
  const searchTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Load available collections on mount
  useEffect(() => {
    loadCollections();
  }, []);

  const loadCollections = async () => {
    try {
      const cols = await apiClient.getCollections();
      setCollections(cols);
    } catch (err) {
      const normalized = err instanceof ApiError ? err : new ApiError(normalizeApiError(err));
      setError(formatErrorMessage(normalized));
      setLastError(normalized);
      console.error('Failed to load collections:', normalized.message);
    }
  };

  // Debounced search function
  const performSearch = useCallback(async () => {
    setIsLoading(true);
    setError(null);

    try {
      const params: SearchParams = {
        limit: 50,
        offset: 0,
      };

      // Add filters if set
      if (filters.dateRange) {
        params.start_date = filters.dateRange[0].toISOString();
        params.end_date = filters.dateRange[1].toISOString();
      }

      if (filters.collections.length > 0) {
        params.collections = filters.collections;
      }

      if (filters.variables.length > 0) {
        params.variables = filters.variables;
      }

      if (filters.bbox) {
        params.bbox = filters.bbox.join(',');
      }

      const response = await apiClient.searchDatasets(params);
      setResults(response.items);
      setLastError(null);
    } catch (err: unknown) {
      const normalized = err instanceof ApiError ? err : new ApiError(normalizeApiError(err));
      setError(formatErrorMessage(normalized));
      setLastError(normalized);
      setResults([]);
    } finally {
      setIsLoading(false);
    }
  }, [filters]);

  // Trigger search with debouncing
  useEffect(() => {
    if (searchTimeoutRef.current) {
      clearTimeout(searchTimeoutRef.current);
    }

    const timeout = setTimeout(() => {
      performSearch();
    }, 500); // 500ms debounce

    searchTimeoutRef.current = timeout;

    return () => {
      if (timeout) clearTimeout(timeout);
    };
  }, [filters, performSearch]);

  const handleCollectionToggle = (collection: string) => {
    setFilters((prev: SearchFilters) => ({
      ...prev,
      collections: prev.collections.includes(collection)
        ? prev.collections.filter((c: string) => c !== collection)
        : [...prev.collections, collection],
    }));
  };

  return (
    <div className="h-full flex flex-col bg-white shadow-lg">
      {/* Header with gradient */}
      <div className="p-4 border-b-2 border-blue-500 bg-gradient-to-r from-blue-50 to-indigo-50">
        <h2 className="text-xl font-bold text-gray-900">Search Datasets</h2>
        <p className="text-sm text-gray-700 mt-1 font-medium">
          Filter by collection, date, or location
        </p>
      </div>

      {/* Filters */}
      <div className="flex-1 overflow-y-auto p-4 space-y-4">
        {/* Search text input */}
        <div>
          <label className="block text-sm font-semibold text-gray-800 mb-2">
            Search
          </label>
          <input
            type="text"
            placeholder="Search datasets..."
            value={filters.searchText}
            onChange={(e: ChangeEvent<HTMLInputElement>) =>
              setFilters((prev: SearchFilters) => ({ ...prev, searchText: e.target.value }))
            }
            className="w-full px-3 py-2 border-2 border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500 bg-white shadow-sm"
          />
        </div>

        {/* Collections filter */}
        <div>
          <label className="block text-sm font-semibold text-gray-800 mb-2">
            Collections
          </label>
          <div className="space-y-2 max-h-48 overflow-y-auto border-2 border-gray-300 rounded-lg p-3 bg-gray-50 shadow-inner">
            {collections.length === 0 ? (
              <p className="text-sm text-gray-500 text-center py-2">
                Loading collections...
              </p>
            ) : (
              collections.map((collection) => (
                <label
                  key={collection}
                  className="flex items-center space-x-2 cursor-pointer hover:bg-white p-2 rounded-md transition-colors"
                >
                  <input
                    type="checkbox"
                    checked={filters.collections.includes(collection)}
                    onChange={() => handleCollectionToggle(collection)}
                    className="rounded border-gray-400 text-blue-600 focus:ring-blue-500 w-4 h-4"
                  />
                  <span className="text-sm text-gray-900 font-medium">{collection}</span>
                </label>
              ))
            )}
          </div>
        </div>

        {/* Date range filter */}
        <div>
          <label className="block text-sm font-semibold text-gray-800 mb-2">
            Date Range
          </label>
          <div className="space-y-2">
            <input
              type="date"
              placeholder="Start date"
              onChange={(e) => {
                const date = e.target.value ? new Date(e.target.value) : null;
                setFilters((prev) => ({
                  ...prev,
                  dateRange: date
                    ? [date, prev.dateRange?.[1] || date]
                    : null,
                }));
              }}
              className="w-full px-3 py-2 border-2 border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500 text-sm bg-white shadow-sm"
            />
            <input
              type="date"
              placeholder="End date"
              defaultValue={new Date().toISOString().split('T')[0]}
              onChange={(e) => {
                const date = e.target.value ? new Date(e.target.value) : null;
                setFilters((prev) => ({
                  ...prev,
                  dateRange: date
                    ? [prev.dateRange?.[0] || date, date]
                    : null,
                }));
              }}
              className="w-full px-3 py-2 border-2 border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500 text-sm bg-white shadow-sm"
            />
          </div>
        </div>

        {/* Clear filters button */}
        {(filters.collections.length > 0 ||
          filters.dateRange ||
          filters.searchText) && (
          <button
            onClick={() =>
              setFilters({
                dateRange: null,
                bbox: null,
                variables: [],
                collections: [],
                searchText: '',
              })
            }
            className="w-full px-4 py-2 text-sm font-semibold text-white bg-gradient-to-r from-gray-600 to-gray-700 hover:from-gray-700 hover:to-gray-800 rounded-lg transition-all shadow-md hover:shadow-lg"
          >
            Clear Filters
          </button>
        )}
      </div>

      {/* Results */}
      <div className="border-t-2 border-gray-300 p-4 bg-gray-50">
        <div className="flex items-center justify-between mb-3">
          <h3 className="text-base font-bold text-gray-900">
            Results ({results.length})
          </h3>
          {isLoading && (
            <div className="flex items-center space-x-2">
              <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-blue-600"></div>
              <span className="text-xs text-gray-500">Searching...</span>
            </div>
          )}
        </div>

        {error && (
          <div className="mb-3">
            <ErrorNotice
              message={error}
              correlationId={lastError?.correlationId}
              onRetry={lastError?.retryable ? performSearch : undefined}
              title="Search failed"
            />
          </div>
        )}

        <div className="space-y-2 overflow-y-auto" style={{ maxHeight: '300px' }}>
          {results.length === 0 && !isLoading && !error && (
            <p className="text-sm text-gray-500 text-center py-4">
              No datasets found. Try adjusting your filters.
            </p>
          )}

          {results.map((dataset) => (
            <button
              key={dataset.id}
              onClick={() => onDatasetSelect(dataset)}
              className="w-full text-left p-3 border-2 border-gray-300 rounded-lg hover:border-blue-500 hover:bg-blue-50 transition-all flex-shrink-0 bg-white shadow-sm hover:shadow-md"
            >
              <h4 className="text-sm font-bold text-gray-900 mb-1 truncate">
                {dataset.title || dataset.id}
              </h4>
              <p className="text-xs text-gray-700 line-clamp-2 font-medium">
                {dataset.description || 'No description available'}
              </p>
              <div className="flex items-center space-x-2 mt-2">
                <span className="text-xs text-blue-600 font-semibold truncate bg-blue-50 px-2 py-1 rounded">
                  {dataset.collection}
                </span>
              </div>
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}
