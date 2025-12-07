/**
 * Timeseries chart component using Plotly.js
 */

import { useMemo, useState, useEffect } from 'react';
import Plot from 'react-plotly.js';
import type { TimeseriesData } from '../types';
import type { ColorScheme } from '../store/preferences';
import { decimateTimeseries, checkRenderThreshold, truncateToMax } from '../utils/plotlyPerformance';

interface TimeseriesChartProps {
  data: TimeseriesData | null;
  isLoading?: boolean;
  onExport?: (format: 'csv' | 'json') => void;
  colorScheme?: ColorScheme;
}

/**
 * Performance warning banner component with auto-dismiss
 * Using component with key ensures it remounts and resets timer for new warnings
 */
function PerformanceWarningBanner({ message }: { message: string }) {
  const [visible, setVisible] = useState(true);

  useEffect(() => {
    const timer = setTimeout(() => setVisible(false), 5000);
    return () => clearTimeout(timer);
  }, []);

  if (!visible) return null;

  return (
    <div className="absolute top-0 left-0 right-0 bg-yellow-50 border-b border-yellow-200 px-4 py-2 z-20 flex items-center justify-between">
      <div className="flex items-center space-x-2">
        <svg className="w-5 h-5 text-yellow-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
        </svg>
        <span className="text-sm text-yellow-800">{message}</span>
      </div>
      <button
        onClick={() => setVisible(false)}
        className="text-yellow-600 hover:text-yellow-800"
        aria-label="Dismiss warning"
      >
        <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
        </svg>
      </button>
    </div>
  );
}

export function TimeseriesChart({ data, isLoading = false, onExport, colorScheme = 'default' }: TimeseriesChartProps) {
  // Calculate performance warning from data (derived state)
  const performanceWarning = useMemo(() => {
    if (!data?.series) return null;

    const totalPoints = data.series.reduce((sum, s) => sum + s.times.length, 0);
    const threshold = checkRenderThreshold(totalPoints);

    return threshold.shouldWarn && threshold.message ? threshold.message : null;
  }, [data]);

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
    const series = data?.series || [];
    if (series.length === 0) return [];

    return series.map((s, idx) => {
      let times = s.times;
      let values = s.values;

      // Check performance threshold
      const totalPoints = times.length;
      const threshold = checkRenderThreshold(totalPoints);

      if (threshold.shouldDecimate) {
        // Truncate if exceeds absolute max
        times = truncateToMax(times);
        values = truncateToMax(values);

        // Apply decimation
        const decimated = decimateTimeseries(times, values);
        times = decimated.times;
        values = decimated.values;
      }

      return {
        x: times,
        y: values,
        type: 'scatter' as const,
        mode: 'lines+markers' as const,
        name: s.label || s.variable || `Series ${idx + 1}`,
        line: {
          color: palette.line,
          width: 2,
        },
        marker: {
          color: palette.marker,
          size: 4,
        },
        hovertemplate:
          '<b>%{fullData.name}</b><br>' +
          'Time: %{x}<br>' +
          'Value: %{y:.4f}' + (s.units ? ` ${s.units}` : '') +
          '<extra></extra>',
      };
    });
  }, [data, palette]);

  const layout = useMemo(() => ({
    title: {
      text: 'Timeseries Data',
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
        text: (() => {
          const first = data?.series?.[0]
          if (!first) return 'Value'
          if (first.units && (first.variable || first.label)) {
            return `${first.variable || first.label} (${first.units})`
          }
          return first.variable || first.label || 'Value'
        })(),
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
      filename: `timeseries_${data?.series?.[0]?.variable || 'data'}`,
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

  const hasSeries = data?.series && data.series.length > 0 && data.series.some((s) => s.times.length > 0)

  if (!hasSeries) {
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
      {/* Performance warning banner - key ensures it remounts on new warning */}
      {performanceWarning && (
        <PerformanceWarningBanner 
          key={performanceWarning} 
          message={performanceWarning} 
        />
      )}

      {/* Chart container */}
      <div className="w-full h-full" style={{ paddingTop: performanceWarning ? '3rem' : '0' }}>
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
      {(data.metadata || data.series[0]?.metadata || data.series[0]) && (
        <div className="absolute bottom-4 left-4 bg-white bg-opacity-90 backdrop-blur-sm rounded-lg shadow-sm px-3 py-2 border border-gray-200 max-w-xs z-10">
          <div className="text-xs space-y-1">
            {data.metadata?.coordinates && (
              <p className="text-gray-600">
                <span className="font-medium">Location:</span>{' '}
                {data.metadata.coordinates.lat.toFixed(4)}, {data.metadata.coordinates.lng.toFixed(4)}
              </p>
            )}
            <p className="text-gray-600">
              <span className="font-medium">Points:</span> {data.series.reduce((acc, s) => acc + s.times.length, 0)}
            </p>
          </div>
        </div>
      )}
    </div>
  );
}
