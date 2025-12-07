import { AxiosError } from 'axios'

export interface NormalizedError {
  message: string
  status?: number
  correlationId?: string
  retryable: boolean
}

export class ApiError extends Error implements NormalizedError {
  status?: number
  correlationId?: string
  retryable: boolean

  constructor(payload: NormalizedError) {
    super(payload.message)
    this.name = 'ApiError'
    this.status = payload.status
    this.correlationId = payload.correlationId
    this.retryable = payload.retryable
    Object.setPrototypeOf(this, ApiError.prototype)
  }
}

export function normalizeApiError(err: unknown): NormalizedError {
  const axiosErr = err as AxiosError<unknown>
  const status = axiosErr.response?.status
  const correlationId = (axiosErr.response?.headers?.['x-correlation-id'] || axiosErr.response?.headers?.['x-request-id']) as string | undefined

  if (axiosErr.code === 'ECONNABORTED') {
    return {
      message: 'Request timed out. Please retry.',
      status,
      correlationId,
      retryable: true,
    }
  }

  if (!axiosErr.response) {
    return {
      message: 'Network error. Check your connection and try again.',
      status,
      correlationId,
      retryable: true,
    }
  }

  const detail = (axiosErr.response?.data as { detail?: unknown } | undefined)?.detail
  const baseMessage = typeof detail === 'string' ? detail : axiosErr.message
  const statusMessage = (() => {
    switch (status) {
      case 400:
        return 'Invalid request. Please check your inputs.'
      case 401:
        return 'Unauthorized. Please sign in again.'
      case 403:
        return 'Forbidden. You may not have access to this resource.'
      case 404:
        return 'Not found. The requested resource could not be located.'
      case 429:
        return 'Too many requests. Please slow down and retry.'
      case 500:
      case 502:
      case 503:
      case 504:
        return 'The service is temporarily unavailable. Please retry shortly.'
      default:
        return 'Unexpected error. Please try again.'
    }
  })()

  const message = baseMessage || statusMessage
  const retryable = !status || [429, 500, 502, 503, 504].includes(status)

  return { message, status, correlationId, retryable }
}

export function formatErrorMessage(normalized: NormalizedError) {
  if (normalized.correlationId) {
    return `${normalized.message} (Ref: ${normalized.correlationId})`
  }
  return normalized.message
}
