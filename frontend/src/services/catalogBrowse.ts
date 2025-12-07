import axios from 'axios'
import type { CollectionNode, Dataset } from '@/types'
import { ApiError, normalizeApiError } from '@/utils/errors'

const rawBase = (import.meta as ImportMeta & { env: { VITE_API_BASE_URL?: string } }).env.VITE_API_BASE_URL
const API_BASE = rawBase && !rawBase.toLowerCase().includes('placeholder') ? rawBase : ''

const client = axios.create({
  baseURL: API_BASE ? API_BASE.replace(/\/$/, '') : undefined,
  headers: { 'Content-Type': 'application/json' },
  timeout: 30000,
})

function hydrateDataset(raw: Record<string, unknown>): Dataset {
  return {
    ...raw,
    temporal: {
      start: new Date(raw.temporal?.start ?? raw.temporalExtent?.start ?? raw.start ?? Date.now()),
      end: new Date(raw.temporal?.end ?? raw.temporalExtent?.end ?? raw.end ?? Date.now()),
      interval: raw.temporal?.interval ?? raw.interval ?? 'P1D',
    },
    spatial: {
      bbox: raw.spatial?.bbox ?? raw.bbox ?? [-180, -90, 180, 90],
      crs: raw.spatial?.crs ?? raw.crs ?? 'EPSG:4326',
    },
  }
}

function hydrateCollection(raw: Record<string, unknown>): CollectionNode {
  return {
    id: String(raw.id),
    title: (raw.title as string) ?? String(raw.id),
    description: (raw.description as string) ?? '',
    childCollections: (raw.childCollections as string[]) ?? (raw.children as string[]) ?? [],
    items: Array.isArray(raw.items) ? raw.items.map((item) => hydrateDataset(item as Record<string, unknown>)) : [],
  }
}

export async function fetchRootCollections(): Promise<CollectionNode[]> {
  try {
    const res = await client.get('/api/v1/collections')
    return (res.data?.collections ?? res.data ?? []).map(hydrateCollection)
  } catch (err) {
    const normalized = normalizeApiError(err)
    throw new ApiError(normalized)
  }
}

export async function fetchCollection(id: string): Promise<CollectionNode> {
  try {
    const res = await client.get(`/api/v1/collections/${id}`)
    return hydrateCollection(res.data)
  } catch (err) {
    const normalized = normalizeApiError(err)
    throw new ApiError(normalized)
  }
}
