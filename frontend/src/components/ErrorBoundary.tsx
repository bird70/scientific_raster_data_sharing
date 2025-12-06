/**
 * Error boundary component to catch React errors
 */

import { Component, ReactNode, ErrorInfo } from 'react';

interface Props {
  children: ReactNode;
}

interface State {
  hasError: boolean;
  error: Error | null;
  errorInfo: ErrorInfo | null;
}

export class ErrorBoundary extends Component<Props, State> {
  constructor(props: Props) {
    super(props);
    this.state = {
      hasError: false,
      error: null,
      errorInfo: null,
    };
  }

  static getDerivedStateFromError(error: Error): Partial<State> {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    // Log error to console for debugging
    console.error('Error caught by boundary:', error, errorInfo);
    
    this.setState({
      error,
      errorInfo,
    });
  }

  handleReset = () => {
    this.setState({
      hasError: false,
      error: null,
      errorInfo: null,
    });
  };

  handleReportIssue = () => {
    const { error, errorInfo } = this.state;
    const errorDetails = `
Error: ${error?.message}
Stack: ${error?.stack}
Component Stack: ${errorInfo?.componentStack}
    `.trim();

    // In production, this would send to an error tracking service
    console.log('Report issue:', errorDetails);
    
    // For now, copy to clipboard
    navigator.clipboard.writeText(errorDetails).then(() => {
      alert('Error details copied to clipboard. Please share with support.');
    });
  };

  render() {
    if (this.state.hasError) {
      return (
        <div className="min-h-screen bg-gray-50 flex items-center justify-center p-4">
          <div className="max-w-2xl w-full bg-white rounded-lg shadow-lg p-8">
            <div className="flex items-center space-x-3 mb-6">
              <div className="flex-shrink-0">
                <svg
                  className="w-12 h-12 text-red-500"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth={2}
                    d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
                  />
                </svg>
              </div>
              <div>
                <h2 className="text-2xl font-bold text-gray-900">
                  Something went wrong
                </h2>
                <p className="text-sm text-gray-600 mt-1">
                  We're sorry for the inconvenience
                </p>
              </div>
            </div>

            <div className="bg-gray-50 rounded-md p-4 mb-6">
              <p className="text-sm font-medium text-gray-900 mb-2">
                Error Details:
              </p>
              <p className="text-sm text-gray-700 font-mono break-all">
                {this.state.error?.message}
              </p>
            </div>

            <div className="flex flex-col sm:flex-row gap-3">
              <button
                onClick={this.handleReset}
                className="flex-1 bg-blue-600 text-white px-6 py-3 rounded-md hover:bg-blue-700 transition-colors font-medium"
              >
                Try Again
              </button>
              <button
                onClick={this.handleReportIssue}
                className="flex-1 bg-gray-200 text-gray-900 px-6 py-3 rounded-md hover:bg-gray-300 transition-colors font-medium"
              >
                Report Issue
              </button>
              <button
                onClick={() => window.location.href = '/'}
                className="flex-1 bg-white border border-gray-300 text-gray-700 px-6 py-3 rounded-md hover:bg-gray-50 transition-colors font-medium"
              >
                Go Home
              </button>
            </div>

            {/* Show stack trace in development */}
            {process.env.NODE_ENV === 'development' && this.state.error && (
              <details className="mt-6">
                <summary className="text-sm font-medium text-gray-700 cursor-pointer hover:text-gray-900">
                  Stack Trace (Development Only)
                </summary>
                <pre className="mt-2 text-xs bg-gray-900 text-gray-100 p-4 rounded-md overflow-auto max-h-64">
                  {this.state.error.stack}
                </pre>
              </details>
            )}
          </div>
        </div>
      );
    }

    return this.props.children;
  }
}
