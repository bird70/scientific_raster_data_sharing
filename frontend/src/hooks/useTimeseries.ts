/**
 * Hook for managing timeseries data fetching and state
 */

import { useState, useCallback } from 'react';
import { apiClient } from '../api/client';
import type { TimeseriesData, LatLng, Dataset } from '../types';
import { ApiError, formatErrorMessage, normalizeApiError } from '../utils/errors';

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

      const timeseriesData = await apiClient.getTimeseries({
        lon: point.lng,
        lat: point.lat,
        start,
        end,
        variable,
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

  const exportData = useCallback(async (format: 'csv' | 'json') => {
    if (!data) return;

    try {
      const exportPayload = {
        times: data.times,
        values: data.values,
        variable: data.metadata?.variable || 'value',
        units: data.metadata?.units || '',
        metadata: data.metadata || {},
      };

      if (format === 'csv') {
        const blob = await apiClient.exportCSV(exportPayload);
        
        // Create download link
        const url = window.URL.createObjectURL(blob);
        const link = document.createElement('a');
        link.href = url;
        link.download = `timeseries_${data.metadata?.variable || 'data'}_${new Date().toISOString().split('T')[0]}.csv`;
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
        window.URL.revokeObjectURL(url);
      } else {
        const jsonData = await apiClient.exportJSON(exportPayload);
        
        // Create download link for JSON
        const blob = new Blob([JSON.stringify(jsonData, null, 2)], { type: 'application/json' });
        const url = window.URL.createObjectURL(blob);
        const link = document.createElement('a');
        link.href = url;
        link.download = `timeseries_${data.metadata?.variable || 'data'}_${new Date().toISOString().split('T')[0]}.json`;
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
        window.URL.revokeObjectURL(url);
      }
    } catch (err: unknown) {
      const normalized = err instanceof ApiError ? err : new ApiError(normalizeApiError(err));
      console.error('Export failed:', normalized.message);
      setError(`Export failed: ${normalized.message}`);
      setLastError(normalized);
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
