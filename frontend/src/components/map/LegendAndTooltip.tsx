interface LegendProps {
  min?: number
  max?: number
  units?: string
  paletteName?: string
}

interface HoverInfo {
  value?: number | null
  lat?: number
  lng?: number
}

interface LegendAndTooltipProps {
  legend?: LegendProps
  hover?: HoverInfo
}

export function LegendAndTooltip({ legend, hover }: LegendAndTooltipProps) {
  return (
    <div className="space-y-3" data-testid="legend-tooltip">
      <div className="border border-gray-200 rounded-lg p-3 bg-white shadow-sm">
        <p className="text-sm font-semibold text-gray-900 mb-1">Legend</p>
        {legend ? (
          <div className="text-xs text-gray-700 space-y-1">
            <div className="flex justify-between">
              <span>Min</span>
              <span className="font-semibold">{legend.min ?? '—'}</span>
            </div>
            <div className="flex justify-between">
              <span>Max</span>
              <span className="font-semibold">{legend.max ?? '—'}</span>
            </div>
            {legend.units && <p>Units: {legend.units}</p>}
            {legend.paletteName && <p>Palette: {legend.paletteName}</p>}
          </div>
        ) : (
          <p className="text-xs text-gray-600">No legend available</p>
        )}
      </div>

      <div className="border border-gray-200 rounded-lg p-3 bg-white shadow-sm">
        <p className="text-sm font-semibold text-gray-900 mb-1">Hover probe</p>
        {hover?.value != null ? (
          <div className="text-xs text-gray-700 space-y-1">
            <p className="font-semibold">Value: {hover.value}</p>
            {hover.lat != null && hover.lng != null && <p>Location: {hover.lat.toFixed(4)}, {hover.lng.toFixed(4)}</p>}
          </div>
        ) : (
          <p className="text-xs text-gray-600">Hover over the map to see values</p>
        )}
      </div>
    </div>
  )
}
