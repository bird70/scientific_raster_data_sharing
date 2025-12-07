import { create } from 'zustand'

export type BaseMapStyle = 'osm' | 'satellite'
export type ColorScheme = 'default' | 'high-contrast'

export interface SavedSearchFilters {
  dateRange: [string, string] | null
  bbox: [number, number, number, number] | null
  variables: string[]
  collections: string[]
  searchText: string
}

export interface PreferencesState {
  baseMap: BaseMapStyle
  colorScheme: ColorScheme
  layerOrder: string[]
  lastSearch: SavedSearchFilters
  setBaseMap: (baseMap: BaseMapStyle) => void
  setColorScheme: (scheme: ColorScheme) => void
  setLayerOrder: (order: string[]) => void
  setLastSearch: (filters: SavedSearchFilters) => void
}

const PREFERENCES_KEY = 'frontend.preferences.v1'

const defaultPreferences = {
  baseMap: 'osm' as BaseMapStyle,
  colorScheme: 'default' as ColorScheme,
  layerOrder: [] as string[],
  lastSearch: {
    dateRange: null,
    bbox: null,
    variables: [],
    collections: [],
    searchText: '',
  } as SavedSearchFilters,
}

function loadPreferences() {
  if (typeof window === 'undefined') return defaultPreferences

  try {
    const raw = localStorage.getItem(PREFERENCES_KEY)
    if (!raw) return defaultPreferences
    const parsed = typeof raw === 'string' ? JSON.parse(raw) : raw

    return {
      baseMap: (parsed.baseMap as BaseMapStyle) || defaultPreferences.baseMap,
      colorScheme:
        (parsed.colorScheme as ColorScheme) || defaultPreferences.colorScheme,
      layerOrder: Array.isArray(parsed.layerOrder)
        ? (parsed.layerOrder as string[])
        : defaultPreferences.layerOrder,
      lastSearch: {
        dateRange: Array.isArray(parsed.lastSearch?.dateRange)
          ? (parsed.lastSearch.dateRange as [string, string])
          : defaultPreferences.lastSearch.dateRange,
        bbox: Array.isArray(parsed.lastSearch?.bbox)
          ? (parsed.lastSearch.bbox as [number, number, number, number])
          : defaultPreferences.lastSearch.bbox,
        variables: Array.isArray(parsed.lastSearch?.variables)
          ? (parsed.lastSearch.variables as string[])
          : defaultPreferences.lastSearch.variables,
        collections: Array.isArray(parsed.lastSearch?.collections)
          ? (parsed.lastSearch.collections as string[])
          : defaultPreferences.lastSearch.collections,
        searchText:
          typeof parsed.lastSearch?.searchText === 'string'
            ? parsed.lastSearch.searchText
            : defaultPreferences.lastSearch.searchText,
      },
    }
  } catch (err) {
    console.warn('Failed to load preferences, using defaults', err)
    return defaultPreferences
  }
}

function persistPreferences(preferences: {
  baseMap: BaseMapStyle
  colorScheme: ColorScheme
  layerOrder: string[]
  lastSearch: SavedSearchFilters
}) {
  if (typeof window === 'undefined') return
  try {
    localStorage.setItem(
      PREFERENCES_KEY,
      JSON.stringify({
        ...preferences,
        // Ensure we never persist unexpected keys
        lastSearch: {
          dateRange: preferences.lastSearch.dateRange,
          bbox: preferences.lastSearch.bbox,
          variables: preferences.lastSearch.variables,
          collections: preferences.lastSearch.collections,
          searchText: preferences.lastSearch.searchText.slice(0, 200),
        },
      })
    )
  } catch (err) {
    console.warn('Failed to persist preferences', err)
  }
}

export const usePreferencesStore = create<PreferencesState>((set, get) => ({
  ...defaultPreferences,
  ...loadPreferences(),
  setBaseMap: (baseMap) => {
    set({ baseMap })
    persistPreferences({ ...get(), baseMap })
  },
  setColorScheme: (colorScheme) => {
    set({ colorScheme })
    persistPreferences({ ...get(), colorScheme })
  },
  setLayerOrder: (layerOrder) => {
    set({ layerOrder })
    persistPreferences({ ...get(), layerOrder })
  },
  setLastSearch: (lastSearch) => {
    set({ lastSearch })
    persistPreferences({ ...get(), lastSearch })
  },
}))
