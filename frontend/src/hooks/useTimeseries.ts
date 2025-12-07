/**
 * Hook for managing timeseries data fetching and state
 */

import { useState, useCallback } from 'react';
import type { TimeseriesData, LatLng, Dataset } from '../types';
import { ApiError, formatErrorMessage, normalizeApiError } from '../utils/errors';
import { fetchTimeseries as fetchTimeseriesApi } from '@/services/timeseries';

export function useTimeseries() {
  const [data, setData] = useState<TimeseriesData | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [lastError, setLastError] = useState<ApiError | null>(null);

  const fetchTimeseries = useCallback(async (
    point: LatLng,
    _dataset: Dataset,
    variable: string,
    dateRange?: { start: string; end: string }
  ) => {
    setIsLoading(true);
    setError(null);

    try {
      // Use dataset temporal range if no specific range provided
      const start = dateRange?.start || 
        (typeof _dataset.temporal.start === 'string' ? _dataset.temporal.start : _dataset.temporal.start.toISOString());
      const end = dateRange?.end || 
        (typeof _dataset.temporal.end === 'string' ? _dataset.temporal.end : _dataset.temporal.end.toISOString());

      const timeseriesData = await fetchTimeseriesApi({
        lon: point.lng,
        lat: point.lat,
        start,
        end,
        variables: [variable],
        datasetIds: [_dataset.id],
      });

      setData(timeseriesData);
      setLastError(null);
    } catch (err: unknown) {
      const normalized = err instanceof ApiError ? err : new ApiError(normalizeApiError(err));
      const errorMessage = formatErrorMessage(normalized);
      setError(errorMessage);
      setLastError(normalized);
      setData(null);
    } finally {
      setIsLoading(false);
    }
  }, []);

  const exportData = useCallback((format: 'csv' | 'json') => {
    if (!data) return;

    const filename = `timeseries_${data.metadata?.variable || 'data'}_${new Date().toISOString().split('T')[0]}`;
    if (format === 'csv') {
      const header = 'time,value';
      const rows = data.times.map((t, idx) => `${t},${data.values[idx] ?? ''}`);
      const csv = [header, ...rows].join('\n');
      const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
      const url = window.URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = `${filename}.csv`;
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
      window.URL.revokeObjectURL(url);
    } else {
      const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
      const url = window.URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = `${filename}.json`;
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
      window.URL.revokeObjectURL(url);
    }
  }, [data]);

  const clearData = useCallback(() => {
    setData(null);
    setError(null);
    setLastError(null);
  }, []);

  return {
    data,
    isLoading,
    error,
    lastError,
    fetchTimeseries,
    exportData,
    clearData,
  };
}
