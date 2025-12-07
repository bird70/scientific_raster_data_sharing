import { create } from 'zustand'
import type { TimeseriesData, LatLng, Dataset } from '@/types'

interface TimeseriesState {
  data: TimeseriesData | null
  isLoading: boolean
  error: string | null
  lastRequest?: { point: LatLng; dataset: Dataset; variable: string }
  setData: (data: TimeseriesData | null) => void
  setLoading: (loading: boolean) => void
  setError: (message: string | null) => void
  setLastRequest: (req?: { point: LatLng; dataset: Dataset; variable: string }) => void
  reset: () => void
}

export const useTimeseriesStore = create<TimeseriesState>((set) => ({
  data: null,
  isLoading: false,
  error: null,
  lastRequest: undefined,
  setData: (data) => set({ data }),
  setLoading: (isLoading) => set({ isLoading }),
  setError: (error) => set({ error }),
  setLastRequest: (req) => set({ lastRequest: req }),
  reset: () => set({ data: null, isLoading: false, error: null, lastRequest: undefined }),
}))
