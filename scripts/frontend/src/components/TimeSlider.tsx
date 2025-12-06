/**
 * Time slider component for navigating temporal data
 */

import { useState, useEffect } from 'react';

interface TimeSliderProps {
  timeSteps: string[]; // ISO 8601 date strings
  currentStep: number;
  onChange: (step: number) => void;
  isPlaying?: boolean;
  onPlayPause?: () => void;
}

export function TimeSlider({
  timeSteps,
  currentStep,
  onChange,
  isPlaying = false,
  onPlayPause,
}: TimeSliderProps) {
  const [localStep, setLocalStep] = useState(currentStep);

  useEffect(() => {
    setLocalStep(currentStep);
  }, [currentStep]);

  const handleSliderChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const step = parseInt(e.target.value, 10);
    setLocalStep(step);
    onChange(step);
  };

  const handleStepForward = () => {
    if (localStep < timeSteps.length - 1) {
      const newStep = localStep + 1;
      setLocalStep(newStep);
      onChange(newStep);
    }
  };

  const handleStepBackward = () => {
    if (localStep > 0) {
      const newStep = localStep - 1;
      setLocalStep(newStep);
      onChange(newStep);
    }
  };

  const formatDate = (dateString: string) => {
    try {
      const date = new Date(dateString);
      return date.toLocaleDateString('en-US', {
        year: 'numeric',
        month: 'short',
        day: 'numeric',
      });
    } catch {
      return dateString;
    }
  };

  if (timeSteps.length === 0) {
    return (
      <div className="bg-white border-t border-gray-200 p-4">
        <p className="text-sm text-gray-500 text-center">
          No temporal data available
        </p>
      </div>
    );
  }

  return (
    <div className="bg-white border-t border-gray-200 p-4">
      <div className="max-w-4xl mx-auto">
        {/* Current time display */}
        <div className="flex items-center justify-between mb-3">
          <div>
            <p className="text-xs text-gray-500">Current Time Step</p>
            <p className="text-sm font-medium text-gray-900">
              {formatDate(timeSteps[localStep])}
            </p>
          </div>
          <div className="text-xs text-gray-500">
            {localStep + 1} / {timeSteps.length}
          </div>
        </div>

        {/* Slider */}
        <div className="mb-3">
          <input
            type="range"
            min="0"
            max={timeSteps.length - 1}
            value={localStep}
            onChange={handleSliderChange}
            className="w-full h-2 bg-gray-200 rounded-lg appearance-none cursor-pointer accent-blue-600"
          />
        </div>

        {/* Controls */}
        <div className="flex items-center justify-center space-x-2">
          {/* Step backward */}
          <button
            onClick={handleStepBackward}
            disabled={localStep === 0}
            className="p-2 rounded-md bg-gray-100 hover:bg-gray-200 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            aria-label="Previous time step"
          >
            <svg
              className="w-5 h-5 text-gray-700"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M15 19l-7-7 7-7"
              />
            </svg>
          </button>

          {/* Play/Pause */}
          {onPlayPause && (
            <button
              onClick={onPlayPause}
              className="p-2 rounded-md bg-blue-600 hover:bg-blue-700 text-white transition-colors"
              aria-label={isPlaying ? 'Pause' : 'Play'}
            >
              {isPlaying ? (
                <svg
                  className="w-5 h-5"
                  fill="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path d="M6 4h4v16H6V4zm8 0h4v16h-4V4z" />
                </svg>
              ) : (
                <svg
                  className="w-5 h-5"
                  fill="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path d="M8 5v14l11-7z" />
                </svg>
              )}
            </button>
          )}

          {/* Step forward */}
          <button
            onClick={handleStepForward}
            disabled={localStep === timeSteps.length - 1}
            className="p-2 rounded-md bg-gray-100 hover:bg-gray-200 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            aria-label="Next time step"
          >
            <svg
              className="w-5 h-5 text-gray-700"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M9 5l7 7-7 7"
              />
            </svg>
          </button>
        </div>
      </div>
    </div>
  );
}
