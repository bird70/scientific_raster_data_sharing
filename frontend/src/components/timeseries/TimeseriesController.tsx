import { useEffect } from 'react'
import type { Dataset } from '@/types'
import { useMapStore } from '@/state/mapStore'
import { usePreferencesStore } from '@/store/preferences'
import { useTimeseries } from '@/hooks/useTimeseries'
import { TimeseriesChart } from '@/components/TimeseriesChart'
import { DownloadCsvButton } from './DownloadCsvButton'
import { ErrorNotice } from '@/components/ErrorNotice'

interface TimeseriesControllerProps {
  dataset: Dataset | null
  variable: string | null
}

export function TimeseriesController({ dataset, variable }: TimeseriesControllerProps) {
  const selectedPoint = useMapStore((state) => state.selectedPoint)
  const colorScheme = usePreferencesStore((state) => state.colorScheme)
  const { data, isLoading, error, lastError, fetchTimeseries, exportData, clearData } = useTimeseries()

  useEffect(() => {
    if (dataset && variable && selectedPoint) {
      fetchTimeseries(selectedPoint, dataset, variable)
    } else {
      clearData()
    }
  }, [dataset, variable, selectedPoint, fetchTimeseries, clearData])

  if (!dataset) {
    return <p className="text-sm text-muted">Select a dataset to view timeseries.</p>
  }

  if (!variable) {
    return <p className="text-sm text-muted">Select a variable to query timeseries.</p>
  }

  return (
    <div className="h-full flex flex-col gap-3">
      <div className="flex items-center justify-between">
        <div className="text-sm text-muted">
          {selectedPoint ? (
            <span>
              Location: {selectedPoint.lat.toFixed(4)}, {selectedPoint.lng.toFixed(4)}
            </span>
          ) : (
            <span>Click on the map to sample a location.</span>
          )}
        </div>
        <DownloadCsvButton data={data} onDownload={() => exportData('csv')} />
      </div>

      {error && (
        <ErrorNotice
          title="Timeseries request failed"
          message={error}
          correlationId={lastError?.correlationId}
          onRetry={selectedPoint && dataset && variable ? () => fetchTimeseries(selectedPoint, dataset, variable) : undefined}
        />
      )}

      <div className="flex-1 min-h-[200px] border border-gray-200 rounded-md overflow-hidden">
        <TimeseriesChart
          data={data}
          isLoading={isLoading}
          onExport={exportData}
          colorScheme={colorScheme}
        />
      </div>
    </div>
  )
}
