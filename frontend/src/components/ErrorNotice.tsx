import { ReactNode } from 'react'

interface ErrorNoticeProps {
  title?: string
  message: string
  correlationId?: string
  onRetry?: () => void
  icon?: ReactNode
}

export function ErrorNotice({
  title = 'Something went wrong',
  message,
  correlationId,
  onRetry,
  icon,
}: ErrorNoticeProps) {
  return (
    <div className="border border-red-200 bg-red-50 text-red-900 rounded-lg p-4 shadow-sm">
      <div className="flex items-start gap-3">
        <div className="mt-0.5 text-red-500">
          {icon ?? (
            <svg
              className="w-5 h-5"
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
          )}
        </div>
        <div className="flex-1 space-y-1">
          <h3 className="font-semibold text-sm">{title}</h3>
          <p className="text-sm leading-5">{message}</p>
          {correlationId && (
            <p className="text-xs text-red-700">Ref: {correlationId}</p>
          )}
          {onRetry && (
            <button
              onClick={onRetry}
              className="mt-2 inline-flex items-center px-3 py-1.5 text-xs font-semibold text-white bg-red-600 rounded-md hover:bg-red-700 focus:outline-none"
            >
              Retry
            </button>
          )}
        </div>
      </div>
    </div>
  )
}
