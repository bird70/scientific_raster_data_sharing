/**
 * Timeseries chart component using Plotly.js
 */

import { useMemo } from 'react';
import Plot from 'react-plotly.js';
import type { TimeseriesData } from '../types';
import type { ColorScheme } from '../store/preferences';

interface TimeseriesChartProps {
  data: TimeseriesData | null;
  isLoading?: boolean;
  onExport?: (format: 'csv' | 'json') => void;
  colorScheme?: ColorScheme;
}

export function TimeseriesChart({ data, isLoading = false, onExport, colorScheme = 'default' }: TimeseriesChartProps) {
  const palette = useMemo(() => {
    if (colorScheme === 'high-contrast') {
      return {
        line: '#111827',
        marker: '#f97316',
        grid: '#d1d5db',
        background: '#f9fafb',
        paper: '#ffffff',
      };
    }
    return {
      line: '#3b82f6',
      marker: '#3b82f6',
      grid: '#f3f4f6',
      background: 'white',
      paper: 'white',
    };
  }, [colorScheme]);

  const plotData = useMemo(() => {
    if (!data || data.times.length === 0) return [];

    return [{
      x: data.times,
      y: data.values,
      type: 'scatter' as const,
      mode: 'lines+markers' as const,
      name: data.metadata?.variable || 'Value',
      line: {
        color: palette.line,
        width: 2,
      },
      marker: {
        color: palette.marker,
        size: 4,
      },
      hovertemplate: '<b>%{fullData.name}</b><br>' +
                    'Time: %{x}<br>' +
                    'Value: %{y:.4f}' + (data.metadata?.units ? ` ${data.metadata.units}` : '') +
                    '<extra></extra>',
    }];
  }, [data, palette]);

  const layout = useMemo(() => ({
    title: {
      text: data?.metadata?.long_name || data?.metadata?.variable || 'Timeseries Data',
      font: { size: 16 },
    },
    xaxis: {
      title: { text: 'Time' },
      type: 'date' as const,
      showgrid: true,
      gridcolor: palette.grid,
    },
    yaxis: {
      title: {
        text: data?.metadata?.units 
          ? `${data?.metadata.variable || 'Value'} (${data.metadata.units})`
          : data?.metadata?.variable || 'Value',
      },
      showgrid: true,
      gridcolor: palette.grid,
    },
    plot_bgcolor: palette.background,
    paper_bgcolor: palette.paper,
    margin: { l: 60, r: 40, t: 60, b: 60 },
    showlegend: false,
    hovermode: 'x unified' as const,
    autosize: true,
  }), [data, palette]);

  const config = useMemo(() => ({
    responsive: true,
    displayModeBar: true,
    modeBarButtonsToRemove: [
      'pan2d' as const,
      'lasso2d' as const,
      'select2d' as const,
      'autoScale2d' as const,
      'hoverClosestCartesian' as const,
      'hoverCompareCartesian' as const,
      'toggleSpikelines' as const,
    ],
    displaylogo: false,
    toImageButtonOptions: {
      format: 'png' as const,
      filename: `timeseries_${data?.metadata?.variable || 'data'}`,
      height: 500,
      width: 800,
      scale: 1,
    },
  }), [data]);

  if (isLoading) {
    return (
      <div className="h-full flex items-center justify-center bg-white">
        <div className="text-center">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600 mx-auto mb-4"></div>
          <p className="text-sm text-gray-600">Loading timeseries data...</p>
        </div>
      </div>
    );
  }

  if (!data || data.times.length === 0) {
    return (
      <div className="h-full flex items-center justify-center bg-white">
        <div className="text-center text-gray-500">
          <svg
            className="w-16 h-16 flex-shrink-0 mx-auto mb-4 text-gray-400"
            style={{ width: '4rem', height: '4rem', flexShrink: 0 }}
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M7 12l3-3 3 3 4-4M8 21l4-4 4 4M3 4h18M4 4h16v12a1 1 0 01-1 1H5a1 1 0 01-1-1V4z"
            />
          </svg>
          <p className="text-lg font-medium mb-2">No Timeseries Data</p>
          <p className="text-sm">
            Click on the map to extract timeseries data for a location
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="h-full bg-white relative">
      {/* Chart container */}
      <div className="w-full h-full">
        <Plot
          data={plotData}
          layout={layout}
          config={config}
          style={{ width: '100%', height: '100%' }}
          useResizeHandler={true}
        />
      </div>
      
      {/* Export buttons */}
      {onExport && (
        <div className="absolute top-4 right-4 flex space-x-2 z-10">
          <button
            onClick={() => onExport('csv')}
            className="px-3 py-1 text-xs bg-white border border-gray-300 rounded hover:bg-gray-50 transition-colors shadow-sm"
            title="Export as CSV"
          >
            CSV
          </button>
          <button
            onClick={() => onExport('json')}
            className="px-3 py-1 text-xs bg-white border border-gray-300 rounded hover:bg-gray-50 transition-colors shadow-sm"
            title="Export as JSON"
          >
            JSON
          </button>
        </div>
      )}
      
      {/* Metadata info */}
      {data.metadata && (
        <div className="absolute bottom-4 left-4 bg-white bg-opacity-90 backdrop-blur-sm rounded-lg shadow-sm px-3 py-2 border border-gray-200 max-w-xs z-10">
          <div className="text-xs space-y-1">
            {data.metadata.coordinates && (
              <p className="text-gray-600">
                <span className="font-medium">Location:</span>{' '}
                {data.metadata.coordinates.lat.toFixed(4)}, {data.metadata.coordinates.lng.toFixed(4)}
              </p>
            )}
            {data.metadata.collection && (
              <p className="text-gray-600">
                <span className="font-medium">Collection:</span> {data.metadata.collection}
              </p>
            )}
            <p className="text-gray-600">
              <span className="font-medium">Points:</span> {data.times.length}
            </p>
          </div>
        </div>
      )}
    </div>
  );
}
