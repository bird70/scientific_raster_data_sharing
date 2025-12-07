/**
 * Search panel component with filters for dataset discovery
 */

import { useState, useEffect, useCallback, useRef } from 'react';
import { apiClient } from '../api/client';
import type { Dataset, SearchFilters, StacSearchRequest } from '../types';
import { ApiError, formatErrorMessage, normalizeApiError } from '../utils/errors';
import { usePreferencesStore } from '../store/preferences';
import { SearchForm } from './search/SearchForm';
import { SearchResults } from './search/SearchResults';
import { searchStac } from '../services/stacSearch';

interface SearchPanelProps {
  onDatasetSelect: (dataset: Dataset) => void;
}

export function SearchPanel({ onDatasetSelect }: SearchPanelProps) {
  const { lastSearch, setLastSearch } = usePreferencesStore();
  const initialFilters: SearchFilters = {
    dateRange: lastSearch?.dateRange
      ? [new Date(lastSearch.dateRange[0]), new Date(lastSearch.dateRange[1])]
      : null,
    bbox: lastSearch?.bbox ?? null,
    variables: lastSearch?.variables ?? [],
    collections: lastSearch?.collections ?? [],
    searchText: lastSearch?.searchText ?? '',
  };

  const [filters, setFilters] = useState<SearchFilters>({ ...initialFilters });
  const [results, setResults] = useState<Dataset[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [lastError, setLastError] = useState<ApiError | null>(null);
  const [collections, setCollections] = useState<string[]>([]);
  const searchTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const buildSearchPayload = (f: SearchFilters): StacSearchRequest => {
    const payload: StacSearchRequest = {
      keywords: f.searchText.trim() || undefined,
      collections: f.collections.length ? f.collections : undefined,
      variables: f.variables.length ? f.variables : undefined,
      limit: 50,
      page: 1,
    };

    if (f.dateRange) {
      payload.datetime = `${f.dateRange[0].toISOString()}/${f.dateRange[1].toISOString()}`;
    }
    if (f.bbox) {
      payload.bbox = f.bbox;
    }
    return payload;
  };

  const loadCollections = useCallback(async () => {
    try {
      const cols = await apiClient.getCollections();
      setCollections(cols);
      setError(null);
    } catch (err) {
      const normalized = err instanceof ApiError ? err : new ApiError(normalizeApiError(err));
      setError(formatErrorMessage(normalized));
      setLastError(normalized);
      console.error('Failed to load collections:', normalized.message);
    }
  }, []);

  useEffect(() => {
    loadCollections();
  }, [loadCollections]);

  useEffect(() => {
    setLastSearch({
      dateRange: filters.dateRange
        ? [filters.dateRange[0].toISOString(), filters.dateRange[1].toISOString()]
        : null,
      bbox: filters.bbox,
      variables: filters.variables,
      collections: filters.collections,
      searchText: filters.searchText.trim().slice(0, 200),
    });
  }, [filters, setLastSearch]);

  const performSearch = useCallback(async () => {
    setIsLoading(true);
    setError(null);

    try {
      const payload = buildSearchPayload(filters);
      const response = await searchStac(payload);
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

  useEffect(() => {
    if (searchTimeoutRef.current) {
      clearTimeout(searchTimeoutRef.current);
    }

    const timeout = setTimeout(() => {
      void performSearch();
    }, 500);

    searchTimeoutRef.current = timeout;

    return () => {
      if (timeout) clearTimeout(timeout);
    };
  }, [filters, performSearch]);

  return (
    <div className="flex flex-col h-full bg-white border border-gray-200 shadow-sm rounded-lg overflow-hidden">
      <div className="p-4 border-b-2 border-blue-500 bg-gradient-to-r from-blue-50 to-indigo-50">
        <h2 className="text-xl font-bold text-gray-900">Search Datasets</h2>
        <p className="text-sm text-gray-700 mt-1 font-medium">Filter by collection, date, or location</p>
      </div>

      <div className="flex-1 overflow-y-auto p-4 space-y-4">
        <SearchForm
          filters={filters}
          collections={collections}
          isLoading={isLoading}
          onFiltersChange={setFilters}
          onSubmit={performSearch}
        />
      </div>

      <div className="border-t-2 border-gray-300 p-4 bg-gray-50">
        <SearchResults
          results={results}
          isLoading={isLoading}
          error={error}
          correlationId={lastError?.correlationId}
          onRetry={lastError?.retryable ? performSearch : undefined}
          onSelect={onDatasetSelect}
        />
      </div>
    </div>
  );
}
