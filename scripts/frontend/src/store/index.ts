/**
 * Global state management using Zustand
 */

import { create } from 'zustand';
import type { Dataset, LatLng, TimeseriesData } from '../types';

interface AppState {
  // Dataset state
  selectedDataset: Dataset | null;
  setSelectedDataset: (dataset: Dataset | null) => void;

  // Map state
  selectedPoint: LatLng | null;
  setSelectedPoint: (point: LatLng | null) => void;
  
  currentTimeStep: number;
  setCurrentTimeStep: (step: number) => void;

  // Timeseries state
  timeseriesData: TimeseriesData | null;
  setTimeseriesData: (data: TimeseriesData | null) => void;
  
  isLoadingTimeseries: boolean;
  setIsLoadingTimeseries: (loading: boolean) => void;

  // UI state
  sidebarOpen: boolean;
  setSidebarOpen: (open: boolean) => void;
}

export const useAppStore = create<AppState>((set) => ({
  // Dataset state
  selectedDataset: null,
  setSelectedDataset: (dataset) => set({ selectedDataset: dataset }),

  // Map state
  selectedPoint: null,
  setSelectedPoint: (point) => set({ selectedPoint: point }),
  
  currentTimeStep: 0,
  setCurrentTimeStep: (step) => set({ currentTimeStep: step }),

  // Timeseries state
  timeseriesData: null,
  setTimeseriesData: (data) => set({ timeseriesData: data }),
  
  isLoadingTimeseries: false,
  setIsLoadingTimeseries: (loading) => set({ isLoadingTimeseries: loading }),

  // UI state
  sidebarOpen: true,
  setSidebarOpen: (open) => set({ sidebarOpen: open }),
}));
