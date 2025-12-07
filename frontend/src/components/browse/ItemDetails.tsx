import type { Dataset } from '@/types'

interface ItemDetailsProps {
  dataset: Dataset
  onViewOnMap?: (dataset: Dataset) => void
  onViewTimeseries?: (dataset: Dataset) => void
}

export function ItemDetails({ dataset, onViewOnMap, onViewTimeseries }: ItemDetailsProps) {
  return (
    <div className="card-surface p-4 space-y-3" data-testid="item-details">
      <div>
        <p className="text-xs text-muted">Dataset</p>
        <p className="text-lg font-semibold text-gray-900">{dataset.title}</p>
        <p className="text-sm text-muted">{dataset.id}</p>
      </div>

      <p className="text-sm text-gray-700 leading-relaxed">{dataset.description}</p>

      <div className="grid grid-cols-2 gap-3 text-sm">
        <div>
          <p className="text-xs text-muted">Collection</p>
          <p className="font-semibold">{dataset.collection}</p>
        </div>
        <div>
          <p className="text-xs text-muted">Temporal</p>
          <p className="font-semibold">
            {dataset.temporal?.start?.toISOString?.().slice(0, 10)} — {dataset.temporal?.end?.toISOString?.().slice(0, 10)}
          </p>
        </div>
      </div>

      <div className="flex gap-2">
        <button
          className="button-primary w-full"
          onClick={() => onViewOnMap?.(dataset)}
          aria-label="View on map"
        >
          View on Map
        </button>
        <button
          className="w-full border border-gray-300 rounded-md px-3 py-2 text-sm font-semibold text-gray-800 hover:bg-gray-50"
          onClick={() => onViewTimeseries?.(dataset)}
          aria-label="View timeseries"
        >
          View Timeseries
        </button>
      </div>
    </div>
  )
}
