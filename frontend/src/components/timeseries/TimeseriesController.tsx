import { useEffect, useMemo } from 'react'
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
  const layers = useMapStore((state) => state.layers)
  const colorScheme = usePreferencesStore((state) => state.colorScheme)
  const { data, isLoading, error, lastError, fetchTimeseries, exportData, clearData } = useTimeseries()

  const activeLayers = useMemo(
    () => layers.filter((layer) => layer.visible !== false),
    [layers]
  )

  useEffect(() => {
    if (!selectedPoint || activeLayers.length === 0) {
      clearData()
      return
    }

    const temporal = activeLayers.find((l) => l.temporal)?.temporal || dataset?.temporal
    const start = temporal?.start ? (typeof temporal.start === 'string' ? temporal.start : temporal.start.toISOString()) : new Date('1970-01-01').toISOString()
    const end = temporal?.end ? (typeof temporal.end === 'string' ? temporal.end : temporal.end.toISOString()) : new Date().toISOString()

    const layersWithVariables = activeLayers.map((layer) => ({
      ...layer,
      variable: layer.variable || variable || undefined,
    })).filter((layer) => layer.variable)

    if (layersWithVariables.length === 0) {
      clearData()
      return
    }

    fetchTimeseries({
      lon: selectedPoint.lng,
      lat: selectedPoint.lat,
      start,
      end,
      variables: Array.from(new Set(layersWithVariables.map((l) => l.variable as string))),
      datasetIds: layersWithVariables.map((l) => l.id),
    })
  }, [dataset, variable, selectedPoint, activeLayers, fetchTimeseries, clearData])

  const chartData = useMemo(() => {
    if (!data) return null

    const labelledSeries = data.series.map((series) => {
      const layer = activeLayers.find((l) => l.id === series.datasetId)
      const base = layer?.name || series.datasetId || 'Series'
      const variableLabel = layer?.variable || series.variable
      const label = variableLabel ? `${base} - ${variableLabel}` : base
      return { ...series, label }
    })

    return {
      ...data,
      series: labelledSeries,
      metadata: {
        coordinates: selectedPoint ?? data.metadata?.coordinates,
      },
    }
  }, [data, activeLayers, selectedPoint])

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
          data={chartData}
          isLoading={isLoading}
          onExport={exportData}
          colorScheme={colorScheme}
        />
      </div>
    </div>
  )
}
