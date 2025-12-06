# Data Model: React Frontend for Scientific Raster Data Platform

**Purpose**: Describe key frontend-facing domain entities used across search, map visualization, and timeseries workflows. Implementation-agnostic.

## Entities

### Dataset
- **id**: string (STAC item id)
- **title**: string
- **description**: string
- **bbox**: [minLon, minLat, maxLon, maxLat]
- **temporalExtent**: { start: datetime, end: datetime }
- **variables**: array of `Variable`
- **assets**: map<string, assetHref>
- **thumbnailUrl**: string | null
- **collectionId**: string

### Variable
- **name**: string
- **units**: string
- **description**: string
- **assetKey**: string (links to asset)

### Collection
- **id**: string
- **title**: string
- **description**: string
- **childCollections**: array<string>
- **items**: array<string> (Dataset ids)
- **temporalExtent**: { start: datetime, end: datetime }

### MapLayer
- **datasetId**: string
- **variable**: string
- **opacity**: number (0-1)
- **visible**: boolean
- **zIndex**: number
- **colorScale**: string (palette id)
- **legend**: { min: number, max: number, ramp: string }

### TimeseriesQuery
- **lon**: number
- **lat**: number
- **start**: datetime
- **end**: datetime
- **variables**: array<string>
- **datasetIds**: array<string>

### TimeseriesDataPoint
- **timestamp**: datetime
- **variable**: string
- **value**: number
- **datasetId**: string

### SearchCriteria
- **keywords**: string
- **dateRange**: { start: datetime, end: datetime }
- **bbox**: [minLon, minLat, maxLon, maxLat] | null
- **variables**: array<string>
- **collections**: array<string>

### UserPreferences
- **baseMap**: string
- **theme**: string
- **chartPalette**: string
- **layerOrder**: array<string> (dataset ids)
- **recentSearches**: array<SearchCriteria>

## Relationships
- `Collection` 1..* `Dataset`
- `Dataset` 1..* `Variable`
- `MapLayer` references one `Dataset` and one `Variable`
- `TimeseriesQuery` references one or many `Dataset` and `Variable`
- `TimeseriesDataPoint` belongs to one `Dataset` and one `Variable`

## Validation Rules
- `bbox` coordinates within valid ranges (-180..180 lon, -90..90 lat)
- `dateRange.start <= dateRange.end`
- `opacity` between 0 and 1
- `variables` array non-empty for timeseries queries
- `datasetIds` array non-empty for timeseries queries

## State Transitions (Map Layers)
- **addLayer**: +MapLayer with default opacity=1, visible=true, top zIndex
- **updateLayer**: change opacity/variable/visibility/zIndex
- **removeLayer**: delete layer and detach legend
- **toggleVisibility**: visible <-> hidden (preserve state)

## State Transitions (Timeseries)
- **submitQuery**: validate inputs → call API → set loading
- **receiveData**: store series keyed by dataset+variable → render Plotly
- **changeLocation**: clear prior selection or add comparison (configurable)
- **exportCsv**: generate CSV from current series
