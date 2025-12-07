import axios from 'axios'
import type { StacSearchRequest, StacSearchResponse } from '../types'
import { normalizeApiError, ApiError } from '../utils/errors'

const API_BASE = (import.meta as ImportMeta & { env: { VITE_API_BASE_URL?: string } }).env
  .VITE_API_BASE_URL || 'http://localhost:8000'

const client = axios.create({
  baseURL: API_BASE.replace(/\/$/, ''),
  headers: { 'Content-Type': 'application/json' },
  timeout: 30000,
})

export async function searchStac(payload: StacSearchRequest): Promise<StacSearchResponse> {
  try {
    const response = await client.post<StacSearchResponse>('/api/v1/stac/search', payload)
    return response.data
  } catch (err) {
    const normalized = normalizeApiError(err)
    throw new ApiError(normalized)
  }
}
