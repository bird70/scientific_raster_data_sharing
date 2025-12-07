/**
 * Main explorer page with map and data visualization
 */

import { useState, useCallback, useEffect } from 'react';
import { SearchPanel } from '../components/SearchPanel';
import { DatasetCard } from '../components/DatasetCard';
import { MapViewer } from '../components/MapViewer';
import { TimeSlider } from '../components/TimeSlider';
import { TimeseriesChart } from '../components/TimeseriesChart';
import { VariableSelector } from '../components/VariableSelector';
import { useTimeAnimation } from '../hooks/useTimeAnimation';
import { useTimeseries } from '../hooks/useTimeseries';
import { useAppStore } from '../store';
import { usePreferencesStore } from '../store/preferences';
import { ErrorNotice } from '../components/ErrorNotice';
import type { Dataset } from '../types';

export function Explorer() {
  const [showDatasetCard, setShowDatasetCard] = useState(false);
  const [selectedVariable, setSelectedVariable] = useState<string | null>(null);
  const [showSearchPanel, setShowSearchPanel] = useState(false);
  const {
    selectedDataset,
    setSelectedDataset,
    selectedPoint,
    setSelectedPoint,
    currentTimeStep,
    setCurrentTimeStep,
  } = useAppStore();

  // Timeseries hook
  const {
    data: timeseriesData,
    isLoading: isLoadingTimeseries,
    error: timeseriesError,
    lastError: timeseriesLastError,
    fetchTimeseries,
    exportData,
    clearData: clearTimeseriesData,
  } = useTimeseries();
  const colorScheme = usePreferencesStore((state) => state.colorScheme);

  // Generate mock time steps for demonstration
  // In production, these would come from the dataset metadata
  let timeSteps: string[] = [];
  if (selectedDataset) {
    timeSteps = generateMockTimeSteps(selectedDataset);
    // Defensive: ensure valid time range for API calls
    if (
      selectedDataset.temporal?.start &&
      selectedDataset.temporal?.end &&
      new Date(selectedDataset.temporal.start) > new Date(selectedDataset.temporal.end)
    ) {
      // Show error or fallback (could use a toast, modal, etc.)
      console.error('Invalid time range: start date is after end date');
      timeSteps = [];
    }
  }

  const handleDatasetSelect = (dataset: Dataset) => {
    setSelectedDataset(dataset);
    setShowDatasetCard(true);
    setCurrentTimeStep(0); // Reset time step when new dataset selected
    setSelectedVariable(null); // Reset variable selection
    clearTimeseriesData(); // Clear any existing timeseries data
  };

  const handleViewOnMap = () => {
    setShowDatasetCard(false);
  };

  const handleMapClick = (point: { lat: number; lng: number }) => {
    setSelectedPoint(point);
    
    // Automatically fetch timeseries if we have a dataset and variable
    if (selectedDataset && selectedVariable) {
      fetchTimeseries(point, selectedDataset, selectedVariable);
    }
  };

  // Auto-fetch timeseries when variable changes (if point is already selected)
  useEffect(() => {
    if (selectedPoint && selectedDataset && selectedVariable) {
      fetchTimeseries(selectedPoint, selectedDataset, selectedVariable);
    }
  }, [selectedVariable, selectedPoint, selectedDataset, fetchTimeseries]);

  const handleTimeStepChange = useCallback(
    (step: number | ((prev: number) => number)) => {
      if (typeof step === 'function') {
        setCurrentTimeStep(step(currentTimeStep));
      } else {
        setCurrentTimeStep(step);
      }
    },
    [currentTimeStep, setCurrentTimeStep]
  );

  // Time animation hook
  const { isPlaying, togglePlayPause } = useTimeAnimation({
    timeSteps,
    currentStep: currentTimeStep,
    onStepChange: handleTimeStepChange,
    speed: 1000, // 1 second per step
    loop: true,
  });

  return (
    <div className="h-full flex flex-col lg:flex-row">
      {/* Mobile menu button with tooltip */}
      <button
        onClick={() => setShowSearchPanel(!showSearchPanel)}
        className="lg:hidden fixed top-20 left-4 z-30 bg-white rounded-lg shadow-lg p-3 hover:bg-blue-50 transition-colors group"
        aria-label="Toggle search panel"
        title="Toggle search panel"
      >
        <span className="absolute left-full ml-2 px-2 py-1 bg-gray-900 text-white text-xs rounded opacity-0 group-hover:opacity-100 transition-opacity whitespace-nowrap pointer-events-none">
          {showSearchPanel ? 'Close' : 'Search'}
        </span>
        <svg
          className="w-6 h-6 text-gray-700"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          {showSearchPanel ? (
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M6 18L18 6M6 6l12 12"
            />
          ) : (
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M4 6h16M4 12h16M4 18h16"
            />
          )}
        </svg>
      </button>

      {/* Search panel - always visible on desktop as sidebar */}
      <div
        style={{ backgroundColor: '#ffffff' }}
        className="hidden lg:flex lg:flex-col lg:w-[400px] h-full border-r-2 border-gray-300 shadow-2xl overflow-hidden flex-shrink-0"
      >
        <SearchPanel onDatasetSelect={handleDatasetSelect} />
      </div>

      {/* Search panel - mobile overlay */}
      <div
        style={{ backgroundColor: '#ffffff' }}
        className={`
          ${showSearchPanel ? 'translate-x-0' : '-translate-x-full'}
          lg:hidden
          fixed
          inset-y-0 left-0
          w-[90%]
          border-r-2 border-gray-300 shadow-2xl
          overflow-hidden flex-shrink-0
          transition-transform duration-300 ease-in-out
          z-20
        `}
      >
        <SearchPanel onDatasetSelect={(dataset) => {
          handleDatasetSelect(dataset);
          setShowSearchPanel(false); // Close panel on mobile after selection
        }} />
      </div>

      {/* Overlay for mobile when search panel is open */}
      {showSearchPanel && (
        <div
          className="lg:hidden fixed inset-0 bg-black bg-opacity-50 z-10"
          onClick={() => setShowSearchPanel(false)}
        />
      )}

      {/* Map and visualization area */}
      <div className="flex-1 flex flex-col overflow-hidden">
        {/* Map container */}
        <div className="flex-1 min-h-[300px] md:min-h-0 bg-gray-100" style={{ position: 'relative', minHeight: '500px' }}>
          {/* Dataset card overlay with better backdrop */}
          {showDatasetCard && selectedDataset && (
            <div className="absolute inset-0 bg-black/60 backdrop-blur-sm flex items-center justify-center z-10 p-8">
              <div className="max-w-2xl w-full max-h-full overflow-y-auto">
                <div className="relative">
                  <button
                    onClick={() => setShowDatasetCard(false)}
                    className="absolute -top-2 -right-2 bg-white rounded-full p-2 shadow-lg hover:bg-red-50 transition-colors z-20 group"
                    aria-label="Close"
                    title="Close dataset details"
                  >
                    <span className="absolute right-full mr-2 px-2 py-1 bg-gray-900 text-white text-xs rounded opacity-0 group-hover:opacity-100 transition-opacity whitespace-nowrap pointer-events-none">
                      Close
                    </span>
                    <svg
                      className="w-5 h-5 text-gray-600"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        strokeLinecap="round"
                        strokeLinejoin="round"
                        strokeWidth={2}
                        d="M6 18L18 6M6 6l12 12"
                      />
                    </svg>
                  </button>
                  <DatasetCard
                    dataset={selectedDataset}
                    onViewOnMap={handleViewOnMap}
                  />
                </div>
              </div>
            </div>
          )}

          {/* Map viewer */}
          <MapViewer
            dataset={selectedDataset}
            onPointClick={handleMapClick}
            selectedPoint={selectedPoint}
            currentTimeStep={currentTimeStep}
            timeSteps={timeSteps}
          />
        </div>

        {/* Time slider */}
        {selectedDataset && timeSteps.length > 0 && (
          <TimeSlider
            timeSteps={timeSteps}
            currentStep={currentTimeStep}
            onChange={setCurrentTimeStep}
            isPlaying={isPlaying}
            onPlayPause={togglePlayPause}
          />
        )}

        {/* Timeseries panel - responsive */}
        <div className="h-96 md:h-80 bg-white border-t border-gray-200 flex flex-col md:flex-row">
          {/* Variable selector sidebar */}
          {selectedDataset && (
            <div className="w-full md:w-64 border-b md:border-b-0 md:border-r border-gray-200 p-4 flex-shrink-0">
              <VariableSelector
                dataset={selectedDataset}
                selectedVariable={selectedVariable}
                onVariableSelect={setSelectedVariable}
              />
              
              {/* Instructions - hidden on mobile to save space */}
              <div className="hidden md:block mt-4 p-3 bg-blue-50 rounded-md">
                <p className="text-xs text-blue-800 font-medium mb-1">
                  How to extract timeseries:
                </p>
                <ol className="text-xs text-blue-700 space-y-1">
                  <li>1. Select a variable above</li>
                  <li>2. Click on the map</li>
                  <li>3. View the timeseries chart</li>
                </ol>
              </div>
              
              {/* Error display */}
              {timeseriesError && (
                <div className="mt-4">
                  <ErrorNotice
                    title="Timeseries request failed"
                    message={timeseriesError}
                    correlationId={timeseriesLastError?.correlationId}
                    onRetry={
                      timeseriesLastError?.retryable &&
                      selectedPoint &&
                      selectedDataset &&
                      selectedVariable
                        ? () => fetchTimeseries(selectedPoint, selectedDataset, selectedVariable)
                        : undefined
                    }
                  />
                </div>
              )}
            </div>
          )}
          
          {/* Chart area */}
          <div className="flex-1 min-h-[200px]">
            <TimeseriesChart
              data={timeseriesData}
              isLoading={isLoadingTimeseries}
              onExport={exportData}
              colorScheme={colorScheme}
            />
          </div>
        </div>
      </div>
    </div>
  );
}

// Helper function to generate mock time steps
// In production, this would come from dataset metadata
function generateMockTimeSteps(dataset: Dataset): string[] {
  if (!dataset?.temporal?.start || !dataset?.temporal?.end) {
    // Defensive: missing temporal info, return empty array or fallback
    return [];
  }
  const steps: string[] = [];
  const start = new Date(dataset.temporal.start);
  const end = new Date(dataset.temporal.end);
  // Generate daily steps for demonstration
  const current = new Date(start);
  let count = 0;
  const maxSteps = 30; // Limit to 30 steps for demo
  while (current <= end && count < maxSteps) {
    steps.push(current.toISOString());
    current.setDate(current.getDate() + 1);
    count++;
  }
  return steps.length > 0 ? steps : [start.toISOString()];
}
