import axios from 'axios'
import type { TimeseriesData } from '@/types'
import { ApiError, normalizeApiError } from '@/utils/errors'

export interface TimeseriesRequest {
  lon: number
  lat: number
  start: string
  end: string
  variables: string[]
  datasetIds: string[]
}

export interface TimeseriesApiResponse {
  series: Array<{
    datasetId: string
    variable: string
    units?: string
    times: string[]
    values: number[]
  }>
}

const rawBase = (import.meta as ImportMeta & { env: { VITE_API_BASE_URL?: string } }).env.VITE_API_BASE_URL
const API_BASE = rawBase && !rawBase.toLowerCase().includes('placeholder') ? rawBase.replace(/\/$/, '') : ''

const client = axios.create({
  baseURL: API_BASE || undefined,
  headers: { 'Content-Type': 'application/json' },
  timeout: 30000,
})

export async function fetchTimeseries(payload: TimeseriesRequest): Promise<TimeseriesData> {
  try {
    const res = await client.post<TimeseriesApiResponse>('/api/v1/timeseries', payload)
    const series = (res.data.series || []).map((s) => ({
      datasetId: s.datasetId,
      variable: s.variable,
      units: s.units,
      times: s.times,
      values: s.values,
    }))

    return { series }
  } catch (err) {
    const normalized = normalizeApiError(err)
    throw new ApiError(normalized)
  }
}
