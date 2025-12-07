import { create } from 'zustand'

export type BaseMapStyle = 'osm' | 'satellite'
export type ColorScheme = 'default' | 'high-contrast'

export interface PreferencesState {
  baseMap: BaseMapStyle
  colorScheme: ColorScheme
  layerOrder: string[]
  setBaseMap: (baseMap: BaseMapStyle) => void
  setColorScheme: (scheme: ColorScheme) => void
  setLayerOrder: (order: string[]) => void
}

const PREFERENCES_KEY = 'frontend.preferences.v1'

const defaultPreferences = {
  baseMap: 'osm' as BaseMapStyle,
  colorScheme: 'default' as ColorScheme,
  layerOrder: [] as string[],
}

function loadPreferences() {
  if (typeof window === 'undefined') return defaultPreferences

  try {
    const raw = localStorage.getItem(PREFERENCES_KEY)
    if (!raw) return defaultPreferences
    const parsed = JSON.parse(raw)
    return {
      baseMap: (parsed.baseMap as BaseMapStyle) || defaultPreferences.baseMap,
      colorScheme:
        (parsed.colorScheme as ColorScheme) || defaultPreferences.colorScheme,
      layerOrder: Array.isArray(parsed.layerOrder)
        ? (parsed.layerOrder as string[])
        : defaultPreferences.layerOrder,
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
}) {
  if (typeof window === 'undefined') return
  try {
    localStorage.setItem(PREFERENCES_KEY, JSON.stringify(preferences))
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
}))
