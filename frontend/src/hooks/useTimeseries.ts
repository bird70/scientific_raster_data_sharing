/**
 * Hook for managing timeseries data fetching and state
 */

import { useState, useCallback } from 'react'
import type { TimeseriesData } from '@/types'
import { ApiError, formatErrorMessage, normalizeApiError } from '../utils/errors'
import { fetchTimeseries as fetchTimeseriesApi, type TimeseriesRequest } from '@/services/timeseries'

export function useTimeseries() {
  const [data, setData] = useState<TimeseriesData | null>(null)
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [lastError, setLastError] = useState<ApiError | null>(null)

  const fetchTimeseries = useCallback(async (query: TimeseriesRequest) => {
    setIsLoading(true)
    setError(null)

    try {
      const timeseriesData = await fetchTimeseriesApi(query)
      setData(timeseriesData)
      setLastError(null)
    } catch (err: unknown) {
      const normalized = err instanceof ApiError ? err : new ApiError(normalizeApiError(err))
      const errorMessage = formatErrorMessage(normalized)
      setError(errorMessage)
      setLastError(normalized)
      setData(null)
    } finally {
      setIsLoading(false)
    }
  }, [])

  const exportData = useCallback(
    (format: 'csv' | 'json') => {
      if (!data || data.series.length === 0) return

      const filename = `timeseries_${new Date().toISOString().split('T')[0]}`

      if (format === 'csv') {
        const header = 'label,time,value'
        const rows = data.series.flatMap((series) => {
          const label = series.label || series.variable || series.datasetId || 'series'
          return series.times.map((time, idx) => `${label},${time},${series.values[idx] ?? ''}`)
        })
        const csv = [header, ...rows].join('\n')
        const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' })
        const url = window.URL.createObjectURL(blob)
        const link = document.createElement('a')
        link.href = url
        link.download = `${filename}.csv`
        document.body.appendChild(link)
        link.click()
        document.body.removeChild(link)
        window.URL.revokeObjectURL(url)
      } else {
        const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' })
        const url = window.URL.createObjectURL(blob)
        const link = document.createElement('a')
        link.href = url
        link.download = `${filename}.json`
        document.body.appendChild(link)
        link.click()
        document.body.removeChild(link)
        window.URL.revokeObjectURL(url)
      }
    },
    [data]
  )

  const clearData = useCallback(() => {
    setData(null)
    setError(null)
    setLastError(null)
  }, [])

  return {
    data,
    isLoading,
    error,
    lastError,
    fetchTimeseries,
    exportData,
    clearData,
  }
}
