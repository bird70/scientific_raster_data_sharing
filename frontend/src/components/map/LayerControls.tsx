import type { MapLayer } from '@/types'

interface LayerControlsProps {
  layers: MapLayer[]
  onOpacityChange: (id: string, value: number) => void
  onToggleVisibility: (id: string) => void
  onRemove: (id: string) => void
  onVariableChange?: (id: string, variable: string) => void
}

export function LayerControls({ layers, onOpacityChange, onToggleVisibility, onRemove, onVariableChange }: LayerControlsProps) {
  if (layers.length === 0) {
    return <p className="text-sm text-gray-600">No layers added yet.</p>
  }

  return (
    <div className="space-y-3" data-testid="layer-controls">
      {layers.map((layer) => (
        <div key={layer.id} className="border border-gray-200 rounded-lg p-3 bg-white shadow-sm">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm font-semibold text-gray-900">{layer.name}</p>
              <p className="text-xs text-gray-600">{layer.collection}{layer.variable ? ` • ${layer.variable}` : ''}</p>
            </div>
            <div className="flex items-center gap-2">
              <label className="flex items-center gap-1 text-xs text-gray-700">
                <input
                  type="checkbox"
                  checked={layer.visible}
                  onChange={() => onToggleVisibility(layer.id)}
                  aria-label={`Toggle ${layer.name}`}
                  className="rounded border-gray-400 text-blue-600 focus:ring-blue-500 w-4 h-4"
                />
                Visible
              </label>
              <button
                onClick={() => onRemove(layer.id)}
                className="text-xs text-red-600 hover:text-red-700 font-semibold"
                aria-label={`Remove ${layer.name}`}
              >
                Remove
              </button>
            </div>
          </div>

          <div className="mt-3 space-y-2">
            <label className="flex items-center gap-2 text-xs text-gray-700">
              Opacity
              <input
                type="range"
                min={0}
                max={1}
                step={0.05}
                value={layer.opacity}
                onChange={(e) => onOpacityChange(layer.id, Number(e.target.value))}
                aria-label={`Opacity ${layer.name}`}
                className="flex-1"
              />
              <span className="text-xs font-semibold w-10 text-right">{Math.round(layer.opacity * 100)}%</span>
            </label>

            {onVariableChange && (
              <input
                type="text"
                value={layer.variable || ''}
                onChange={(e) => onVariableChange(layer.id, e.target.value)}
                placeholder="Variable (optional)"
                className="w-full px-2 py-1 border border-gray-300 rounded-md text-xs"
              />
            )}
          </div>
        </div>
      ))}
    </div>
  )
}
