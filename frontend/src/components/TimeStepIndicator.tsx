/**
 * Time step indicator overlay for the map
 */

interface TimeStepIndicatorProps {
  currentTime: string; // ISO 8601 date string
  totalSteps?: number;
  currentStep?: number;
}

export function TimeStepIndicator({
  currentTime,
  totalSteps,
  currentStep,
}: TimeStepIndicatorProps) {
  const formatDateTime = (dateString: string) => {
    try {
      const date = new Date(dateString);
      return date.toLocaleString('en-US', {
        year: 'numeric',
        month: 'short',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
      });
    } catch {
      return dateString;
    }
  };

  return (
    <div className="absolute top-4 right-4 bg-white bg-opacity-90 backdrop-blur-sm rounded-lg shadow-lg px-4 py-3 border border-gray-200">
      <div className="flex items-center space-x-3">
        {/* Calendar icon */}
        <div className="flex-shrink-0">
          <svg
            className="w-6 h-6 text-blue-600"
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
        </div>

        {/* Time info */}
        <div>
          <p className="text-xs text-gray-500 font-medium">Current Time</p>
          <p className="text-sm font-semibold text-gray-900">
            {formatDateTime(currentTime)}
          </p>
          {totalSteps !== undefined && currentStep !== undefined && (
            <p className="text-xs text-gray-500 mt-0.5">
              Step {currentStep + 1} of {totalSteps}
            </p>
          )}
        </div>
      </div>
    </div>
  );
}
