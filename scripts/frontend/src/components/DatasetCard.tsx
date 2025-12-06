/**
 * Dataset card component for displaying dataset information
 */

import type { Dataset } from '../types';

interface DatasetCardProps {
  dataset: Dataset;
  onViewOnMap?: () => void;
}

export function DatasetCard({ dataset, onViewOnMap }: DatasetCardProps) {
  const formatDate = (date: Date | string) => {
    const d = typeof date === 'string' ? new Date(date) : date;
    return d.toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
    });
  };

  const formatBbox = (bbox: [number, number, number, number]) => {
    return `[${bbox[0].toFixed(2)}, ${bbox[1].toFixed(2)}, ${bbox[2].toFixed(2)}, ${bbox[3].toFixed(2)}]`;
  };

  return (
    <div style={{ backgroundColor: '#ffffff' }} className="rounded-lg shadow-2xl border-2 border-gray-300 overflow-hidden">
      {/* Header */}
      <div className="bg-gradient-to-r from-blue-500 to-blue-600 px-6 py-4">
        <h3 className="text-lg font-semibold text-white">
          {dataset.title || dataset.id}
        </h3>
        <p className="text-sm text-blue-100 mt-1">{dataset.collection}</p>
      </div>

      {/* Content */}
      <div className="p-6 space-y-4">
        {/* Description */}
        {dataset.description && (
          <div>
            <h4 className="text-sm font-medium text-gray-700 mb-1">
              Description
            </h4>
            <p className="text-sm text-gray-600">{dataset.description}</p>
          </div>
        )}

        {/* Temporal extent */}
        <div>
          <h4 className="text-sm font-medium text-gray-700 mb-2">
            Temporal Coverage
          </h4>
          <div className="flex items-center space-x-2 text-sm text-gray-600">
            <svg
              className="w-4 h-4 flex-shrink-0 text-gray-400"
              style={{ width: '1rem', height: '1rem', flexShrink: 0 }}
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"
              />
            </svg>
            <span>
              {dataset.temporal?.start ? formatDate(dataset.temporal.start) : 'Unknown'} -{' '}
              {dataset.temporal?.end ? formatDate(dataset.temporal.end) : 'Unknown'}
            </span>
          </div>
          <p className="text-xs text-gray-500 mt-1">
            Interval: {dataset.temporal?.interval ?? 'Unknown'}
          </p>
        </div>

        {/* Spatial extent */}
        <div>
          <h4 className="text-sm font-medium text-gray-700 mb-2">
            Spatial Extent
          </h4>
          <div className="flex items-center space-x-2 text-sm text-gray-600">
            <svg
              className="w-4 h-4 flex-shrink-0 text-gray-400"
              style={{ width: '1rem', height: '1rem', flexShrink: 0 }}
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M3.055 11H5a2 2 0 012 2v1a2 2 0 002 2 2 2 0 012 2v2.945M8 3.935V5.5A2.5 2.5 0 0010.5 8h.5a2 2 0 012 2 2 2 0 104 0 2 2 0 012-2h1.064M15 20.488V18a2 2 0 012-2h3.064M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
              />
            </svg>
            <span className="font-mono text-xs">
              {dataset.spatial?.bbox ? formatBbox(dataset.spatial.bbox) : 'Unknown'}
            </span>
          </div>
          <p className="text-xs text-gray-500 mt-1">CRS: {dataset.spatial?.crs ?? 'Unknown'}</p>
        </div>

        {/* Variables */}
        {dataset.variables && dataset.variables.length > 0 && (
          <div>
            <h4 className="text-sm font-medium text-gray-700 mb-2">
              Available Variables ({dataset.variables.length})
            </h4>
            <div className="flex flex-wrap gap-2">
              {dataset.variables.slice(0, 6).map((variable, index) => (
                <span
                  key={index}
                  className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800"
                  title={`${variable.longName} (${variable.units})`}
                >
                  {variable.name}
                </span>
              ))}
              {dataset.variables.length > 6 && (
                <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-600">
                  +{dataset.variables.length - 6} more
                </span>
              )}
            </div>
          </div>
        )}

        {/* Assets */}
        <div>
          <h4 className="text-sm font-medium text-gray-700 mb-2">Assets</h4>
          <div className="space-y-1">
            {dataset.assets.cog && (
              <div className="flex items-center space-x-2 text-xs text-gray-600">
                <svg
                  className="w-3 h-3 flex-shrink-0 text-green-500"
                  style={{ width: '0.75rem', height: '0.75rem', flexShrink: 0 }}
                  fill="currentColor"
                  viewBox="0 0 20 20"
                >
                  <path
                    fillRule="evenodd"
                    d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"
                    clipRule="evenodd"
                  />
                </svg>
                <span>COG tiles available</span>
              </div>
            )}
            {dataset.assets.zarr && (
              <div className="flex items-center space-x-2 text-xs text-gray-600">
                <svg
                  className="w-3 h-3 flex-shrink-0 text-green-500"
                  style={{ width: '0.75rem', height: '0.75rem', flexShrink: 0 }}
                  fill="currentColor"
                  viewBox="0 0 20 20"
                >
                  <path
                    fillRule="evenodd"
                    d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"
                    clipRule="evenodd"
                  />
                </svg>
                <span>Zarr timeseries available</span>
              </div>
            )}
          </div>
        </div>
      </div>

      {/* Footer with action button */}
      {onViewOnMap && (
        <div className="bg-gray-50 px-6 py-4 border-t border-gray-200">
          <button
            onClick={onViewOnMap}
            className="w-full px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white font-medium rounded-md transition-colors flex items-center justify-center space-x-2"
          >
            <svg
              className="w-5 h-5 flex-shrink-0"
              style={{ width: '1.25rem', height: '1.25rem', flexShrink: 0 }}
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M9 20l-5.447-2.724A1 1 0 013 16.382V5.618a1 1 0 011.447-.894L9 7m0 13l6-3m-6 3V7m6 10l4.553 2.276A1 1 0 0021 18.382V7.618a1 1 0 00-.553-.894L15 4m0 13V4m0 0L9 7"
              />
            </svg>
            <span>View on Map</span>
          </button>
        </div>
      )}
    </div>
  );
}
